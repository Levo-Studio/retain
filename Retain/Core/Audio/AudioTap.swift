import AVFoundation

/// The microphone tap: one `memcpy` per buffer, on the audio thread.
///
/// **A type of its own for the same reason as `DrainTimer`, and it cost the
/// same crash.** The tap block used to be a closure literal written inside
/// `RecordingEngine`, which is `@MainActor` — this project defaults every type
/// to the main actor. `installTap(onBus:bufferSize:format:block:)` takes its
/// block through a `@preconcurrency` declaration, so the mismatch was not an
/// error: the compiler emitted a runtime isolation check at the top of the
/// block instead. The first buffer to arrive ran that check on Core Audio's own
/// thread, where it called `dispatch_assert_queue` and trapped. Every recording
/// died the moment the microphone opened.
///
/// It is also a violation of hard rule 5 quite apart from the crash. That check
/// is a Swift runtime call, in a callback that is allowed one `memcpy` and a
/// timestamp and nothing else — no allocation, no lock, no logging, and
/// certainly nothing that can block on a queue assertion.
///
/// So the block lives here, in a `nonisolated` type, where a closure literal is
/// nonisolated by construction and cannot quietly become the main actor's
/// again.
nonisolated enum AudioTap {

    /// Installs the tap that fills `ring` from `node`.
    ///
    /// - Parameters:
    ///   - node: the input node in the app. Any `AVAudioNode` is accepted so
    ///     that a test can run a real tap off a player node and never touch the
    ///     microphone — which is what makes the crash above testable at all.
    ///   - format: the hardware's own format. Retain does not ask for one; see
    ///     the buffer size below.
    static func install(on node: AVAudioNode, format: AVAudioFormat?, filling ring: AudioRingBuffer) {
        // Buffer size 0 lets the hardware decide, which is what makes the
        // AudioHardwarePowerHint in Info.plist effective: Core Audio hands us
        // 4096-frame buffers instead of 512, eight times fewer wakeups for the
        // same audio. Asking for a size here would override that and undo the
        // single largest power saving Retain has.
        node.installTap(onBus: 0, bufferSize: 0, format: format) { buffer, _ in
            // ---- audio thread. Hard rule 5 applies to every line below. ----
            //
            // One memcpy, through the ring buffer's C implementation. No
            // allocation, no lock, no logging, no conversion, no Swift runtime
            // call that could do any of those.
            //
            // Only channel 0 is taken. Downmixing several channels is
            // arithmetic over every sample, which belongs on the writer queue
            // and not here — and for speech from a microphone, one channel is
            // what the models want anyway. A device whose useful signal is not
            // on channel 0 would need the copy widened to all channels and the
            // downmix done in RecordingWriter, never here.
            guard let channel = buffer.floatChannelData?[0] else { return }
            ring.write(channel, count: Int(buffer.frameLength))
            // ---- end audio thread ----
        }
    }

    static func remove(from node: AVAudioNode) {
        node.removeTap(onBus: 0)
    }
}
