import Foundation

/// The map and the reduce, as pure values.
///
/// Everything here is a function from values to values: a block becomes a
/// prompt, a model's answer becomes a note card, a pile of note cards becomes
/// the finished notes. Nothing in this file opens a socket, and nothing in it
/// knows which model answered — which is what lets the prompts, the schemas and
/// the repair work all be tested in milliseconds.
///
/// **The prompts are constants in this file on purpose.** A prompt is the part
/// of Retain that decides what the notes read like, it changes more often than
/// the code around it, and every change to one is a change to the product. Kept
/// here, a prompt edit shows up in a diff next to the reason it was made.
///
/// **The model writes Markdown inside a JSON envelope.** The envelope is what
/// keeps the answer checkable — a 3–8B model asked to free-write produces five
/// cards where one was asked for — and the Markdown inside it is what the model
/// is actually good at. `NoteMarkdown` then holds the Markdown to the subset the
/// design draws.
nonisolated enum NoteReduction {

    // MARK: - Prompts, map step

    /// **These are meeting notes, not an encyclopedia entry.**
    ///
    /// The prompt used to say "explaining the matter itself the way a textbook
    /// would" and "never write about the class". Read literally, that is an
    /// instruction to leave the room: the model was handed three minutes of a
    /// biology lesson about corals and wrote a tidy paragraph of general
    /// knowledge about coral symbiosis — accurate, plausible, and not what the
    /// teacher had said. Which is exactly how it was reported: the model just
    /// puts something out.
    ///
    /// What is wanted is the other thing. Somebody who missed the lesson should
    /// be able to read the note and know **what was covered and what was said
    /// about it** — the definition as it was given, the example that was used,
    /// the number that was named, the question somebody asked. Nothing from
    /// outside the transcript, however true.
    ///
    /// The shape is unchanged; only the job is.
    static let blockSystemPrompt = """
        You take one stretch of a recorded class and write down what was said in it.

        These are notes of the lesson, not an article about the subject. Somebody who \
        missed this stretch reads them to find out what was covered and what was said \
        about it. Write your answer in German.

        The transcript is German and comes from automatic speech recognition, so it \
        contains recognition errors, filler words and false starts. Read through them.

        The note is Markdown, in exactly this shape and using nothing else:

        ## Überschrift
        Ein Absatz.
        - höchstens drei Stichpunkte

        Rules:
        - The heading is one line starting with "## ". Never "#", never "###". It names \
        what this stretch was about: a noun phrase, no verb, no full stop.
        - One paragraph of two to four sentences saying what was actually said: the \
        definition as it was given, the example that was used, the point that was made. \
        Follow the order it was said in.
        - **Take nothing from outside the transcript.** If the teacher explained \
        something incompletely, write it as incompletely as they did. Adding what you \
        know about the subject is the one mistake that makes these notes worthless, \
        because the reader cannot tell it from what was said.
        - Do not narrate the lesson either: no "der Lehrer sagt", no "in diesem \
        Abschnitt", no "es wurde besprochen". Write the content, in the room's own \
        terms.
        - Mark the one technical term the stretch turns on with **double asterisks**, \
        once, inside the paragraph. Never mark a second term.
        - The list is optional and holds at most three items, each something worth \
        keeping that was actually named: a number, a definition, a condition, an \
        exception, a question from the room. Leave it out when nothing of that kind was \
        said. Never restate the paragraph.
        - No tables, no code fences, no images, no links, no horizontal rules.

        If a word was obviously misrecognised and the context makes it clear what was \
        meant, correct it. If you cannot tell, leave it out rather than guess.
        """

    /// The user turn for one block.
    static func blockPrompt(for block: TranscriptBlock) -> ChatConversation {
        var parts: [String] = []
        parts.append("Transcript, minute \(timestamp(block.start)) to \(timestamp(block.end)):")
        parts.append(transcript(of: block.lines))

        // The design promises this: the annotation bar is labelled "Anmerkung —
        // geht an die KI", so what the user typed has to reach the model, and
        // reach it as an instruction about emphasis rather than as more
        // transcript.
        let annotations = block.markers.filter(\.hasText)
        if !annotations.isEmpty {
            parts.append(
                """
                The student marked the following while listening. Give what it points at \
                room in the note, and follow it if it says something is important:
                """
            )
            parts.append(annotations.map { "- \(timestamp($0.time)): \($0.text)" }.joined(separator: "\n"))
        }

        return ChatConversation([
            .system(blockSystemPrompt),
            .user(parts.joined(separator: "\n\n")),
        ])
    }

    static let blockSchema = SchemaDescription(
        name: "note_block",
        schema: JSONSchema.object(
            "Notes of one stretch of a recorded class, in German: what was covered and what was said about it. Nothing from outside the transcript.",
            [
                (
                    "markdown",
                    JSONSchema.string(
                        "The note as Markdown: a '## ' heading naming what this stretch was about, one paragraph saying what was said about it with one **bold** term, and an optional list of at most three '- ' items that were actually named. No other Markdown."
                    )
                )
            ]
        )
    )

    // MARK: - Prompts, reduce step

    /// The reduce is a different job from the map and says so.
    ///
    /// - *the cards are drafts* — without it the model copies them, and the
    ///   final notes read as a list of three-minute fragments, which is what
    ///   they already were.
    /// - *merge and split by subject matter* — nobody changes topic on a
    ///   three-minute clock, so the block boundaries are the wrong seams and
    ///   the model has to be told it may move them.
    /// - *the same Markdown subset* — the finished notes are drawn by the same
    ///   renderer as the cards.
    /// - *the topic constraints* — see `topic(from:)`. They are in the prompt
    ///   and enforced afterwards, because a model that is told twice still
    ///   sometimes answers "Zusammenfassung der Vorlesung".
    static let reduceSystemPrompt = """
        You write the finished notes of one recorded class: what was covered, and \
        what was said about it.

        These are notes of the lesson, not an article about the subject. Somebody who \
        was not there reads them instead of the recording. Write in German.

        You are given the transcript of record and the draft notes that were written \
        while the recording ran. The drafts are drafts: each was written from three \
        minutes in isolation, so they overlap, they repeat themselves, and they cut \
        topics in half. **The transcript is what is true.** Where a draft says \
        something the transcript does not, drop it.

        topic — a German noun phrase naming what the lesson was about, at most 60 \
        characters. No verb, no sentence, no full stop. Never a generic label such as \
        "Zusammenfassung", "Vorlesung" or "Notizen".

        markdown — the notes, as three to eight sections in the order things were said. \
        Merge consecutive drafts that turned out to be about the same thing; split one \
        that covered two. Each section is:

        ## Überschrift
        Ein Absatz von drei bis sechs Sätzen.
        - höchstens drei Stichpunkte

        Rules:
        - Headings start with "## ". Never "#", never "###". Each names what that part \
        of the lesson was about: a noun phrase, no verb, no full stop.
        - Each paragraph says what was said: the definition as it was given, the \
        example that was used, the argument that was made, in the order it came.
        - **Take nothing from outside the transcript.** If something was explained \
        incompletely, leave it incomplete. Filling the gap with what you know about \
        the subject is the one mistake that makes these notes worthless, because the \
        reader cannot tell it from what was said.
        - Do not narrate the lesson either: no "der Lehrer sagt", no "in dieser \
        Stunde", no "es wurde besprochen". Write the content, in the room's own terms.
        - Mark the one technical term of each section with **double asterisks**, once.
        - The list is optional and holds at most three items, each something worth \
        keeping that was actually named.
        - No tables, no code fences, no images, no links, no horizontal rules.
        """

    /// - Parameters:
    ///   - notes: the cards written while the recording ran, in order.
    ///   - transcript: the batch transcript, which is the record. The live one
    ///     is never used here — it sits around 10 % word error against the
    ///     batch pass's 5.9 %, and the final notes are the thing that lasts.
    static func reducePrompt(notes: [NoteBlock], transcript: [TranscriptLine]) -> ChatConversation {
        var parts: [String] = []

        parts.append("Draft notes, one per block:")
        parts.append(notes.map(draft(of:)).joined(separator: "\n\n"))

        parts.append("Transcript of record:")
        parts.append(self.transcript(of: transcript))

        return ChatConversation([
            .system(reduceSystemPrompt),
            .user(parts.joined(separator: "\n\n")),
        ])
    }

    static let notesSchema = SchemaDescription(
        name: "recording_notes",
        schema: JSONSchema.object(
            "The finished notes of one recorded class, in German: what was covered and what was said about it, in the order it was said. Nothing from outside the transcript.",
            [
                (
                    "topic",
                    JSONSchema.string(
                        "A German noun phrase naming what the lesson was about. At most 60 characters, no verb, no full stop."
                    )
                ),
                (
                    "markdown",
                    JSONSchema.string(
                        "The notes as Markdown: three to eight sections in the order things were said, each a '## ' heading naming that part of the lesson, one paragraph saying what was said about it with one **bold** term, and an optional list. No other Markdown."
                    )
                ),
            ]
        )
    )

    // MARK: - Answers

    /// What the model sends back for one block.
    nonisolated struct BlockAnswer: Hashable, Sendable, Codable {

        var markdown: String

        init(markdown: String) {
            self.markdown = markdown
        }

        /// A single-field answer is the one case where a model is likely to
        /// skip the envelope and simply write the Markdown. Accepting a bare
        /// string as well as `{"markdown": …}` costs three lines and saves the
        /// card.
        init(from decoder: any Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self),
               let text = try? container.decode(String.self, forKey: .markdown) {
                markdown = text
                return
            }
            markdown = try decoder.singleValueContainer().decode(String.self)
        }
    }

    /// What the model sends back for the whole recording.
    nonisolated struct NotesAnswer: Hashable, Sendable, Codable {

        var topic: String
        var markdown: String

        init(topic: String, markdown: String) {
            self.topic = topic
            self.markdown = markdown
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // The topic is allowed to be missing; the notes are not. A reduce
            // that produced no notes is a failed reduce, and a recording with
            // no topic is a recording the library draws by its date.
            topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? ""
            markdown = try container.decode(String.self, forKey: .markdown)
        }
    }

    // MARK: - Map: an answer becomes a card

    static func noteBlock(from answer: BlockAnswer, for block: TranscriptBlock) -> NoteBlock {
        NoteBlock(
            number: block.number,
            markdown: NoteMarkdown.sanitised(answer.markdown),
            start: block.start,
            end: block.end,
            state: .written
        )
    }

    /// The placeholder for a block the model could not be asked about.
    ///
    /// The "No connection" dialog promises that "summaries are caught up once
    /// the connection is back", and a card that is visibly waiting is how that
    /// promise is kept. Its Markdown is empty: there is nothing to say yet, and
    /// an apology in the notes would be indistinguishable from a note.
    static func deferredBlock(for block: TranscriptBlock) -> NoteBlock {
        NoteBlock(number: block.number, markdown: "", start: block.start, end: block.end, state: .deferred)
    }

    // MARK: - Reduce: cards become notes

    static func notes(
        from answer: NotesAnswer,
        blocks: [NoteBlock],
        markers: [RecordingMarker] = []
    ) -> RecordingNotes {
        RecordingNotes(
            topic: topic(from: answer.topic),
            markdown: NoteMarkdown.sanitised(answer.markdown),
            blocks: blocks,
            markers: markers.sorted { $0.time < $1.time }
        )
    }

    /// The notes when the reduce could not be run at all — the model was
    /// unreachable, or every attempt came back unusable. The cards, in order,
    /// as they already are. Worse notes than a reduce produces, and far better
    /// than none.
    ///
    /// No topic: the topic is the one thing only the reduce can see, and
    /// guessing it from the first card would put one card's subject in the
    /// library column for the whole recording.
    static func notes(fallbackFrom blocks: [NoteBlock], markers: [RecordingMarker] = []) -> RecordingNotes {
        RecordingNotes(
            topic: nil,
            markdown: blocks
                .map(\.markdown)
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n"),
            blocks: blocks,
            markers: markers.sorted { $0.time < $1.time }
        )
    }

    // MARK: - The topic

    /// At most this many characters in a topic.
    ///
    /// The library table gives the topic one flexible column beside three fixed
    /// ones in a 1120-point window. The three topics the design draws are 29 to
    /// 31 characters; 60 is twice that and still fits without the cell
    /// truncating at a usable width.
    static let topicCharacterLimit = 60

    /// Openings that are a label rather than a topic.
    ///
    /// Enforced after decoding as well as asked for in the prompt, because a
    /// 3–8B model offers these however firmly it is told not to — and the
    /// result of letting one through is a library where three recordings in a
    /// row are called "Zusammenfassung der Vorlesung" and the column carries no
    /// information at all.
    static let genericTopicOpenings = [
        "zusammenfassung",
        "notizen",
        "protokoll",
        "mitschrift",
        "thema",
        "unterricht",
        "stunde",
        "vorlesung",
        "aufnahme",
        "summary",
        "notes",
        "recording",
    ]

    /// A topic, or `nil` when the model did not produce one worth keeping.
    ///
    /// Returning `nil` rather than a trimmed-down best effort is the point.
    /// The topic is nullable everywhere downstream and the interface draws the
    /// recording's date and time when it is missing, which is honest. A
    /// sentence squeezed into a table cell is not.
    static func topic(from raw: String?) -> String? {
        guard let raw else { return nil }

        // Only the first line. A model that ignores "no sentence" often answers
        // with a title and then a paragraph explaining it.
        let firstLine = raw.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? raw
        var candidate = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // A heading marker or a quoted answer is still an answer.
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "#*_ "))
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'«»„“”"))
        candidate = candidate.trimmingCharacters(in: .whitespaces)

        guard !candidate.isEmpty else { return nil }
        guard candidate.count <= topicCharacterLimit else { return nil }

        // A full stop is the clearest sign the model wrote a sentence. A
        // question or exclamation mark says the same thing.
        guard let last = candidate.last, !".!?".contains(last) else { return nil }

        let folded = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for opening in genericTopicOpenings where folded.hasPrefix(opening) {
            return nil
        }

        return candidate
    }

    // MARK: - Formatting

    /// `MM:SS`, or `H:MM:SS` once a recording runs past the hour.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    /// The transcript as the model sees it.
    ///
    /// Speakers are labelled where diarization knew them. It is worth the
    /// tokens: a question from the room and the answer to it read as one
    /// confused statement otherwise, and the model writes the question into the
    /// notes as if the person teaching had said it.
    static func transcript(of lines: [TranscriptLine]) -> String {
        lines.map { line in
            switch line.speaker {
            case .lecturer, .unknown:
                "[\(timestamp(line.start))] \(line.text)"
            case .audience:
                "[\(timestamp(line.start))] (Frage aus dem Publikum) \(line.text)"
            }
        }
        .joined(separator: "\n")
    }

    /// One draft card as it appears in the reduce prompt.
    ///
    /// Stripped of its Markdown: the reduce model is about to write its own
    /// emphasis, and carrying the drafts' asterisks in tells it nothing while
    /// costing tokens on every card.
    static func draft(of note: NoteBlock) -> String {
        """
        Block \(note.number), \(timestamp(note.start))–\(timestamp(note.end))
        \(NoteMarkdown.plainText(note.markdown))
        """
    }
}

// MARK: - When a note is a note

nonisolated extension NoteReduction.BlockAnswer: UsableAnswer {

    /// A heading with nothing under it is not a note.
    ///
    /// This is what `gpt-oss-20b` returns when it is asked for one under a
    /// strict `json_schema`: `## Lern…`, valid JSON, right field, stop reason
    /// saying it finished. The card was stored and drawn as three dots, and the
    /// ladder never descended to the rung where the same model on the same
    /// transcript writes a full note.
    ///
    /// The bar is deliberately low. A three-minute block honestly summarised in
    /// one short sentence is a real note and must pass; what must not pass is a
    /// heading alone, or a body of a handful of characters.
    var isUsable: Bool { NoteReduction.isUsableNote(markdown) }
}

nonisolated extension NoteReduction {

    /// The shortest body that can still be a note, in characters.
    ///
    /// Twenty is about four German words. Anything under it is the model
    /// clearing its throat.
    static let shortestUsableNote = 20

    static func isUsableNote(_ markdown: String) -> Bool {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let body = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return body.count >= shortestUsableNote
    }
}
