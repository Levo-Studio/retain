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

    /// **These are meeting notes, not an encyclopedia entry — and not a story.**
    ///
    /// Two faults are corrected here, both seen in what the model produced.
    ///
    /// The first was "explaining the matter itself the way a textbook would".
    /// Read literally, that is an instruction to leave the room: handed three
    /// minutes of a biology lesson about corals, the model wrote a tidy,
    /// accurate paragraph of general knowledge, with terms that appear nowhere
    /// in the transcript.
    ///
    /// The second is that the shape was shown as fillable German — a line
    /// reading `Ein Absatz.` under a heading reading `Überschrift`. The model
    /// copied it. A note went out with the literal words "Ein Absatz." as its
    /// paragraph, which is the template answering instead of the model. The
    /// shape is described now and never demonstrated in the language the answer
    /// is written in.
    ///
    /// And the balance has moved: fewer sentences, more points. A lesson is
    /// mostly a list of things that were said, and prose is the form that hides
    /// them.
    ///
    /// The paragraph about the transcript being dirty is there because the live
    /// gate came off the audio path: everything the microphone hears is
    /// decoded now, so a cough, a chair and a corridor all arrive as words.
    /// The model is told to read through that and told, in the same breath,
    /// that reading through it is not licence to invent — the one failure that
    /// cannot be spotted by the person reading the notes.
    static let blockSystemPrompt = """
        You take one stretch of a recorded class and write down what was said in it.

        These are notes of the lesson, not an article about the subject, and not a \
        retelling of it. Somebody who missed this stretch reads them to find out what \
        was covered and what was said about it. Write your answer in German.

        The transcript is German, comes from automatic speech recognition, and is \
        not clean. It carries filler words and false starts; read through those. \
        Beyond them, whole sentences in it may make no sense, and words may appear that nobody \
        said — every sound in the room reaches the recogniser and it writes a word \
        for some of them. Expect that, and think:

        - Where the sentences around it make it clear what was meant, write what was \
        meant. A mangled technical term standing next to its own definition is not a \
        mystery.
        - Where they do not, leave it out. A passage you cannot follow is not a \
        passage to guess at, and never the basis for a point in the notes.
        - **Invent nothing.** Do not repair a sentence with a word you cannot get \
        from the transcript itself, and do not write down anything you had to make up \
        to make a broken passage read well. One invented sentence makes the whole \
        page worthless, because the reader cannot tell which one it is.
        - A fragment that fits nowhere — a stray word, a sentence with no subject, a \
        line of noise — does not go in at all. Finding a home for every line is not \
        the job.

        Answer with Markdown in this order and nothing else:

        1. one heading line beginning with "## "
        2. one or two sentences of plain text
        3. between two and six list items, each beginning with "- "

        Rules:
        - The heading names what this stretch was about: a German noun phrase, no \
        verb, no full stop. Never "#", never "###".
        - The sentences say what the stretch was about at all — the one thing a reader \
        needs before the list makes sense. Two sentences at most. Everything else \
        belongs in the list.
        - **The list carries the content.** One item per thing that was said: a \
        definition, a rule, a date, a figure, a name, a condition, an exception, a task \
        that was set, a question from the room. Short — a phrase, not a sentence. \
        Never restate the sentences above.
        - **Every number that was said goes in.** Dates, weights, percentages, counts, \
        pages, deadlines, marks. A number is the one thing a reader cannot reconstruct \
        and the first thing they came for.
        - **Take nothing from outside the transcript.** If something was explained \
        incompletely, leave it incomplete. Adding what you know about the subject is \
        the one mistake that makes these notes worthless, because the reader cannot \
        tell it from what was said.
        - Do not narrate: no "der Lehrer sagt", no "in diesem Abschnitt", no "es wurde \
        besprochen", no "zunächst … dann …". Write the content, in the room's own terms.
        - Mark the one term the stretch turns on with **double asterisks**, once. Never \
        mark a second term.
        - Never write placeholder text. If a part has nothing to hold, leave that part \
        out entirely.
        - No tables, no code fences, no images, no links, no horizontal rules.

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
                        "The note as Markdown: a '## ' heading naming what this stretch was about, then one or two sentences, then two to six '- ' items carrying the content — every definition, rule, date, figure, name and task that was said, with every number kept. One **bold** term. No other Markdown, and never placeholder text."
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
    /// - *the student's remarks* — they reached the model nowhere at all once
    ///   nothing was summarised while the lecture ran: the map step carried
    ///   them and the map step stopped happening, so `⌘⇧M` wrote to a file and
    ///   to a dot on the chapter rail and to nothing else. They are handed over
    ///   here, last, with the rule that their meaning has to land in the notes
    ///   and their wording must not.
    /// - *the transcript is dirty* — it had none of this and needed it most,
    ///   because the finished notes are written here. Everything the microphone
    ///   hears is decoded now, so nonsense reaches the model, and a model that
    ///   meets nonsense with no instruction smooths it into something readable
    ///   and wrong.
    static let reduceSystemPrompt = """
        You write the finished notes of one recorded class: what was covered, and \
        what was said about it.

        These are notes of the lesson, not an article about the subject, and not a \
        retelling of it. Somebody who was not there reads them instead of the \
        recording. Write in German.

        You are given the transcript of record: the whole lesson, from the first \
        word to the last. Read all of it before you write anything — the point of \
        being given it whole is that you can see where a subject started and where it \
        was dropped, which is not visible three minutes at a time.

        The transcript comes from automatic speech recognition and is not clean. \
        It carries filler words and false starts; read through those. Beyond them, \
        whole sentences in it may make no sense, and words may appear that nobody \
        said — every sound in the room reaches the recogniser and it writes a word \
        for some of them. Expect that, and think:

        - Where the sentences around it make it clear what was meant, write what was \
        meant. A mangled technical term standing next to its own definition is not a \
        mystery.
        - Where they do not, leave it out. A passage you cannot follow is not a \
        passage to guess at, and never the basis for a point in the notes.
        - **Invent nothing.** Do not repair a sentence with a word you cannot get \
        from the transcript itself, and do not write down anything you had to make up \
        to make a broken passage read well. One invented sentence makes the whole \
        page worthless, because the reader cannot tell which one it is.
        - A fragment that fits nowhere — a stray word, a sentence with no subject, a \
        line of noise — does not go in at all. Finding a home for every line is not \
        the job.

        topic — a German noun phrase naming what the lesson was about, at most 60 \
        characters. No verb, no sentence, no full stop. Never a generic label such as \
        "Zusammenfassung", "Vorlesung" or "Notizen".

        sections — three to eight of them, in the order things were said. Each has a \
        starts_at and a markdown.

        starts_at — the timestamp in front of the transcript line that section begins \
        at, copied exactly as it appears there, for example 12:40. It is what a reader \
        clicks to hear that part again, so copy it rather than estimating it.

        markdown — one section, in this order and nothing else:

        1. one heading line beginning with "## "
        2. one or two sentences of plain text
        3. between two and six list items, each beginning with "- "

        Rules:
        - Each heading names what that part of the lesson was about: a German noun \
        phrase, no verb, no full stop. Never "#", never "###".
        - The sentences say what the part was about at all — what a reader needs \
        before the list makes sense. Two at most. Everything else belongs in the list.
        - **The list carries the content.** One item per thing that was said: a \
        definition, a rule, a date, a figure, a name, a condition, an exception, a task \
        that was set, a question from the room. Short — a phrase, not a sentence.
        - **Every number that was said goes in.** Dates, weights, percentages, counts, \
        pages, deadlines, marks. A number is the one thing a reader cannot reconstruct \
        and the first thing they came for.
        - **Take nothing from outside the transcript.** If something was explained \
        incompletely, leave it incomplete. Filling the gap with what you know about \
        the subject is the one mistake that makes these notes worthless, because the \
        reader cannot tell it from what was said.
        - Do not narrate: no "der Lehrer sagt", no "in dieser Stunde", no "es wurde \
        besprochen", no "zunächst … dann …". Write the content, in the room's own terms.
        - Mark the one term of each section with **double asterisks**, once.
        - Never write placeholder text. If a part has nothing to hold, leave that part \
        out entirely.
        - No tables, no code fences, no images, no links, no horizontal rules.

        The lesson may come with remarks the student typed while listening, each \
        with the time it was typed at. They are not transcript and they are not \
        optional:

        - **Every remark reaches the notes.** Its content goes into the section \
        covering its time, as one of that section's list items or worked into its \
        sentences. None of them is dropped, whatever else the lesson was about.
        - **Never quote one.** It was typed in a hurry in the student's own \
        shorthand, and the notes are not where that reappears word for word. Write \
        what it means, in the same voice as everything around it, so a reader cannot \
        tell it apart from the rest.
        - If it says something the transcript does not — a correction, a piece of \
        context, that something is coming up in an exam — take it as true and write \
        it down. The student was in the room.
        - If it only points at something — "wichtig", "nochmal anschauen" — then it \
        is telling you which part of the lesson matters most, and the section \
        covering that time carries that part in full.
        """

    /// - Parameters:
    ///   - notes: the cards written while the recording ran, in order.
    ///   - transcript: the batch transcript, which is the record. The live one
    ///     is never used here — it sits around 10 % word error against the
    ///     batch pass's 5.9 %, and the final notes are the thing that lasts.
    ///   - markers: what the student typed during the lecture. Last in the
    ///     prompt on purpose — it is the part that must survive everything
    ///     else, and the end of a long prompt is where a model is still
    ///     reading.
    static func reducePrompt(
        notes: [NoteBlock],
        transcript: [TranscriptLine],
        markers: [RecordingMarker] = []
    ) -> ChatConversation {
        var parts: [String] = []

        // Only when there are any. Nothing is summarised while a lecture runs
        // any more — the model is handed the whole transcript once, at the end
        // — and a heading saying "Draft notes:" with nothing under it is a
        // prompt telling the model something it then has to ignore.
        if !notes.isEmpty {
            parts.append("Draft notes, one per block:")
            parts.append(notes.map(draft(of:)).joined(separator: "\n\n"))
        }

        parts.append("Transcript of record:")
        parts.append(self.transcript(of: transcript))

        // A bare `⌘⇧M` has no text in it. It marks its chapter with a dot and
        // it counts in the meta strip, but there is nothing here to tell the
        // model, and an empty bullet would read as a remark the student made
        // and then said nothing in.
        let annotations = markers.filter(\.hasText).sorted { $0.time < $1.time }
        if !annotations.isEmpty {
            parts.append("Remarks the student typed while listening:")
            parts.append(
                annotations
                    .map { "- \(timestamp($0.time)): \($0.text)" }
                    .joined(separator: "\n")
            )
        }

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
                    "sections",
                    JSONSchema.array(
                        of: JSONSchema.object(
                            "One section of the notes.",
                            [
                                (
                                    "starts_at",
                                    JSONSchema.string(
                                        "Where this section begins, copied from the timestamp in front of the transcript line it starts at. Exactly as it appears there, for example 12:40."
                                    )
                                ),
                                (
                                    "markdown",
                                    JSONSchema.string(
                                        "The section as Markdown: a '## ' heading naming that part of the lesson, then one or two sentences, then two to six '- ' items carrying the content — every definition, rule, date, figure, name and task that was said, with every number kept. One **bold** term. No other Markdown, and never placeholder text."
                                    )
                                ),
                            ]
                        ),
                        "Three to eight sections, in the order things were said.",
                        maximum: 8
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

        /// One section of the notes, as the model wrote it.
        ///
        /// **The model says where a section starts; Retain does not work it
        /// out.** The structure used to be recovered from the Markdown by
        /// string matching — headings found by their `##`, the subject found by
        /// its asterisks, the minute found by searching the transcript for that
        /// word, and a share of the recording invented when the search failed.
        /// Every one of those is a guess about an answer whose author was right
        /// there and had the timestamps in front of it.
        nonisolated struct Section: Hashable, Sendable, Codable {

            /// Where in the recording this section begins, as it appears in the
            /// transcript the model was given: `mm:ss`, or `h:mm:ss`.
            var startsAt: String

            /// The section as Markdown, heading and all.
            var markdown: String

            enum CodingKeys: String, CodingKey {
                case startsAt = "starts_at"
                case markdown
            }
        }

        var topic: String
        var sections: [Section]

        /// The notes as one document, for export, for search and for the chat.
        ///
        /// Assembled from the sections rather than asked for twice: two fields
        /// holding the same notes are two things that can disagree.
        var markdown: String {
            sections.map(\.markdown).joined(separator: "\n\n")
        }

        init(topic: String, sections: [Section]) {
            self.topic = topic
            self.sections = sections
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // The topic is allowed to be missing; the notes are not. A reduce
            // that produced no notes is a failed reduce, and a recording with
            // no topic is a recording the library draws by its date.
            topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? ""
            sections = try container.decode([Section].self, forKey: .sections)
        }

        enum CodingKeys: String, CodingKey {
            case topic, sections
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

    /// The finished notes, as the model wrote them.
    ///
    /// **The blocks come from the answer and nothing is inferred.** They used
    /// to be the draft cards passed through, which returned an empty list once
    /// there were no drafts — the Markdown came back, the blocks did not,
    /// nothing was stored, and the window said "No notes yet" over a lecture
    /// the model had just read in full. The fix after that was worse: the
    /// sections were recovered from the Markdown by string matching and their
    /// times by searching the transcript for each section's bold term, with an
    /// invented share of the recording when the search failed. Every one of
    /// those is a guess about an answer whose author had the timestamps in
    /// front of it and could simply be asked.
    static func notes(
        from answer: NotesAnswer,
        markers: [RecordingMarker] = []
    ) -> RecordingNotes {
        let blocks = answer.sections.enumerated().map { index, section in
            NoteBlock(
                number: index + 1,
                markdown: NoteMarkdown.sanitised(section.markdown),
                start: seconds(from: section.startsAt),
                // Up to where the next one begins. The last runs to the end of
                // what there is, which the caller knows and this does not.
                end: index + 1 < answer.sections.count
                    ? seconds(from: answer.sections[index + 1].startsAt)
                    : .greatestFiniteMagnitude,
                state: .written
            )
        }

        return RecordingNotes(
            topic: topic(from: answer.topic),
            markdown: blocks.map(\.markdown).joined(separator: "\n\n"),
            blocks: blocks,
            markers: markers.sorted { $0.time < $1.time }
        )
    }

    /// `mm:ss` or `h:mm:ss` back into seconds — the inverse of `timestamp(_:)`,
    /// which is the format the transcript is handed to the model in and the
    /// format the model is asked to copy back.
    ///
    /// Anything that is not one of those is zero rather than a refusal: a
    /// section whose time could not be read is still a section worth reading,
    /// and the chapter row for it lands at the start instead of nowhere.
    static func seconds(from timestamp: String) -> TimeInterval {
        let parts = timestamp
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ":")
            .compactMap { Int($0) }

        switch parts.count {
        case 2: return TimeInterval(parts[0] * 60 + parts[1])
        case 3: return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        default: return 0
        }
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

nonisolated extension NoteReduction.NotesAnswer: UsableAnswer {

    /// Notes with no sections in them are not notes.
    ///
    /// It is the one shape this answer can take that parses and says nothing,
    /// and it has to reach the ladder as a failure rather than being stored as
    /// an empty set — that was the bug: a lecture the model had read in full,
    /// and a window saying "No notes yet" over it.
    var isUsable: Bool {
        sections.contains { NoteReduction.isUsableNote($0.markdown) }
    }
}

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

    /// Lines a model writes when it is answering with the shape instead of the
    /// content.
    ///
    /// These were in the prompt as an example of the form, in German, and the
    /// model copied them: a note went out whose entire paragraph was the words
    /// "Ein Absatz.". The prompt no longer demonstrates the shape in the
    /// language of the answer, and a reply that still contains one of these is
    /// a rung that failed — the ladder has a better one below it.
    static let templateEchoes = ["ein absatz", "überschrift", "höchstens drei stichpunkte"]

    static func isUsableNote(_ markdown: String) -> Bool {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // A whole line that is nothing but one of the template's own words.
        // Matched per line rather than anywhere in the text, so a note that
        // genuinely discusses a heading is not thrown away.
        let echoed = trimmed.split(separator: "\n").contains { line in
            let bare = line
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t#-*.").union(.whitespaces))
                .lowercased()
            return templateEchoes.contains(bare)
        }
        guard !echoed else { return false }

        let body = trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return body.count >= shortestUsableNote
    }
}
