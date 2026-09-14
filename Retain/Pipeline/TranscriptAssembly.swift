import Foundation

/// Turns a stream of timed words plus a set of speaker segments into the lines
/// the transcript is read as.
///
/// The batch pass hands back one long string and a timing per word; the design
/// draws short lines with a timestamp and a speaker each. Where the breaks go
/// is a readability decision, not an audio one, so it lives here as a pure
/// function over values and is tested without a model.
///
/// A line ends when any of these is true:
///
/// - the speaker changes, which is the break a reader is actually looking for;
/// - the gap to the next word is longer than `pauseBreak`, because a pause is
///   where a thought ended;
/// - the line has reached `maximumDuration`, so a lecturer who does not pause
///   for two minutes still produces something clickable.
nonisolated enum TranscriptAssembly {

    /// A gap longer than this ends the line. Short enough to break at the end
    /// of a sentence, long enough not to break inside one — a speaker drawing
    /// breath mid-clause is well under half a second.
    static let pauseBreak: TimeInterval = 0.9

    /// No line runs longer than this, whatever the pauses did.
    ///
    /// Twenty seconds is about sixty words: a paragraph, and close enough to
    /// the audio that clicking the line lands where the reader meant.
    static let maximumDuration: TimeInterval = 20

    /// Assembles lines from words and speaker segments.
    ///
    /// - Parameters:
    ///   - words: timed words in order. Out-of-order input is not repaired; the
    ///     batch pass produces them in order and anything else is a defect
    ///     upstream that should be visible rather than smoothed over.
    ///   - segments: diarization output. Pass an empty array when diarization
    ///     did not run, and every line comes back `.unknown`.
    static func lines(from words: [WordTiming], segments: [SpeakerSegment] = []) -> [TranscriptLine] {
        guard !words.isEmpty else { return [] }

        let roles = SpeakerRoles.assign(segments)

        var lines: [TranscriptLine] = []
        var current: [WordTiming] = []
        var currentSpeaker: SpeakerRole = .unknown

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { current = []; return }

            lines.append(
                TranscriptLine(
                    start: first.start,
                    end: last.end,
                    text: trimmed,
                    speaker: currentSpeaker,
                    isProvisional: false
                )
            )
            current = []
        }

        for word in words {
            // The speaker is read at the middle of the word rather than at its
            // start: a word straddling a segment boundary belongs to whoever
            // said most of it, and reading the start alone flips attribution on
            // the first word after every handover.
            let midpoint = word.start + (word.end - word.start) / 2
            let speaker = SpeakerRoles.role(at: midpoint, in: segments, roles: roles)

            if current.isEmpty {
                currentSpeaker = speaker
                current.append(word)
                continue
            }

            let gap = word.start - (current.last?.end ?? word.start)
            let span = word.end - (current.first?.start ?? word.start)

            if speaker != currentSpeaker || gap > pauseBreak || span > maximumDuration {
                flush()
                currentSpeaker = speaker
                current.append(word)
            } else {
                current.append(word)
            }
        }
        flush()

        return lines
    }

    /// Replaces the live transcript with the batch one.
    ///
    /// The two passes are not merged word by word and deliberately so: the
    /// batch pass is the record, the live pass was feedback, and picking
    /// between them per word would produce a transcript that is neither. What
    /// is kept from the live pass is nothing at all — the marks and annotations
    /// a user made are anchored to times, not to lines, so they survive the
    /// swap on their own.
    ///
    /// Returned separately from the assembly so the caller can show the live
    /// lines until the batch pass is actually finished, rather than emptying
    /// the transcript while it runs.
    static func replacingProvisional(
        _ existing: [TranscriptLine],
        with final: [TranscriptLine]
    ) -> [TranscriptLine] {
        guard !final.isEmpty else { return existing }
        return final
    }
}
