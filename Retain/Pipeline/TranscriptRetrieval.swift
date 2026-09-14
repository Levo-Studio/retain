import Foundation

/// Picks the part of a recording a question is about.
///
/// Ninety minutes of German is some seventy thousand characters, which is
/// twenty-five thousand tokens on a good day. A 7B model loaded at 4k cannot
/// see it, and the two obvious ways of making it fit are both wrong:
///
/// - **Truncating** answers the question from the first ten minutes and says
///   nothing about the fact. Hard rule 13 is the same objection in a different
///   place.
/// - **Summarising first** is what the notes already are. Asking a question
///   against the summary alone throws away the detail the question was asked
///   because the summary lacks.
///
/// So the transcript is *selected*: the lines that share vocabulary with the
/// question, plus the lines around them for context, in time order, up to a
/// token budget. It is keyword retrieval and not embeddings, deliberately —
/// embeddings mean a second model resident during a chat, and German keyword
/// overlap is unusually informative because the terms a student asks about are
/// long compound nouns that appear nowhere else in the recording.
nonisolated enum TranscriptRetrieval {

    /// Words that appear in every question and every answer and therefore
    /// separate nothing. Short German function words, plus the ones a question
    /// is built out of.
    static let stopWords: Set<String> = [
        "aber", "alle", "allem", "allen", "aller", "alles", "also", "auch", "auf", "aus",
        "bei", "beim", "bin", "bis", "dann", "das", "dass", "dem", "den", "denn", "der",
        "des", "die", "dies", "diese", "diesem", "diesen", "dieser", "dieses", "doch",
        "dort", "durch", "ein", "eine", "einem", "einen", "einer", "eines", "erklaer",
        "erklaere", "erklaeren", "etwa", "etwas", "fuer", "ganz", "gab", "geht", "gibt",
        "hab", "habe", "haben", "hat", "hatte", "heisst", "ich", "ihr", "immer", "ist",
        "kann", "koennen", "machen", "mehr", "mein", "mich", "mir", "mit", "nach", "nicht",
        "noch", "nun", "nur", "ober", "oder", "ohne", "sagen", "sagt", "schon", "sehr",
        "sein", "seine", "sich", "sie", "sind", "soll", "sollen", "sondern", "ueber",
        "und", "uns", "unser", "vom", "von", "vor", "war", "waren", "warum", "was",
        "wann", "weil", "welche", "welcher", "wenn", "wer", "werden", "wie", "wieder",
        "will", "wir", "wird", "wo", "wurde", "wurden", "zeig", "zeige", "zum", "zur",
        "zwischen",
    ]

    /// A word shorter than this tells nothing apart.
    static let minimumTermLength = 4

    /// How many lines either side of a hit come along.
    ///
    /// One. A transcript line is up to twenty seconds, so a hit plus its
    /// neighbours is about a minute — enough for the sentence the answer is in
    /// to have a beginning and an end, and cheap enough that a question with
    /// thirty hits still fits.
    static let contextLines = 1

    // MARK: - Terms

    /// The words of a question that are worth matching on.
    static func terms(in question: String) -> Set<String> {
        let folded = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let pieces = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })

        return Set(
            pieces
                .map(String.init)
                .filter { $0.count >= minimumTermLength && !stopWords.contains($0) }
        )
    }

    // MARK: - Selection

    /// The lines of `transcript` worth showing the model, in time order.
    ///
    /// - Parameter tokenBudget: how many tokens the transcript may take. When
    ///   the whole transcript fits, the whole transcript is returned — selection
    ///   only ever loses something, so it is not done when it is not needed.
    static func excerpt(
        of transcript: [TranscriptLine],
        for question: String,
        tokenBudget: Int
    ) -> [TranscriptLine] {
        guard !transcript.isEmpty, tokenBudget > 0 else { return [] }

        let whole = transcript.map(\.text).joined(separator: "\n")
        if TokenBudget.estimatedTokens(in: whole) <= tokenBudget {
            return transcript
        }

        let wanted = terms(in: question)
        let scores = transcript.map { line in score(line.text, against: wanted) }

        // A question whose words appear nowhere — "worum ging es hier
        // eigentlich" — gets an even sample of the whole recording rather than
        // its first ten minutes. The shape of the answer is then "about the
        // recording", which is what was asked.
        guard scores.contains(where: { $0 > 0 }) else {
            return evenSample(of: transcript, tokenBudget: tokenBudget)
        }

        let ranked = scores.enumerated()
            .filter { $0.element > 0 }
            .sorted { first, second in
                first.element == second.element ? first.offset < second.offset : first.element > second.element
            }
            .map(\.offset)

        var chosen: Set<Int> = []
        var used = 0

        for index in ranked {
            let window = max(0, index - contextLines)...min(transcript.count - 1, index + contextLines)
            let addition = window.filter { !chosen.contains($0) }
            let cost = addition.reduce(0) { $0 + TokenBudget.estimatedTokens(in: transcript[$1].text) }

            // Stop rather than skip ahead: the lines are in score order, so
            // anything still to come matters less than what has been taken, and
            // squeezing in a later short line over an earlier long one would
            // make the excerpt depend on line lengths instead of on relevance.
            guard used + cost <= tokenBudget else { break }

            chosen.formUnion(addition)
            used += cost
        }

        return chosen.sorted().map { transcript[$0] }
    }

    /// How many of the question's words a line contains.
    ///
    /// Substring rather than whole-word matching, because German inflects and
    /// compounds: a question about the *Seitentabelle* has to match a line that
    /// says *Seitentabellen*, and one about *Paging* has to match
    /// *Paging-Verfahren*.
    static func score(_ text: String, against terms: Set<String>) -> Int {
        guard !terms.isEmpty else { return 0 }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return terms.count { folded.contains($0) }
    }

    /// Lines spread evenly across the recording, up to the budget.
    static func evenSample(of transcript: [TranscriptLine], tokenBudget: Int) -> [TranscriptLine] {
        let average = max(1, TokenBudget.estimatedTokens(in: transcript.map(\.text).joined()) / transcript.count)
        let affordable = max(1, tokenBudget / average)
        guard affordable < transcript.count else { return transcript }

        let step = Double(transcript.count) / Double(affordable)
        return (0..<affordable).map { transcript[min(transcript.count - 1, Int(Double($0) * step))] }
    }
}
