import AVFoundation
import Testing

@testable import Retain

/// The microphone tap — and the crash that made every recording die the moment
/// it started.
///
/// The tap block used to be a closure literal inside `RecordingEngine`, which
/// is `@MainActor` because this project puts every type there by default.
/// `installTap(onBus:bufferSize:format:block:)` takes its block through a
/// `@preconcurrency` declaration, so the mismatch was not a build error: the
/// compiler emitted a runtime isolation check at the top of the block. The
/// first buffer to arrive ran that check on Core Audio's own thread, where it
/// called `dispatch_assert_queue` and trapped. `EXC_BREAKPOINT`, nothing on
/// screen, every time.
///
/// **This runs a real tap and never opens the microphone.** The audio comes
/// from a player node, so there is no permission to grant and nothing to
/// prompt; what is being tested is the block's isolation, and Core Audio does
/// not care where the samples came from. If the block belonged to the main
/// actor again, this test would not fail — it would take the test process with
/// it, which is the loudest a regression of this shape can be made.
@Suite("Audio tap", .serialized)
struct AudioTapTests {

    /// A second of 440 Hz at 48 kHz, mono float — what a microphone hands over,
    /// without a microphone.
    private func tone(in format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames

        guard let channel = buffer.floatChannelData?[0] else { return nil }
        // Broken into steps rather than one expression: the type checker gives
        // up on the single-line version.
        let rate = format.sampleRate
        let step: Double = 2 * Double.pi * 440 / rate
        for frame in 0..<Int(frames) {
            channel[frame] = Float(sin(step * Double(frame)))
        }
        return buffer
    }

    @Test("A tap fills the ring buffer from the audio thread without trapping")
    func theTapRunsOffTheMainActor() async throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        )
        let ring = try #require(AudioRingBuffer(capacity: 48_000 * 4))

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // The mixer, not the input node: an input node opens the microphone and
        // asks for permission, and neither is what this is about.
        await AudioTap.install(on: engine.mainMixerNode, format: nil, filling: ring)
        defer { engine.mainMixerNode.removeTap(onBus: 0) }

        // Offline, so the test does not depend on a sound card and does not
        // play a tone at whoever is running it.
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: 4096
        )
        try engine.start()

        let buffer = try #require(tone(in: format))
        // `completionHandler:` on purpose: the argument-less overload is the
        // async one, and it waits for the buffer to finish playing. Nothing
        // plays until `renderOffline` below is called, so awaiting it here is a
        // deadlock — which is what it did, hanging the whole suite.
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()

        let output = try #require(
            AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)
        )
        var rendered: AVAudioFrameCount = 0
        while rendered < AVAudioFrameCount(format.sampleRate) {
            let status = try engine.renderOffline(4096, to: output)
            guard status == .success else { break }
            rendered += output.frameLength
        }

        engine.stop()

        // Reaching this line is most of the assertion: the old block trapped on
        // the first buffer and took the process with it.
        #expect(ring.available > 0, "the tap never wrote a sample")
    }
}
