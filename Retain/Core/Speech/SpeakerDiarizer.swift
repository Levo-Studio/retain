import FluidAudio
import Foundation

/// Works out who was speaking when, after the lecture.
///
/// Offline rather than live, because clustering needs to have heard every voice
/// before it can decide how many there are. The result is a set of anonymous
/// clusters; turning those into "the lecturer" and "the room" is
/// `SpeakerRoles`, which is a judgement about lectures and lives in the
/// pipeline where it can be tested.
///
/// ## Not available on macOS 14
///
/// FluidAudio's own source carries a warning: macOS 14 has an Apple bug in BNNS
/// that crashes Core ML predictions on the BNNS CPU path with `EXC_BAD_ACCESS`
/// inside `libBNNS`. Their matrix reproduced it 1200 times out of 1200 with
/// `.cpuAndNeuralEngine` on hosts without a Neural Engine, and intermittently
/// on Apple Silicon whenever a prediction falls back off the ANE. Apple fixed
/// it in macOS 15. The reported mitigation is GPU-enabled routing — which is
/// exactly what hard rule 4 forbids, and which FluidAudio itself marks
/// unverified.
///
/// So on macOS 14 diarization does not run. Every line keeps `.unknown` as its
/// speaker and the rest of the lecture — recording, both transcripts, notes,
/// search — is unaffected. **This is a placeholder for a decision, not the
/// decision:** the deployment target and the ANE routing are both locked, and
/// which of them gives way is the owner's call.
actor SpeakerDiarizer {

    enum Availability: Equatable, Sendable {
        case available
        /// macOS 14, where running it risks a crash. See the type comment.
        case unsupportedOperatingSystem
    }

    static var availability: Availability {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15
            ? .available
            : .unsupportedOperatingSystem
    }

    /// Diarizes a finished recording.
    ///
    /// - Returns: the segments, or an empty array when diarization did not run.
    ///   Empty rather than a thrown error: a lecture without speaker labels is
    ///   still a lecture, and failing the whole pass because the room could not
    ///   be told apart from the lectern would be the wrong trade.
    func segments(for url: URL, progress: (@Sendable (Double) -> Void)? = nil) async -> [SpeakerSegment] {
        guard Self.availability == .available else { return [] }

        do {
            // Built fresh per lecture rather than cached on the actor.
            // OfflineDiarizerManager is not Sendable, so a stored one cannot be
            // handed to an async call without Swift refusing it — and the
            // expensive half, the model download, is cached inside FluidAudio
            // anyway. What is paid again is loading the weights, once per
            // lecture, after it has already ended.
            //
            // No MLModelConfiguration passed anywhere in here: the default is
            // .cpuAndNeuralEngine and hard rule 4 says it stays that way.
            let manager = OfflineDiarizerManager()
            try await manager.prepareModels()

            let result = try await manager.process(url) { done, total in
                guard total > 0 else { return }
                progress?(Double(done) / Double(total))
            }

            return result.segments.map {
                SpeakerSegment(
                    speakerID: $0.speakerId,
                    start: TimeInterval($0.startTimeSeconds),
                    end: TimeInterval($0.endTimeSeconds)
                )
            }
        } catch {
            return []
        }
    }
}
