import Foundation

// MARK: - Runs

/// A stretch of text inside one line of a note, with whatever marks it carries.
///
/// A run is the smallest piece that is drawn the same way throughout, which is
/// why "is it an emphasised term" and "is it inside a user's highlight" live on
/// the same value rather than in two parallel structures: the two can overlap
/// on the same words, and a run is where that overlap is resolved once.
nonisolated struct RetainInlineRun: Sendable, Equatable, Hashable {

    var text: String

    /// The model wrote this as `**…**`. The design draws it a weight up, in the
    /// primary ink, on the term-highlight background.
    var isTerm: Bool = false

    /// The user marked this passage in the finished notes.
    var isHighlighted: Bool = false
}

// MARK: - Elements

/// One block-level thing in a note. The design draws these three and nothing
/// else.
nonisolated enum RetainNoteElement: Sendable, Equatable, Hashable {
    case heading([RetainInlineRun])
    case paragraph([RetainInlineRun])
    case bulletList([[RetainInlineRun]])
}

// MARK: - Parsing

/// Turns one note block's Markdown into the elements the design draws.
///
/// It renders rather than re-validates. `Pipeline/NoteMarkdown` already took
/// the tables, fences, images, links and stray heading levels out after
/// decoding, so anything reaching here is already inside the subset — and a
/// renderer that checked again would be a second, quietly different opinion
/// about what is allowed.
///
/// What it does still do is fail gracefully: text that contains none of the
/// three shapes comes out as one paragraph, which is what the model writes on a
/// bad day and what the screen has to draw anyway.
nonisolated enum RetainMarkdown {

    /// The Markdown as elements, with any user highlights applied.
    ///
    /// Highlight ranges are character offsets into `plainText(of:)` — the text
    /// as it is read on screen, not as it is spelled in Markdown. That is the
    /// text the user selected over, so it is the only offset that survives the
    /// emphasis markers being invisible.
    static func elements(of markdown: String, highlights: [Range<Int>] = []) -> [RetainNoteElement] {
        let parsed = parse(markdown)
        guard !highlights.isEmpty else { return parsed }
        return applying(highlights, to: parsed)
    }

    /// The elements' text as it reads on screen: headings, paragraphs and
    /// bullet items, one per line.
    static func plainText(of elements: [RetainNoteElement]) -> String {
        var lines: [String] = []
        for element in elements {
            switch element {
            case let .heading(runs), let .paragraph(runs):
                lines.append(runs.map(\.text).joined())
            case let .bulletList(items):
                lines.append(contentsOf: items.map { $0.map(\.text).joined() })
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Blocks

    private static func parse(_ markdown: String) -> [RetainNoteElement] {
        var elements: [RetainNoteElement] = []
        var paragraph: [String] = []
        var bullets: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                elements.append(.paragraph(inlineRuns(paragraph.joined(separator: " "))))
                paragraph = []
            }
            if !bullets.isEmpty {
                elements.append(.bulletList(bullets.map(inlineRuns)))
                bullets = []
            }
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flush()
                continue
            }

            if line.hasPrefix("#") {
                flush()
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { elements.append(.heading(inlineRuns(text))) }
                continue
            }

            if line.hasPrefix("- ") {
                if !paragraph.isEmpty {
                    elements.append(.paragraph(inlineRuns(paragraph.joined(separator: " "))))
                    paragraph = []
                }
                bullets.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }

            if !bullets.isEmpty {
                elements.append(.bulletList(bullets.map(inlineRuns)))
                bullets = []
            }
            paragraph.append(line)
        }

        flush()
        return elements
    }

    // MARK: Inline

    /// Splits a line into plain and emphasised runs.
    ///
    /// `**…**` and `__…__` are the emphasised term. A lone `*` or `_` is left
    /// as typed — the design draws no italic, and turning one into emphasis
    /// would put a style on screen that was never designed. Backticks are
    /// dropped and their text kept, which is what `NoteMarkdown.plainText`
    /// already treats them as.
    static func inlineRuns(_ text: String) -> [RetainInlineRun] {
        let characters = Array(text)
        var runs: [RetainInlineRun] = []
        var plain = ""
        var index = 0

        func flushPlain() {
            guard !plain.isEmpty else { return }
            runs.append(RetainInlineRun(text: plain))
            plain = ""
        }

        while index < characters.count {
            let character = characters[index]

            if character == "`" {
                index += 1
                continue
            }

            if character == "*" || character == "_",
               index + 1 < characters.count,
               characters[index + 1] == character,
               let close = closingMarker(character, in: characters, after: index + 2) {
                let term = String(characters[(index + 2)..<close]).replacingOccurrences(of: "`", with: "")
                if !term.isEmpty {
                    flushPlain()
                    runs.append(RetainInlineRun(text: term, isTerm: true))
                    index = close + 2
                    continue
                }
            }

            plain.append(character)
            index += 1
        }

        flushPlain()
        return runs
    }

    private static func closingMarker(_ marker: Character, in characters: [Character], after start: Int) -> Int? {
        var index = start
        while index + 1 < characters.count {
            if characters[index] == marker, characters[index + 1] == marker { return index }
            index += 1
        }
        return nil
    }

    // MARK: Highlights

    /// Splits runs wherever a highlight starts or ends, so that a term and a
    /// highlight that cover the same words end up on one run carrying both
    /// rather than one of them winning.
    private static func applying(
        _ highlights: [Range<Int>],
        to elements: [RetainNoteElement]
    ) -> [RetainNoteElement] {
        var offset = 0
        var out: [RetainNoteElement] = []

        /// Every line advances the offset by its own length plus the newline
        /// that `plainText(of:)` joins it with.
        func line(_ runs: [RetainInlineRun], isFirst: Bool) -> [RetainInlineRun] {
            if !isFirst { offset += 1 }
            return split(runs, from: &offset, highlights: highlights)
        }

        var isFirstLine = true
        for element in elements {
            switch element {
            case let .heading(runs):
                out.append(.heading(line(runs, isFirst: isFirstLine)))
                isFirstLine = false
            case let .paragraph(runs):
                out.append(.paragraph(line(runs, isFirst: isFirstLine)))
                isFirstLine = false
            case let .bulletList(items):
                var marked: [[RetainInlineRun]] = []
                for item in items {
                    marked.append(line(item, isFirst: isFirstLine))
                    isFirstLine = false
                }
                out.append(.bulletList(marked))
            }
        }

        return out
    }

    private static func split(
        _ runs: [RetainInlineRun],
        from offset: inout Int,
        highlights: [Range<Int>]
    ) -> [RetainInlineRun] {
        var out: [RetainInlineRun] = []

        for run in runs {
            var text = ""
            var isHighlighted = highlights.contains { $0.contains(offset) }

            for character in run.text {
                let hit = highlights.contains { $0.contains(offset) }
                if hit != isHighlighted, !text.isEmpty {
                    out.append(RetainInlineRun(text: text, isTerm: run.isTerm, isHighlighted: isHighlighted))
                    text = ""
                }
                isHighlighted = hit
                text.append(character)
                offset += 1
            }

            if !text.isEmpty {
                out.append(RetainInlineRun(text: text, isTerm: run.isTerm, isHighlighted: isHighlighted))
            }
        }

        return out
    }
}
