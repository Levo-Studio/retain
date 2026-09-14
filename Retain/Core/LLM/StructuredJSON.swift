import Foundation

/// Gets a `Codable` answer out of whatever the model actually sent.
///
/// This is the bottom rung of the fallback ladder and the only one that has to
/// cope with prose. A 3–8B model told to answer in JSON will, often enough to
/// matter, wrap it in a fenced code block, introduce it with a sentence, put a
/// `<think>` block in front of it, or answer twice. None of that is a model
/// that failed; it is a model that answered in a shape the parser has to meet.
///
/// **What it will not do is repair broken JSON.** No trailing-comma fixing, no
/// quote guessing, no bracket balancing. A repaired object is a guess about
/// what the model meant, and a guessed note is worse than a missing one,
/// because nothing downstream can tell the two apart.
nonisolated enum StructuredJSON {

    /// Decodes the first candidate that both parses and satisfies `Answer`.
    ///
    /// Both conditions matter: a model that answers `{"error": "..."}` produces
    /// valid JSON that is not an answer, and treating the first parseable thing
    /// as the answer would hand that to `Codable` and fail there instead of
    /// moving on to the object further down the reply.
    static func decode<Answer: Decodable>(_ type: Answer.Type, from text: String) throws -> Answer {
        let decoder = JSONDecoder()
        var lastError: (any Error)?

        for candidate in candidates(in: text) {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                return try decoder.decode(Answer.self, from: data)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? SummarizationError.unreadableAnswer
    }

    /// Every substring of `text` that could be a JSON object or array, outermost
    /// first, in the order they appear.
    ///
    /// Separated from `decode` so it can be tested against real replies without
    /// a model and without a type to decode into.
    static func candidates(in text: String) -> [String] {
        let cleaned = withoutReasoning(text)
        var found: [String] = []

        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            found.append(trimmed)
        }

        found.append(contentsOf: fencedBlocks(in: cleaned))
        found.append(contentsOf: balancedSpans(in: cleaned))

        // Same span found by two routes — a fenced block that is also the only
        // balanced object — should be tried once.
        var seen: Set<String> = []
        return found.filter { seen.insert($0).inserted }
    }

    // MARK: - Steps

    /// Drops a leading `<think>…</think>` block.
    ///
    /// Reasoning models emit one before the answer, and its contents are prose
    /// that regularly contains braces — a draft of the JSON, usually — which
    /// would otherwise be found before the real answer.
    static func withoutReasoning(_ text: String) -> String {
        guard let open = text.range(of: "<think>"),
              let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex)
        else { return text }
        return String(text[text.startIndex..<open.lowerBound] + text[close.upperBound...])
    }

    /// The contents of every ``` fenced block, with the language tag removed.
    static func fencedBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        var remainder = Substring(text)

        while let open = remainder.range(of: "```") {
            let afterOpen = remainder[open.upperBound...]
            guard let close = afterOpen.range(of: "```") else { break }

            var body = afterOpen[..<close.lowerBound]
            // A fence may carry a language tag on the opening line: ```json
            if let newline = body.firstIndex(of: "\n") {
                let tag = body[..<newline].trimmingCharacters(in: .whitespaces)
                if !tag.isEmpty, !tag.contains("{"), !tag.contains("[") {
                    body = body[body.index(after: newline)...]
                }
            }

            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(trimmed)
            }
            remainder = afterOpen[close.upperBound...]
        }

        return blocks
    }

    /// Every balanced `{…}` or `[…]` span at the outermost level.
    ///
    /// Quotes and escapes are tracked, because a brace inside a string — and
    /// German note text contains them about as often as anything else does —
    /// must not close the span.
    static func balancedSpans(in text: String) -> [String] {
        var spans: [String] = []
        var depth = 0
        var start: String.Index?
        var opener: Character = "{"
        var inString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                if depth > 0 { inString = true }
            case "{", "[":
                if depth == 0 {
                    start = index
                    opener = character
                }
                depth += 1
            case "}", "]":
                guard depth > 0 else { continue }
                let matches = (opener == "{" && character == "}") || (opener == "[" && character == "]")
                depth -= 1
                if depth == 0, matches, let start {
                    spans.append(String(text[start...index]))
                }
                if depth == 0 { start = nil }
            default:
                continue
            }
        }

        return spans
    }
}
