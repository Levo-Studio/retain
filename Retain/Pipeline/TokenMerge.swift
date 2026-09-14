import Foundation

/// Joins the model's sub-word tokens back into words with times.
///
/// Parakeet decodes SentencePiece pieces, not words: "Seitentabelle" comes back
/// as something like `▁Seiten`, `tabelle`, each with its own start and end. A
/// word's time is the start of its first piece and the end of its last, and
/// getting that wrong is what makes clicking a line in the transcript land in
/// the wrong second.
///
/// Pure, so the rule is testable without a model — which matters, because the
/// alternative is finding out from a 90-minute recording.
nonisolated enum TokenMerge {

    /// SentencePiece marks a word boundary with U+2581 LOWER ONE EIGHTH BLOCK.
    ///
    /// **Both forms have to be accepted, and finding that out cost a wrong
    /// transcript.** FluidAudio's streaming path hands the marker through as it
    /// is, but its batch path runs every timing token through
    /// `normalizedTimingToken`, which replaces U+2581 with a plain space before
    /// anyone downstream sees it. Matching only on U+2581 means no token ever
    /// looks like the start of a word, every word in a ninety-minute lecture
    /// merges into one, and what comes out is a single line with one speaker —
    /// which is what happened, and which no unit test built from assumed input
    /// would have caught.
    static let wordBoundary: Character = "\u{2581}"

    /// Whether this piece begins a new word.
    static func startsWord(_ piece: String) -> Bool {
        guard let first = piece.first else { return false }
        return first == wordBoundary || first == " "
    }

    /// The piece without whichever boundary marker it carried.
    static func stripBoundary(_ piece: String) -> String {
        String(piece.drop { $0 == wordBoundary || $0 == " " })
    }

    /// Merges timed tokens into timed words.
    ///
    /// Tokens the model emits for its own bookkeeping — the language tags of
    /// the multilingual vocabulary, `<blank>`, anything else in angle brackets
    /// — are dropped rather than rendered, because they are not words anyone
    /// said.
    static func words(from tokens: [(token: String, start: TimeInterval, end: TimeInterval)]) -> [WordTiming] {
        var words: [WordTiming] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                words.append(WordTiming(text: trimmed, start: start, end: end))
            }
            text = ""
        }

        for token in tokens {
            let piece = token.token
            guard !isSpecial(piece) else { continue }

            let stripped = stripBoundary(piece)
            let isWordStart = startsWord(piece)

            if isWordStart || text.isEmpty {
                flush()
                text = stripped
                start = token.start
                end = token.end
            } else {
                text += stripped
                // A continuation only ever extends the word; a piece whose end
                // time comes back earlier than the one before it must not pull
                // the word's end backwards, or the line's duration goes
                // negative and the seek target with it.
                end = max(end, token.end)
            }
        }
        flush()

        return words
    }

    /// Whether a piece is model bookkeeping rather than something that was
    /// said: `<en-US>`, `<blank>`, `<pad>` and their kind.
    static func isSpecial(_ token: String) -> Bool {
        let bare = stripBoundary(token)
        return bare.hasPrefix("<") && bare.hasSuffix(">") && bare.count > 2
    }
}
