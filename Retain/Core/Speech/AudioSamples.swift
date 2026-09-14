import AVFoundation
import Foundation

/// Reads a recording off disk as the float samples every model wants.
///
/// Retain writes 16 kHz mono Int16, which is already the target rate, so this
/// is a format conversion and not a resample. It is still done through
/// `AVAudioConverter` rather than by hand: a recording written before a format
/// change, or one a user dropped in, may be anything at all, and silently
/// misreading it would produce a transcript of noise rather than an error.
nonisolated enum AudioSamples {

    enum Failure: Error, Sendable {
        case unreadable(URL)
        case unsupportedFormat
    }

    /// Loads the whole file. Ninety minutes is about 86 million floats, or
    /// 345 MB — large, but the batch pass runs once, after the lecture, with
    /// the machine plugged in, and FluidAudio's own disk-backed path is chosen
    /// per call by the caller that needs it.
    static func load(_ url: URL) throws -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else {
            throw Failure.unreadable(url)
        }
        return try samples(from: file)
    }

    /// Loads one stretch of the file, for re-running a single block rather than
    /// the lecture.
    static func load(_ url: URL, from start: TimeInterval, to end: TimeInterval) throws -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else {
            throw Failure.unreadable(url)
        }

        let rate = file.processingFormat.sampleRate
        let first = AVAudioFramePosition(max(0, start) * rate)
        let last = AVAudioFramePosition(min(Double(file.length) / rate, end) * rate)
        guard last > first else { return [] }

        file.framePosition = first
        return try samples(from: file, frames: AVAudioFrameCount(last - first))
    }

    // MARK: -

    private static func samples(from file: AVAudioFile, frames: AVAudioFrameCount? = nil) throws -> [Float] {
        let wanted = frames ?? AVAudioFrameCount(file.length)
        guard wanted > 0 else { return [] }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: CaptureFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else { throw Failure.unsupportedFormat }

        let source = file.processingFormat
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw Failure.unsupportedFormat
        }

        // Read and convert in blocks rather than in one buffer: a 90-minute
        // file read whole would need the input and the output resident at the
        // same time, and the peak is what gets a background process killed.
        let blockFrames: AVAudioFrameCount = 16_000 * 60
        var result: [Float] = []
        result.reserveCapacity(Int(Double(wanted) * CaptureFormat.sampleRate / source.sampleRate))

        var remaining = wanted
        while remaining > 0 {
            let take = min(blockFrames, remaining)
            guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: take) else {
                throw Failure.unsupportedFormat
            }
            try file.read(into: input, frameCount: take)
            guard input.frameLength > 0 else { break }
            remaining -= input.frameLength

            let ratio = target.sampleRate / source.sampleRate
            let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
                throw Failure.unsupportedFormat
            }

            let supply = SampleSupply(input)
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, outStatus in
                guard let next = supply.take() else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                return next
            }
            guard status == .haveData || status == .inputRanDry else {
                throw Failure.unsupportedFormat
            }

            if let channel = output.floatChannelData?[0], output.frameLength > 0 {
                result.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
        }

        return result
    }
}

// MARK: -

/// Hands one buffer to `AVAudioConverter` and nothing afterwards. Same reason
/// as `SingleUseInput` in `RecordingWriter`: the input block is `@Sendable`
/// even though it is called synchronously.
private nonisolated final class SampleSupply: @unchecked Sendable {

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
