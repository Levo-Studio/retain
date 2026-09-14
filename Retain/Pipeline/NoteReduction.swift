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

    /// Written in English and asking for German output.
    ///
    /// The two are not in tension: instruction-tuned models follow English
    /// instructions more reliably than German ones — that is what the bulk of
    /// their instruction data is in — while the class, and therefore the notes,
    /// are German. Mixing the two in one prompt is the arrangement that loses
    /// the least.
    ///
    /// Every line below is there to stop something a 3–8B model does otherwise:
    ///
    /// - *automatic and German* — without it, the model treats recognition
    ///   errors as terminology and repeats them into the heading.
    /// - *`##` and nothing else* — a model handed "write Markdown" opens with
    ///   an `#` title, because the card looks to it like a document. An H1 in a
    ///   column drawn for a 22px heading is a card twice the height of the ones
    ///   around it.
    /// - *no tables, code, images or links* — all four are drawn nowhere, all
    ///   four are things a model reaches for unasked, and a link is a promise
    ///   Retain cannot keep: there is no browser in the notes pane.
    /// - *noun phrase, no verb, no full stop* — otherwise the heading is
    ///   "Die Lehrerin erklärt die Seitentabelle", which is about the class
    ///   rather than the subject and reads wrong at 22px bold.
    /// - *never write about the class* — a model given a transcript writes a
    ///   meeting summary: "Zunächst wurde besprochen …". Nobody revises from
    ///   that.
    /// - *the list may be left out* — without that half, every card gets
    ///   exactly three bullets restating the paragraph, because an empty list
    ///   feels to the model like a failure.
    /// - *one bold term* — the design highlights exactly one term per card. Two
    ///   highlights in one paragraph is a paragraph with no emphasis in it.
    /// - *invent nothing* — the single most expensive failure here. A fluent
    ///   invented definition in a student's revision notes is worse than a gap,
    ///   because nothing about it looks wrong.
    static let blockSystemPrompt = """
        You write one revision note from one stretch of a recorded class.

        The transcript is German and was produced by automatic speech recognition, \
        so it contains recognition errors, filler words and false starts. Write your \
        answer in German.

        The note is Markdown, in exactly this shape and using nothing else:

        ## Überschrift
        Ein Absatz.
        - höchstens drei Stichpunkte

        Rules:
        - The heading is one line starting with "## ". Never "#", never "###". \
        It is a noun phrase: no verb, no full stop.
        - One paragraph of two to four sentences, explaining the matter itself the \
        way a textbook would. Never write about the class, the teacher, the room or \
        "dieser Abschnitt".
        - Mark the one technical term the stretch is about with **double asterisks**, \
        once, inside the paragraph. Never mark a second term.
        - The list is optional and holds at most three items, each a fact worth \
        memorising: a number, a definition, a condition, an exception. Leave it out \
        when the stretch holds nothing of that kind. Never restate the paragraph.
        - No tables, no code fences, no images, no links, no horizontal rules.

        Invent nothing. If a word was obviously misrecognised and you can tell what was \
        meant, correct it; if you cannot, leave it out.
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
            "One revision note about one stretch of a recording, in German.",
            [
                (
                    "markdown",
                    JSONSchema.string(
                        "The note as Markdown: a '## ' heading, one paragraph with one **bold** term, and an optional list of at most three '- ' items. No other Markdown."
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
        You write the finished notes for one recorded class.

        You are given the transcript of record and the draft notes that were written \
        while the recording ran. The drafts are drafts: each was written from three \
        minutes in isolation, so they overlap, they repeat themselves, and they cut \
        topics in half. Write in German.

        topic — a German noun phrase naming the subject matter of the whole recording, \
        at most 60 characters. No verb, no sentence, no full stop. Never a generic label \
        such as "Zusammenfassung", "Vorlesung" or "Notizen".

        markdown — the notes, as three to eight sections in the order things were said. \
        Merge consecutive drafts that turned out to be about the same thing; split one \
        that covered two. Each section is:

        ## Überschrift
        Ein Absatz von drei bis sechs Sätzen.
        - höchstens drei Stichpunkte

        Rules:
        - Headings start with "## ". Never "#", never "###". Each is a noun phrase: \
        no verb, no full stop.
        - Mark the one technical term of each section with **double asterisks**, once.
        - The list is optional and holds at most three items.
        - No tables, no code fences, no images, no links, no horizontal rules.
        - Write the matter itself, never the class, the teacher or the room.

        Invent nothing that is not in the transcript.
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
            "The finished notes for one recording, in German.",
            [
                (
                    "topic",
                    JSONSchema.string(
                        "A German noun phrase naming the subject matter. At most 60 characters, no verb, no full stop."
                    )
                ),
                (
                    "markdown",
                    JSONSchema.string(
                        "The notes as Markdown: three to eight sections, each a '## ' heading, one paragraph with one **bold** term, and an optional list. No other Markdown."
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
