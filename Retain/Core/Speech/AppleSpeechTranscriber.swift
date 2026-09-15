import AVFoundation
import Foundation
import Speech

/// Apple's own on-device transcription, for the Macs that have it.
///
/// **macOS 26 only.** `SpeechAnalyzer` and `SpeechTranscriber` ship in 26 and
/// Retain's deployment target is 15, so this is reached through an availability
/// check and Parakeet remains what runs everywhere else. Nothing about the
/// pipeline changes: the same file goes in, the same word timings come out, and
/// `TranscriptAssembly` turns them into lines exactly as before.
///
/// Why it is worth having at all: in a 2026 benchmark over 13 000 recordings,
/// Apple's model had the lowest German word error rate of the engines tested —
/// 6.7 % on read-aloud speech, against Parakeet and WhisperKit. The owner asked
/// for it after that came up. Whether it wins on a real classroom, where the
/// speech is neither read nor close to the microphone, is a question only the
/// owner's own recordings can answer, which is why this sits **beside** the
/// existing pass rather than replacing it.
///
/// It is still entirely local. The model is downloaded once by the system and
/// held by the system; nothing about the audio leaves the Mac, which is the
/// whole product and not a preference.
@available(macOS 26.0, *)
nonisolated struct AppleSpeechTranscriber {

    /// What the pass produces, in the shape `LectureTranscription` already
    /// works in.
    struct Result: Sendable {
        let words: [WordTiming]
        let text: String
        let realTimeFactor: Double
    }

    /// The language Retain records in. Read from the same place the FluidAudio
    /// models take it, so there is one answer to what language a lecture is in.
    static var locale: Locale { Locale(identifier: SpeechModels.languageCode) }

    /// Whether this Mac can run it **and** has, or can fetch, the German model.
    ///
    /// `isAvailable` alone is not enough: the framework is there on every
    /// macOS 26 install and the language assets are not.
    static func isUsable() async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    // MARK: -

    /// Transcribes the whole file.
    ///
    /// - Parameter onProgress: 0…1 over the recording's own duration. The
    ///   analyzer reports what it has finalised rather than a percentage, so
    ///   the fraction is derived from where in the file that is.
    func transcribe(
        _ url: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Result {
        let started = Date()

        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate

        let transcriber = SpeechTranscriber(
            locale: Self.locale,
            // The time-indexed preset is the one that carries `audioTimeRange`
            // on every run of the answer. Without it there are no word timings,
            // and without word timings there is no timestamp beside a line, no
            // chapter to jump to and no citation to follow.
            preset: .timeIndexedTranscriptionWithAlternatives
        )

        try await Self.installAssetsIfNeeded(for: transcriber)

        // Collected before the analyzer is finished: `results` ends when the
        // analysis does, so reading it afterwards reads an ended sequence.
        let collecting = Task { () -> [SpeechTranscriber.Result] in
            var collected: [SpeechTranscriber.Result] = []
            for try await result in transcriber.results {
                collected.append(result)
                if duration > 0 {
                    let seconds = result.range.end.seconds
                    onProgress?(min(1, max(0, seconds / duration)))
                }
            }
            return collected
        }

        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: file,
            modules: [transcriber],
            // The file is the whole input; there is nothing after it.
            finishAfterFile: true
        )
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let results = try await collecting.value
        onProgress?(1)

        let words = results.flatMap(Self.words(in:))
        let text = results
            .map { String($0.text.characters) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let elapsed = Date().timeIntervalSince(started)
        return Result(
            words: words,
            text: text,
            realTimeFactor: elapsed > 0 ? duration / elapsed : 0
        )
    }

    // MARK: - The model on disk

    /// Fetches the German model if the system does not have it yet.
    ///
    /// Once per Mac, not once per lecture. `assetInstallationRequest` returns
    /// `nil` when there is nothing to fetch, which is the ordinary case after
    /// the first time.
    private static func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }
        try await request.downloadAndInstall()
    }

    // MARK: - Words out of an attributed string

    /// Every run of the answer that carries a time range, as a `WordTiming`.
    ///
    /// The transcriber attributes its text by run, and a run is a word or a
    /// short group of them. Runs without a time range are dropped rather than
    /// guessed at: a word with an invented timestamp is worse than a word that
    /// is missing, because the interface would offer to jump to it.
    private static func words(in result: SpeechTranscriber.Result) -> [WordTiming] {
        var words: [WordTiming] = []

        for run in result.text.runs {
            guard let range = run.audioTimeRange else { continue }

            let text = String(result.text[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite, end >= start else { continue }

            words.append(WordTiming(text: text, start: start, end: end))
        }

        return words
    }
}
