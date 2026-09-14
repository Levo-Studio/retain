import AVFoundation
import Foundation
import Testing

@testable import Retain

/// Drives the writer end to end with a signal whose properties are known, so
/// the resample, the Int16 quantisation and the file on disk are all checked
/// against something rather than against "it did not crash".
///
/// No microphone is involved. The audio comes from a generator, which is the
/// only way to assert on the exact contents of the result — and the only way
/// these can run in CI or on a machine that has refused Retain the microphone.
@Suite("Recording writer")
struct RecordingWriterTests {

    private static let hardwareRate: Double = 48_000

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("retain-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("lecture.\(CaptureFormat.fileExtension)")
    }

    /// A sine at `frequency`, `seconds` long, at the hardware rate.
    private func tone(frequency: Double, seconds: Double, amplitude: Float = 0.5) -> [Float] {
        let count = Int(Self.hardwareRate * seconds)
        return (0..<count).map { index in
            amplitude * Float(sin(2 * .pi * frequency * Double(index) / Self.hardwareRate))
        }
    }

    /// Writes `samples` through a real writer and returns the finished file.
    private func write(_ samples: [Float], chunk: Int = 12_000) async throws -> URL {
        let url = temporaryURL()
        let ring = try #require(AudioRingBuffer(capacity: samples.count * MemoryLayout<Float>.size * 2))
        let writer = RecordingWriter(url: url, ring: ring, onProgress: { _ in }, onFailure: { _ in })

        let source = try #require(CaptureFormat.tapped(at: Self.hardwareRate))
        try writer.open(sourceFormat: source)

        var offset = 0
        while offset < samples.count {
            let count = min(chunk, samples.count - offset)
            samples.withUnsafeBufferPointer { buffer in
                _ = ring.write(buffer.baseAddress!.advanced(by: offset), count: count)
            }
            offset += count
            writer.drain()
        }

        await withCheckedContinuation { continuation in
            writer.close { continuation.resume() }
        }
        return url
    }

    private func read(_ url: URL) throws -> (file: AVAudioFile, samples: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { return (file, []) }

        // Read back as float so the assertions are about the signal rather than
        // about Int16 arithmetic.
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32,
                          sampleRate: file.processingFormat.sampleRate,
                          channels: 1,
                          interleaved: false)
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        try file.read(into: buffer)

        let channel = try #require(buffer.floatChannelData?[0])
        return (file, Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
    }

    // MARK: -

    @Test("The file on disk is 16 kHz mono, whatever the microphone was")
    func writesTheCanonicalFormat() async throws {
        let url = try await write(tone(frequency: 440, seconds: 0.5))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == CaptureFormat.sampleRate)
        #expect(file.fileFormat.channelCount == CaptureFormat.channelCount)
        #expect(url.pathExtension == "caf")

