import Foundation

/// Cuts the finished notes into the blocks the interface is built from.
///
/// **This exists because the blocks were empty.** `NoteReduction.notes(from:)`
/// passed the draft cards straight through as the finished blocks, which worked
/// for as long as there were drafts. Nothing is summarised during a lecture any
/// more, so it was handed an empty array and returned one: the Markdown came
/// back from the model, the block list did not, nothing was written to the
/// store, and the window said "No notes yet" over a lecture the model had just
/// answered about in full.
///
/// A block is a `##` heading and everything under it. That is the same cut the
/// prompt asks the model to write, so this reads the answer's own structure
/// rather than imposing one.
///
/// **Where a block starts is anchored, not guessed.** Every section carries one
/// `**bold**` term — the prompt requires it, once per section — and the
/// transcript the model was given carries a timestamp per line. Looking the
/// term up in the transcript gives the minute that section is about. Where a
/// term cannot be found, the section falls back to its share of the recording,
/// which is a worse answer and still a usable one: a chapter row is a place to
/// jump to, not a claim about a word.
nonisolated enum NoteSections {

    /// The blocks of one finished set of notes, numbered from one.
    static func blocks(
        from markdown: String,
        transcript: [TranscriptLine],
        duration: TimeInterval? = nil
    ) -> [NoteBlock] {
        let sections = split(markdown)
        guard !sections.isEmpty else { return [] }

        let end = duration ?? transcript.last?.end ?? 0
        var starts = anchored(sections, in: transcript, end: end)

        // Times must not run backwards: the sections are in the order things
        // were said, so a later section anchored earlier than its predecessor
        // found the wrong occurrence of its term.
        for index in starts.indices.dropFirst() where starts[index] < starts[index - 1] {
            starts[index] = starts[index - 1]
        }

        return sections.enumerated().map { index, text in
            NoteBlock(
                number: index + 1,
                markdown: text,
                start: starts[index],
                end: index + 1 < starts.count ? starts[index + 1] : end,
                state: .written
            )
        }
    }

    // MARK: - Cutting

    /// The Markdown, cut at every `##` heading.
    ///
    /// Anything before the first heading is kept as its own section rather than
    /// dropped: a model that opens with a sentence and then starts its headings
    /// has written something, and throwing it away would lose it silently.
    static func split(_ markdown: String) -> [String] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var sections: [[String]] = []
        var current: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("## ") {
                if !current.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append(current)
                }
                current = [line]
            } else {
                current.append(line)
            }
        }
        if !current.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(current)
        }

        return sections.map {
            $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Anchoring

    private static func anchored(
        _ sections: [String],
        in transcript: [TranscriptLine],
        end: TimeInterval
    ) -> [TimeInterval] {
        var searchFrom = 0

        return sections.enumerated().map { index, section in
            // The section's own share of the recording, used when its term is
            // nowhere in the transcript.
            let share = sections.isEmpty ? 0 : end * Double(index) / Double(sections.count)

            guard let term = boldTerm(in: section) else { return share }
            guard let found = transcript[searchFrom...].firstIndex(where: {
                $0.text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }) else { return share }

            searchFrom = found
            return transcript[found].start
        }
    }

    /// The one `**term**` the prompt asks each section to mark.
    static func boldTerm(in section: String) -> String? {
        guard let open = section.range(of: "**") else { return nil }
        guard let close = section.range(of: "**", range: open.upperBound..<section.endIndex) else { return nil }

        let term = String(section[open.upperBound..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A one- or two-letter "term" matches everywhere and anchors nothing.
        return term.count >= 3 ? term : nil
    }
}
