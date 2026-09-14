import AVFoundation

/// The format everything downstream of the writer speaks.
///
/// 16 kHz mono signed 16-bit, written into a CAF. That is what FluidAudio's
/// models want on both the streaming and the batch side, so converting once on
/// the way in costs less than converting on every pass over the recording
/// afterwards. It is also small: an hour and a half of lecture is about
/// 173 MB, against 1 GB if the device's own 48 kHz stereo float were kept.
///
/// CAF rather than WAV because WAV's 32-bit size field caps a file at 4 GB and
/// its header has to be rewritten on close, which means a recording that
/// crashes mid-lecture is a file no tool will open. A CAF grows without a cap
/// and a truncated one still plays up to the point it stopped — which for a
/// recording you cannot repeat is the difference between losing the tail and
/// losing the lecture.
nonisolated enum CaptureFormat {

    static let sampleRate: Double = 16_000
    static let channelCount: AVAudioChannelCount = 1
    static let bitDepth = 16

    static let fileExtension = "caf"

    /// What the writer converts into: 16 kHz mono, and still **float**.
    ///
    /// The rate and the channel count are the point of the conversion. The
    /// sample type is not, and float is deliberate even though the file on disk
    /// is Int16: the same block goes to the live transcriber, which wants float,
    /// and to `AVAudioFile`, which quantises it on the way out. Converting to
    /// Int16 here would mean converting straight back to float for every block
    /// of a ninety-minute lecture, and would lose the only step that is actually
    /// lossy twice instead of once.
    ///
    /// Deinterleaved because that is what one channel of
    /// `AVAudioFile(forWriting:settings:)`'s processing format is, and
    /// `write(from:)` accepts nothing else.
    ///
    /// Optional rather than force-unwrapped even though the arguments are
    /// constants AVAudioFormat documents as valid: a nil here would be a crash
    /// on a user's machine in the middle of a lecture, and refusing to start
    /// with a message is always the better end of that.
    static var processing: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )
    }

    /// Settings for `AVAudioFile(forWriting:settings:)`.
    static var fileSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channelCount),
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// The format the ring buffer's contents are in: one channel of the
    /// device's own stream, at the device's own rate, still float.
    ///
    /// The audio callback may only memcpy, so it cannot downmix, cannot
    /// resample and cannot quantise. What it can do is copy one channel out of
    /// the buffer it was handed, which is what it does, and this is the format
    /// that leaves it.
    static func tapped(at rate: Double) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)
    }
}
