import Foundation

/// Everything about answering a question against one recording, as pure values.
///
/// The prompt, the schema, the decoded answer and the parsing of the source
/// chips. `RecordingChat` does nothing but hold the conversation and hand these
/// to a backend.
nonisolated enum ChatAnswering {

    // MARK: - The prompt

    /// Board 04 states the contract in the rail itself: "Fragen zu dieser
    /// Stunde. Das Modell sieht Notizen und Transkript."
    ///
    /// The instructions below each stop something specific:
    ///
    /// - *only from what is here* — a 7B model asked about paging will answer
    ///   from its training data, fluently and about a different lecture. The
    ///   whole value of the chat is that it answers about **this** recording.
    /// - *the transcript is dirty* — everything the microphone hears is decoded
    ///   now, so a question can land on a passage that is noise. Without this
    ///   the model reads the noise as a statement and answers from it.
    /// - *say when it is not here* — without permission to say so, the model
    ///   invents rather than disappoint. "Dazu steht nichts im Transkript" is a
    ///   useful answer; a confident wrong one is not.
    /// - *cite* — board 04 draws the chips, and a citation is what makes the
    ///   answer checkable against a transcript the reader can click into.
    /// - *the exact spellings* — the references are parsed back into places in
    ///   the transcript and the notes. "ungefähr in der Mitte" is not one.
    /// - *short* — the rail is 330 points wide.
    static let systemPrompt = """
        You answer questions about one recorded class, for the student who recorded it.

        You are given that recording's notes and the part of its transcript that is \
        relevant to the question. Answer in German.

        - Answer only from the notes and the transcript given to you. Never add anything \
        you know from elsewhere, however sure you are of it.
        - The transcript comes from automatic speech recognition and is not clean: some \
        sentences make no sense, and some words were never said. Where the surrounding \
        lines make the meaning clear, use it. Where they do not, treat that passage as \
        something you do not have, and say so — do not repair it with a word you cannot \
        get from the transcript itself.
        - If the answer is not in the material, say so in one sentence. Do not guess and \
        do not apologise at length.
        - Keep it to three or four sentences.
        - List what you used in "references", using exactly these spellings: a transcript \
        timestamp as it appears in square brackets, for example "00:38:20", or a note \
        block as "Notiz 3". Nothing else belongs in that list.
        """

    static let schema = SchemaDescription(
        name: "chat_answer",
        schema: JSONSchema.object(
            "An answer about one recording, in German, with its sources.",
            [
                ("answer", JSONSchema.string("Three or four German sentences answering the question.")),
                (
                    "references",
                    JSONSchema.array(
                        of: JSONSchema.string("A transcript timestamp such as \"00:38:20\", or a note block such as \"Notiz 3\"."),
                        "What the answer was taken from. May be empty.",
                        maximum: 6
                    )
                ),
            ]
        )
    )

    /// Builds the prompt for one question.
    ///
    /// - Parameters:
    ///   - history: earlier turns, oldest first. Carried so a follow-up — "und
    ///     warum?" — has something to refer to.
    ///   - transcriptBudget: how many tokens the transcript excerpt may take.
    ///     Everything else in the prompt is small and bounded; the transcript is
    ///     the only part that can be ninety minutes long, so it is the only
    ///     part that is selected.
    static func prompt(
        question: String,
        notes: RecordingNotes,
        transcript: [TranscriptLine],
        history: [ChatTurn] = [],
        transcriptBudget: Int
    ) -> ChatConversation {
        var messages: [ChatMessage] = [.system(systemPrompt)]

        var material: [String] = ["Notes for this recording:"]
        material.append(numberedNotes(notes))

        let excerpt = TranscriptRetrieval.excerpt(
            of: transcript,
            for: question,
            tokenBudget: max(0, transcriptBudget)
        )
        if !excerpt.isEmpty {
            material.append("Transcript of this recording, the part that matches the question:")
            material.append(NoteReduction.transcript(of: excerpt))
        }
        messages.append(.system(material.joined(separator: "\n\n")))

        // Only the recent turns. A rail that has been going for twenty
        // questions would otherwise push the transcript out of the context,
        // which is the opposite of what the budget is for.
        for turn in history.suffix(historyTurns) {
            messages.append(ChatMessage(role: turn.author == .you ? .user : .assistant, content: turn.text))
        }

        messages.append(.user(question))
        return ChatConversation(messages)
    }

    /// How many earlier turns travel with a question.
    static let historyTurns = 6

    /// The notes as the model sees them, with the block numbers it is asked to
    /// cite written in front of each card.
    static func numberedNotes(_ notes: RecordingNotes) -> String {
        guard !notes.blocks.isEmpty else { return notes.markdown }

        return notes.blocks
            .filter { !$0.markdown.isEmpty }
            .map { "Notiz \($0.number) (\(NoteReduction.timestamp($0.start))):\n\($0.markdown)" }
            .joined(separator: "\n\n")
    }

    // MARK: - The answer

    nonisolated struct Answer: Hashable, Sendable, Codable {

        var answer: String
        var references: [String]

        init(answer: String, references: [String] = []) {
            self.answer = answer
            self.references = references
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            answer = try container.decode(String.self, forKey: .answer)
            references = try container.decodeIfPresent([String].self, forKey: .references) ?? []
        }
    }

    /// Turns a decoded answer into the turn the rail draws.
    ///
    /// - Parameter blocks: the note blocks that exist. A citation of a block
    ///   that does not is dropped rather than drawn — a chip reading "Notiz 9"
    ///   that leads nowhere is worse than one chip fewer.
    static func turn(from answer: Answer, blocks: [NoteBlock], duration: TimeInterval?) -> ChatTurn {
        let numbers = Set(blocks.map(\.number))
        var seen: Set<ChatReference> = []

        let references = answer.references.compactMap { raw -> ChatReference? in
            guard let reference = self.reference(from: raw) else { return nil }
            switch reference {
            case .note(let number):
                guard numbers.contains(number) else { return nil }
            case .transcript(let time):
                // A timestamp past the end of the recording is a hallucinated
                // one, and it is the commonest kind: a model that cannot find a
                // source makes a plausible-looking time up.
                if let duration, time > duration { return nil }
                if time < 0 { return nil }
            }
            guard seen.insert(reference).inserted else { return nil }
            return reference
        }

        return ChatTurn(
            author: .model,
            text: answer.answer.trimmingCharacters(in: .whitespacesAndNewlines),
            references: references
        )
    }

    /// Parses one chip.
    ///
    /// Both spellings the model is given, plus the ones it uses anyway: square
    /// brackets around a timestamp because that is how the transcript was
    /// shown to it, and "Note"/"Block" because half of an English-instructed
    /// model's vocabulary is English.
    static func reference(from raw: String) -> ChatReference? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "[]()\"'"))
        guard !text.isEmpty else { return nil }

        let folded = text.lowercased()
        for word in ["notiz", "note", "block"] where folded.hasPrefix(word) {
            let digits = text.drop(while: { !$0.isNumber }).prefix(while: \.isNumber)
            guard let number = Int(digits) else { return nil }
            return .note(number)
        }

        return seconds(from: text).map { .transcript($0) }
    }

    /// `MM:SS` or `H:MM:SS` back into seconds.
    static func seconds(from text: String) -> TimeInterval? {
        let parts = text.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }

        var total: TimeInterval = 0
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            total = total * 60 + TimeInterval(value)
        }
        return total
    }
}