        // Signed 16-bit integer, not float and not 24-bit: the models want
        // Int16 and the size of a school day's recordings depends on it.
        let description = file.fileFormat.streamDescription.pointee
        #expect(description.mBitsPerChannel == UInt32(CaptureFormat.bitDepth))
        #expect(description.mFormatFlags & kAudioFormatFlagIsFloat == 0)
        #expect(description.mFormatID == kAudioFormatLinearPCM)
    }

    @Test("Three seconds in is three seconds out")
    func preservesDuration() async throws {
        let seconds = 3.0
        let url = try await write(tone(frequency: 440, seconds: seconds))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let file = try AVAudioFile(forReading: url)
        let written = Double(file.length) / file.fileFormat.sampleRate

        // A resampler has a few frames of latency at the start and the end, so
        // an exact match would be the wrong assertion. Ten milliseconds of
        // slack over three seconds catches an off-by-a-block error while
        // tolerating the filter.
        #expect(abs(written - seconds) < 0.01, "wrote \(written)s for \(seconds)s of input")
    }

    @Test("A ninety-minute lecture keeps time to within a second")
    func durationHoldsOverALecture() async throws {
        // The length that matters. Generated rather than recorded, so it runs
        // in a second or two: what is being checked is that the frame
        // accounting does not drift, which is a property of the arithmetic and
        // not of the clock.
        let seconds = 90.0 * 60.0
        let count = Int(Self.hardwareRate * seconds)

        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let chunk = 4096
        let ring = try #require(AudioRingBuffer(capacity: chunk * MemoryLayout<Float>.size * 8))
        let writer = RecordingWriter(url: url, ring: ring, onProgress: { _ in }, onFailure: { _ in })
        try writer.open(sourceFormat: try #require(CaptureFormat.tapped(at: Self.hardwareRate)))

        let block = [Float](repeating: 0.25, count: chunk)
        var written = 0
        while written < count {
            let handed = block.withUnsafeBufferPointer {
                ring.write($0.baseAddress!, count: min(chunk, count - written))
            }
            if handed {
                written += min(chunk, count - written)
            } else {
                writer.drain()
                // The drain is asynchronous; give it the chance to empty the
                // ring before offering the same block again.
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        await withCheckedContinuation { continuation in
            writer.close { continuation.resume() }
        }

        let file = try AVAudioFile(forReading: url)
        let result = Double(file.length) / file.fileFormat.sampleRate
        #expect(abs(result - seconds) < 1.0, "90 minutes of input produced \(result)s")
        #expect(ring.overruns > 0 || written == count)
    }

    @Test("The signal survives the trip at roughly the level it went in")
    func preservesLevel() async throws {
        let amplitude: Float = 0.5
        let url = try await write(tone(frequency: 440, seconds: 1.0, amplitude: amplitude))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (_, samples) = try read(url)
        #expect(!samples.isEmpty)

        // Skip the resampler's warm-up at both ends.
        let body = Array(samples[1000..<(samples.count - 1000)])
        let level = AudioLevel.measure(body)

        let expected = AudioLevel.decibels(amplitude)
        #expect(abs(level.peak - expected) < 1.0, "peak \(level.peak) dBFS, expected about \(expected)")
        #expect(!level.isSilent)
        #expect(!level.isClipping)
    }

    @Test("A 1 kHz tone is still 1 kHz after resampling to 16 kHz")
    func preservesFrequency() async throws {
        // 1 kHz is well under the 8 kHz Nyquist limit of the 16 kHz target, so
        // a correct resample keeps it and a broken one does not. Counting zero
        // crossings is enough to tell those apart and needs no FFT.
        let url = try await write(tone(frequency: 1000, seconds: 1.0))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (_, samples) = try read(url)
        let body = Array(samples[800..<(samples.count - 800)])

        var crossings = 0
        for index in 1..<body.count where (body[index - 1] < 0) != (body[index] < 0) {
            crossings += 1
        }

        let seconds = Double(body.count) / CaptureFormat.sampleRate
        let frequency = Double(crossings) / 2 / seconds
        #expect(abs(frequency - 1000) < 20, "measured \(frequency) Hz")
    }

    @Test("Silence in is silence out, not a file of noise")
    func preservesSilence() async throws {
        let url = try await write([Float](repeating: 0, count: 48_000))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (_, samples) = try read(url)
        #expect(!samples.isEmpty)
        #expect(AudioLevel.measure(samples).isSilent)
    }

    @Test("A device that changes rate mid-recording keeps writing to the same file")
    func survivesASampleRateChange() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let ring = try #require(AudioRingBuffer(capacity: 48_000 * MemoryLayout<Float>.size))
        let writer = RecordingWriter(url: url, ring: ring, onProgress: { _ in }, onFailure: { _ in })
        try writer.open(sourceFormat: try #require(CaptureFormat.tapped(at: 48_000)))

        let first = tone(frequency: 440, seconds: 0.5)
        first.withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, count: first.count) }
        writer.drain()
        try await Task.sleep(for: .milliseconds(100))

        // The user plugged in a microphone that runs at 44.1 kHz.
        writer.restart(sourceFormat: try #require(CaptureFormat.tapped(at: 44_100)))
        try await Task.sleep(for: .milliseconds(50))

        let second = (0..<22_050).map { index in
            0.5 * Float(sin(2 * .pi * 440 * Double(index) / 44_100))
        }
        second.withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, count: second.count) }
        writer.drain()

        await withCheckedContinuation { continuation in
            writer.close { continuation.resume() }
        }

        // One file, both halves in it. A device change must not start a second
        // recording that something downstream then has to stitch.
        let file = try AVAudioFile(forReading: url)
        let written = Double(file.length) / file.fileFormat.sampleRate
        #expect(written > 0.9, "expected about a second across both formats, got \(written)s")
        #expect(file.fileFormat.sampleRate == CaptureFormat.sampleRate)
    }

    @Test("Closing with nothing recorded still leaves a readable file")
    func emptyRecordingIsStillAFile() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let ring = try #require(AudioRingBuffer(capacity: 4096))
        let writer = RecordingWriter(url: url, ring: ring, onProgress: { _ in }, onFailure: { _ in })
        try writer.open(sourceFormat: try #require(CaptureFormat.tapped(at: Self.hardwareRate)))

        await withCheckedContinuation { continuation in
            writer.close { continuation.resume() }
        }

        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 0)
        #expect(file.fileFormat.sampleRate == CaptureFormat.sampleRate)
    }

    @Test("What goes into the file also goes to the live transcriber, as float")
    func handsEveryBlockToTheLiveTranscriber() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let collected = SampleCollector()
        let samples = tone(frequency: 440, seconds: 1.0)
        let ring = try #require(AudioRingBuffer(capacity: samples.count * MemoryLayout<Float>.size * 2))
        let writer = RecordingWriter(
            url: url,
            ring: ring,
            onProgress: { _ in },
            onFailure: { _ in },
            onSamples: { collected.append($0) }
        )
        try writer.open(sourceFormat: try #require(CaptureFormat.tapped(at: Self.hardwareRate)))

        samples.withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, count: samples.count) }
        writer.drain()

        await withCheckedContinuation { continuation in
            writer.close { continuation.resume() }
        }

        let handed = collected.all
        #expect(!handed.isEmpty, "nothing was handed to the live transcriber")

        // Frame for frame what the file got. The live transcript's times are
        // counted from this stream and the batch pass reads that one, so if the
        // two ever differ the two transcripts disagree about when a sentence
        // was said.
        let file = try AVAudioFile(forReading: url)
        #expect(handed.count == Int(file.length), "handed \(handed.count) frames, wrote \(file.length)")

        // And it is the signal rather than silence. The converter has to land
        // on float: an Int16 buffer has no float channel data at all, so the
        // live transcriber would be fed nothing and never notice.
        let body = Array(handed[1000..<(handed.count - 1000)])
        #expect(abs(AudioLevel.measure(body).peak - AudioLevel.decibels(0.5)) < 1.0)
    }

    @Test("Progress reports the duration and the level as the file grows")
    func reportsProgress() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let collected = ProgressCollector()
        let ring = try #require(AudioRingBuffer(capacity: 48_000 * MemoryLayout<Float>.size))
        let writer = RecordingWriter(
            url: url,
            ring: ring,
            onProgress: { collected.append($0) },
            onFailure: { _ in }
        )
        try writer.open(sourceFormat: try #require(CaptureFormat.tapped(at: Self.hardwareRate)))

        let samples = tone(frequency: 440, seconds: 1.0)
        samples.withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, count: samples.count) }
        writer.drain()

        await withCheckedContinuation { continuation in
            writer.close { continuation.resume() }
        }

        let reports = collected.all
        #expect(!reports.isEmpty)
        #expect(reports.map(\.duration) == reports.map(\.duration).sorted(), "duration must only ever grow")
        #expect(reports.last.map { abs($0.duration - 1.0) < 0.05 } == true)
        #expect(reports.allSatisfy { $0.overruns == 0 })
        #expect(reports.contains { !$0.level.isSilent })
    }
}

// MARK: -

/// Gathers progress reports from the writer queue for the test to look at
/// afterwards.
private nonisolated final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [RecordingWriter.Progress] = []

    func append(_ progress: RecordingWriter.Progress) {
        lock.lock()
        defer { lock.unlock() }
        reports.append(progress)
    }

    var all: [RecordingWriter.Progress] {
        lock.lock()
        defer { lock.unlock() }
        return reports
    }
}

// MARK: -

/// Gathers what the writer hands to the live transcriber, in order, so the test
/// can compare it against the file afterwards.
private nonisolated final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ block: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: block)
    }

    var all: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}
