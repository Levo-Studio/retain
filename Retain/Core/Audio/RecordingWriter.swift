import AVFoundation
import Foundation

/// The consumer end of the ring buffer: drains it, resamples, quantises and
/// writes the CAF.
///
/// Everything the audio callback is not allowed to do happens here, on a
/// `.utility` queue — the resample, the Int16 quantisation `AVAudioFile` does on
/// the way to disk, the file I/O and the level measurement. `.utility` rather
/// than `.userInitiated` on purpose: this work has seconds of slack in the ring
/// buffer, and a lower QoS lets the scheduler keep it on the efficiency cores,
/// which over a whole school day is the difference the battery notices.
nonisolated final class RecordingWriter: @unchecked Sendable {

    enum Failure: Error, Sendable {
        case unsupportedFormat
        case couldNotCreateFile(URL, underlying: String)
        case writeFailed(underlying: String)
    }

    /// Where the recording is and how far it has got.
    struct Progress: Sendable {
        let url: URL
        let duration: TimeInterval
        let level: AudioLevel
        /// Blocks the audio callback could not hand over. Anything but zero is
        /// lost audio and a defect.
        let overruns: UInt64
    }

    private let ring: AudioRingBuffer
    private let queue = DispatchQueue(label: "studio.levo.retain.writer", qos: .utility)
    private let onProgress: @Sendable (Progress) -> Void
    private let onFailure: @Sendable (Failure) -> Void

    /// Every block of 16 kHz mono float, as it is written.
    ///
    /// This is how the live transcriber is fed. It hangs off the writer rather
    /// than off a second reader of the ring buffer because the ring buffer
    /// allows exactly one consumer — and because by this point the audio is
    /// already in the format the speech models want, so a second path would
    /// only resample it again.
    private let onSamples: @Sendable ([Float]) -> Void

    private let url: URL
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var scratch: [Float]
    private var writtenFrames: AVAudioFramePosition = 0
    private var draining = false

    /// How much is taken out of the ring in one pass. A quarter of a second at
    /// 48 kHz: big enough that the file is opened and written in long runs
    /// rather than in dribbles, small enough that the meter still moves at a
    /// readable rate.
    private static let drainSamples = 12_000

    init(
        url: URL,
        ring: AudioRingBuffer,
        onProgress: @escaping @Sendable (Progress) -> Void,
        onFailure: @escaping @Sendable (Failure) -> Void,
        onSamples: @escaping @Sendable ([Float]) -> Void = { _ in }
    ) {
        self.url = url
        self.ring = ring
        self.onProgress = onProgress
        self.onFailure = onFailure
        self.onSamples = onSamples
        self.scratch = [Float](repeating: 0, count: Self.drainSamples)
    }

    // MARK: - Lifecycle

    /// Opens the file. Call before the tap is installed so the first block has
    /// somewhere to go.
    func open(sourceFormat: AVAudioFormat) throws {
        try queue.sync {
            guard let target = CaptureFormat.processing else { throw Failure.unsupportedFormat }
            guard let converter = AVAudioConverter(from: sourceFormat, to: target) else {
                throw Failure.unsupportedFormat
            }

            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                // `settings` describes the file — Int16 CAF. The buffers handed
                // to write(from:) are float, and AVAudioFile quantises them on
                // the way out, so the single resample lands on float and both
                // the file and the live transcriber read the same block rather
                // than converting to Int16 and straight back out again for
                // every block of a ninety-minute lecture.
                //
                // No `commonFormat:`/`interleaved:` here, and that is load
                // bearing. This initialiser's processing format is
                // deinterleaved float32, which is exactly what the converter
                // produces. Naming the format explicitly and getting it wrong
                // does not fail as an error: AVAudioFile asserts inside
                // `writeFromBuffer:` and takes the process with it, in the
                // middle of a lecture.
                file = try AVAudioFile(forWriting: url, settings: CaptureFormat.fileSettings)
            } catch {
                throw Failure.couldNotCreateFile(url, underlying: error.localizedDescription)
            }

            self.converter = converter
            self.sourceFormat = sourceFormat
            self.writtenFrames = 0
        }
    }

    /// Asks for a pass over whatever is in the ring. Called on a timer from the
    /// engine — never from the audio callback.
    func drain() {
        queue.async { [self] in
            guard !draining else { return }
            draining = true
            defer { draining = false }
            drainLocked()
        }
    }

    /// Drains what is left and closes the file. After this the recording on
    /// disk is complete.
    func close(completion: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            drainLocked()
            // AVAudioFile writes its header as it goes and finalises on
            // deallocation; dropping the reference here is the close.
            file = nil
            converter = nil
            completion()
        }
    }

    /// Throws away what is buffered because it belongs to a format that is
    /// gone, and starts converting from the new one. The file keeps growing:
    /// a device change mid-lecture is a gap of milliseconds, not a new
    /// recording.
    func restart(sourceFormat newFormat: AVAudioFormat) {
        queue.async { [self] in
            drainLocked()
            ring.reset()
            guard let target = CaptureFormat.processing,
                  let converter = AVAudioConverter(from: newFormat, to: target) else {
                onFailure(.unsupportedFormat)
                return
            }
            self.converter = converter
            self.sourceFormat = newFormat
        }
    }

    // MARK: - The pass

    private func drainLocked() {
        guard let file, let converter, let sourceFormat else { return }

        while true {
            let samples = scratch.withUnsafeMutableBufferPointer { buffer in
                ring.read(into: buffer.baseAddress!, count: Self.drainSamples)
            }
            guard samples > 0 else { break }

            let level = scratch.withUnsafeBufferPointer { buffer in
                AudioLevel.measure(UnsafeBufferPointer(rebasing: buffer[0..<samples]))
            }

            guard let input = AVAudioPCMBuffer(
                pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples)
            ) else { break }
            input.frameLength = AVAudioFrameCount(samples)
            if let channel = input.floatChannelData?[0] {
                scratch.withUnsafeBufferPointer { source in
                    channel.update(from: source.baseAddress!, count: samples)
                }
            }

            guard let converted = convert(input, with: converter) else { break }

            // The live transcriber's feed. Handed over before the write so a
            // disk that has filled up still leaves the lecture transcribed on
            // screen for as long as the app is open.
            if let channel = converted.floatChannelData?[0], converted.frameLength > 0 {
                onSamples(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))))
            }

            do {
                try file.write(from: converted)
                writtenFrames += AVAudioFramePosition(converted.frameLength)
            } catch {
                onFailure(.writeFailed(underlying: error.localizedDescription))
                return
            }

            onProgress(
                Progress(
                    url: url,
                    duration: Double(writtenFrames) / CaptureFormat.sampleRate,
                    level: level,
                    overruns: ring.overruns
                )
            )

            // A short read means the ring is empty; anything else and there may
            // be more waiting.
            if samples < Self.drainSamples { break }
        }
    }

    private func convert(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        // One frame of headroom: the resampler can emit a frame more than the
        // ratio suggests at a block boundary, and a capacity that is one short
        // costs that frame silently.
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1

        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            return nil
        }

        // AVAudioConverter calls this block synchronously, on this thread,
        // until it says it has nothing more — but the block is typed
        // `@Sendable`, so capturing a mutable flag and a non-Sendable buffer
        // directly is four warnings and a promise the compiler cannot check.
        // Handing both to a box that gives the buffer up exactly once says the
        // same thing in a form that holds: the second call gets nil, whichever
        // thread it happens to arrive on.
        let supply = SingleUseInput(input)

        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            guard let next = supply.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return next
        }

        switch status {
        case .haveData, .inputRanDry:
            return output.frameLength > 0 ? output : nil
        case .endOfStream, .error:
            if let error { onFailure(.writeFailed(underlying: error.localizedDescription)) }
            return nil
        @unknown default:
            return nil
        }
    }
}

// MARK: -

/// Hands one buffer to `AVAudioConverter` and nothing afterwards.
///
/// The converter's input block is `@Sendable` even though it is called
/// synchronously on the calling thread, so the buffer it hands out and the
/// "already handed out" flag have to live somewhere the compiler accepts. The
/// lock makes the `@unchecked` honest rather than merely asserted; it is taken
/// twice per block of audio, off the audio thread.
private nonisolated final class SingleUseInput: @unchecked Sendable {

    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        defer { buffer = nil }
        return buffer
    }
}
