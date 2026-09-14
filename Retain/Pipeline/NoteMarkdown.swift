import Foundation

/// Keeps the model's Markdown inside the subset the design draws.
///
/// The notes are Markdown because that is the shape a language model writes
/// well. What a language model also writes, unasked, is everything else
/// Markdown can do: an `#` heading because the card is "the title", a table
/// because the transcript mentioned three algorithms, a code fence around the
/// whole answer because it was told to produce structured output, a link to
/// Wikipedia because it knows one.
///
/// Every one of those breaks a layout drawn for prose. So the prompt asks for
/// the subset — and this enforces it afterwards, because a prompt is a request
/// and this is the guarantee.
///
/// **It repairs rather than rejects.** A card with a table in it is still a
/// card the student sat through three minutes for; dropping the table keeps the
/// rest. Nothing here changes the words.
nonisolated enum NoteMarkdown {

    /// The only heading level the notes have. Board 03 draws one size of
    /// heading and there is no second level under it.
    static let headingPrefix = "## "

    // MARK: - Cleaning

    static func sanitised(_ raw: String) -> String {
        var lines: [String] = []

        for line in raw.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A fence around the whole answer is the commonest thing a model
            // does when it has been told to produce structured output. The
            // delimiters go; what is between them is the answer.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { continue }

            // A table has no width to be drawn at in a 64ch column.
            if trimmed.hasPrefix("|") { continue }
            if isTableRule(trimmed) { continue }

            // A rule between sections is a divider the design does not draw.
            if isThematicBreak(trimmed) { continue }

            if trimmed.hasPrefix("#") {
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    lines.append(headingPrefix + inline(text))
                }
                continue
            }

            lines.append(inline(bulletNormalised(trimmed)))
        }

        return collapsed(lines).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The card's heading, or `nil` when the model wrote none.
    ///
    /// The case that breaks the chapter rail, which is why it is a question
    /// with an answer rather than an assumption.
    static func heading(of markdown: String) -> String? {
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }

            let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : String(text)
        }
        return nil
    }

    /// Every heading in a document, in order. The finished notes have several.
    static func headings(in markdown: String) -> [String] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { return nil }
            let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : String(text)
        }
    }

    /// The Markdown with its formatting taken off, for a prompt or for search.
    ///
    /// The reduce prompt carries every card, and the emphasis markers in them
    /// cost tokens while telling the next model nothing it needs.
    static func plainText(_ markdown: String) -> String {
        var text = markdown
        for marker in ["**", "__", "`"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                while trimmed.hasPrefix("#") { trimmed.removeFirst() }
                if trimmed.hasPrefix("- ") { trimmed.removeFirst(2) }
                return trimmed.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Steps

    /// Images out, links down to their text.
    ///
    /// A link in a note is a promise Retain cannot keep: there is no browser in
    /// the notes pane and no network to open one onto. Its text is usually the
    /// term it was wrapped around, so keeping the text loses nothing.
    private static func inline(_ line: String) -> String {
        var text = line.replacing(#/!\[[^\]]*\]\([^)]*\)/#, with: "")
        text = text.replacing(#/\[([^\]]*)\]\([^)]*\)/#) { match in match.output.1 }
        return text
    }

    /// `*` and `+` lists become `-` lists, which is the one spelling the
    /// renderer has to handle.
    private static func bulletNormalised(_ line: String) -> String {
        guard let first = line.first, "*+".contains(first) else { return line }
        let rest = line.dropFirst()
        guard rest.first == " " else { return line }
        return "-" + rest
    }

    private static func isTableRule(_ line: String) -> Bool {
        guard line.contains("-"), line.contains("|") else { return false }
        return line.allSatisfy { "-|: ".contains($0) }
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return line.allSatisfy { $0 == "-" } || line.allSatisfy { $0 == "*" } || line.allSatisfy { $0 == "_" }
    }

    /// One blank line between things, never three.
    private static func collapsed(_ lines: [String]) -> String {
        var out: [String] = []
        for line in lines {
            if line.isEmpty, out.last?.isEmpty ?? true { continue }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}
