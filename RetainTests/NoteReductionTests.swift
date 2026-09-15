import Foundation
import Testing

@testable import Retain

@Suite("Topic")
struct TopicTests {

    @Test("A noun phrase is kept as written")
    func nounPhraseSurvives() {
        #expect(NoteReduction.topic(from: "Virtueller Speicher und Paging") == "Virtueller Speicher und Paging")
        #expect(NoteReduction.topic(from: "Scheduling: CFS und Prioritäten") == "Scheduling: CFS und Prioritäten")
    }

    @Test("Nothing in, nothing out")
    func emptyGivesNothing() {
        #expect(NoteReduction.topic(from: nil) == nil)
        #expect(NoteReduction.topic(from: "") == nil)
        #expect(NoteReduction.topic(from: "   \n  ") == nil)
    }

    /// A sentence in a table column that is one flexible column wide.
    @Test("A sentence is refused rather than trimmed")
    func sentencesAreRefused() {
        #expect(NoteReduction.topic(from: "In dieser Stunde ging es um virtuellen Speicher.") == nil)
        #expect(NoteReduction.topic(from: "Worum ging es?") == nil)
        #expect(NoteReduction.topic(from: "Paging!") == nil)
    }

    @Test("A generic label is refused")
    func genericLabelsAreRefused() {
        #expect(NoteReduction.topic(from: "Zusammenfassung der Vorlesung") == nil)
        #expect(NoteReduction.topic(from: "zusammenfassung") == nil)
        #expect(NoteReduction.topic(from: "Notizen zur Stunde") == nil)
        #expect(NoteReduction.topic(from: "Thema der Stunde") == nil)
        #expect(NoteReduction.topic(from: "Summary") == nil)
    }

    /// "Zusammenfassung" is refused; a topic that merely mentions the word
    /// later is not — refusing that would throw away real topics.
    @Test("A generic word inside the phrase is not a generic label")
    func onlyTheOpeningIsChecked() {
        #expect(NoteReduction.topic(from: "Datenkompression und Zusammenfassung") != nil)
    }

    @Test("Too long for the column is refused")
    func lengthIsCapped() {
        let fits = String(repeating: "a", count: NoteReduction.topicCharacterLimit)
        let doesNot = String(repeating: "a", count: NoteReduction.topicCharacterLimit + 1)

        #expect(NoteReduction.topic(from: fits) == fits)
        #expect(NoteReduction.topic(from: doesNot) == nil)
    }

    @Test("Only the first line is considered")
    func firstLineWins() {
        #expect(NoteReduction.topic(from: "Paging\n\nDamit ist gemeint, dass …") == "Paging")
    }

    @Test("Quotes and heading markers around the answer are removed")
    func decorationIsStripped() {
        #expect(NoteReduction.topic(from: "\"Virtueller Speicher\"") == "Virtueller Speicher")
        #expect(NoteReduction.topic(from: "„Virtueller Speicher“") == "Virtueller Speicher")
        #expect(NoteReduction.topic(from: "## Virtueller Speicher") == "Virtueller Speicher")
        #expect(NoteReduction.topic(from: "**Virtueller Speicher**") == "Virtueller Speicher")
    }
}

// MARK: -

@Suite("Note Markdown")
struct NoteMarkdownTests {

    private let card = """
        ## Der TLB als Cache der Übersetzung
        Ohne Puffer kostet jeder Zugriff zwei Speicherzugriffe. Der **TLB** hält die letzten Übersetzungen.
        - Verdrängung nach pseudo-LRU
        """

    @Test("A card already in the subset comes through untouched")
    func cleanMarkdownIsUnchanged() {
        #expect(NoteMarkdown.sanitised(card) == card)
    }

    /// A model handed "write Markdown" opens with an H1, because the card looks
    /// to it like a document. At 22px bold that is a card twice the height of
    /// the ones around it.
    @Test("Every heading level becomes the one level the design draws")
    func headingsAreLevelled() {
        #expect(NoteMarkdown.sanitised("# Titel").hasPrefix("## "))
        #expect(NoteMarkdown.sanitised("#### Titel") == "## Titel")
        #expect(NoteMarkdown.sanitised("##   Titel") == "## Titel")
    }

    @Test("A fence around the answer is taken off, the answer is kept")
    func fencesAreRemoved() {
        let fenced = """
            ```markdown
            \(card)
            ```
            """
        #expect(NoteMarkdown.sanitised(fenced) == card)
    }

    @Test("A table is dropped rather than drawn at a width that does not exist")
    func tablesAreDropped() {
        let withTable = """
            ## Seitenersetzung
            Die Auswahl entscheidet über die Trefferrate.

            | Verfahren | Kosten |
            | --- | --- |
            | FIFO | billig |
            """

        let cleaned = NoteMarkdown.sanitised(withTable)
        #expect(!cleaned.contains("|"))
        #expect(cleaned.contains("Die Auswahl entscheidet über die Trefferrate."))
    }

    @Test("A link keeps its words and loses its destination")
    func linksBecomeTheirText() {
        let linked = "Siehe [Second Chance](https://de.wikipedia.org/wiki/Second_Chance) dazu."
        #expect(NoteMarkdown.sanitised(linked) == "Siehe Second Chance dazu.")
    }

    @Test("An image is dropped entirely")
    func imagesAreDropped() {
        #expect(NoteMarkdown.sanitised("Ein Diagramm: ![Clock](clock.png)") == "Ein Diagramm:")
    }

    @Test("Every list spelling becomes the one the renderer draws")
    func bulletsAreNormalised() {
        #expect(NoteMarkdown.sanitised("* eins\n+ zwei\n- drei") == "- eins\n- zwei\n- drei")
    }

    @Test("A rule between sections is not a divider the design draws")
    func thematicBreaksAreDropped() {
        #expect(NoteMarkdown.sanitised("## Eins\n\n---\n\n## Zwei") == "## Eins\n\n## Zwei")
    }

    @Test("Runs of blank lines collapse to one")
    func blankLinesCollapse() {
        #expect(NoteMarkdown.sanitised("## Eins\n\n\n\nAbsatz.") == "## Eins\n\nAbsatz.")
    }

    @Test("The heading is the first one and it loses its marker")
    func headingIsRead() {
        #expect(NoteMarkdown.heading(of: card) == "Der TLB als Cache der Übersetzung")
        #expect(NoteMarkdown.heading(of: "Absatz ohne Überschrift.") == nil)
        #expect(NoteMarkdown.heading(of: "") == nil)
        #expect(NoteMarkdown.heading(of: "##") == nil)
    }

    @Test("A document's headings come out in order")
    func headingsAreListed() {
        let notes = "## Eins\nAbsatz.\n\n## Zwei\nAbsatz.\n\n## Drei"
        #expect(NoteMarkdown.headings(in: notes) == ["Eins", "Zwei", "Drei"])
    }

    @Test("Plain text drops the formatting and keeps the words")
    func plainTextKeepsTheWords() {
        let plain = NoteMarkdown.plainText(card)

        #expect(!plain.contains("#"))
        #expect(!plain.contains("**"))
        #expect(plain.contains("Der TLB als Cache der Übersetzung"))
        #expect(plain.contains("TLB hält die letzten Übersetzungen"))
        #expect(plain.contains("Verdrängung nach pseudo-LRU"))
    }
}

// MARK: -

@Suite("Chapters")
struct NoteChaptersTests {

    private func block(_ number: Int, _ heading: String?, start: TimeInterval) -> NoteBlock {
        NoteBlock(
            number: number,
            markdown: heading.map { "## \($0)\nAbsatz." } ?? "Absatz ohne Überschrift.",
            start: start,
            end: start + 180
        )
    }

    @Test("Every card with a heading is a row, in order")
    func headingsBecomeRows() {
        let rows = NoteChapters.entries(from: [
            block(1, "Adressräume", start: 0),
            block(2, "Der TLB", start: 180),
        ])

        #expect(rows.map(\.title) == ["Adressräume", "Der TLB"])
        #expect(rows.map(\.time) == [0, 180])
        #expect(rows.map(\.blockNumber) == [1, 2])
    }

    /// The case that breaks the rail: a model that answered with a bare
    /// paragraph. A row short is better than a row with an empty label.
    @Test("A card with no heading has no row")
    func headinglessCardsAreSkipped() {
        let rows = NoteChapters.entries(from: [
            block(1, "Adressräume", start: 0),
            block(2, nil, start: 180),
            block(3, "Working Set", start: 360),
        ])

        #expect(rows.count == 2)
        #expect(rows.map(\.blockNumber) == [1, 3])
    }

    @Test("No cards, no rail")
    func noBlocksGivesNoRows() {
        #expect(NoteChapters.entries(from: []).isEmpty)
    }

    @Test("A row holding a marker is flagged")
    func markersFlagTheirRow() {
        let rows = NoteChapters.entries(
            from: [block(1, "Adressräume", start: 0), block(2, "Der TLB", start: 180)],
            markers: [RecordingMarker(time: 200, text: "klausurrelevant")]
        )

        #expect(rows[0].hasMarker == false)
        #expect(rows[1].hasMarker == true)
    }

    @Test("The rail on the notes is the rail derived from its cards")
    func notesExposeTheRail() {
        let notes = RecordingNotes(
            topic: "Paging",
            markdown: "## Alles\nAbsatz.",
            blocks: [block(1, "Adressräume", start: 0)]
        )

        #expect(notes.chapters.map(\.title) == ["Adressräume"])
    }
}

// MARK: -

@Suite("Prompts")
struct PromptTests {

    private func block(_ markers: [RecordingMarker] = []) -> TranscriptBlock {
        TranscriptBlock(
            number: 2,
            lines: [
                TranscriptLine(start: 60, end: 64, text: "Der TLB hält die letzten Übersetzungen.", speaker: .lecturer),
                TranscriptLine(start: 64, end: 66, text: "Was passiert, wenn er voll ist?", speaker: .audience),
            ],
            markers: markers,
            closing: .marker
        )
    }

    @Test("The prompt is English and asks for German")
    func promptAsksForGerman() {
        #expect(NoteReduction.blockSystemPrompt.contains("German"))
        #expect(NoteReduction.reduceSystemPrompt.contains("German"))
    }

    /// The Markdown subset is asked for as well as enforced. Asking is what
    /// makes the model produce it; enforcing is what makes it true.
    @Test("The prompt names the Markdown subset the design draws")
    func promptConstrainsTheMarkdown() {
        for prompt in [NoteReduction.blockSystemPrompt, NoteReduction.reduceSystemPrompt] {
            #expect(prompt.contains("## "))
            #expect(prompt.contains("Never \"#\""))
            #expect(prompt.contains("No tables, no code fences, no images, no links"))
            #expect(prompt.contains("**"))
        }
    }

    @Test("The block prompt carries the block and nothing else")
    func blockPromptCarriesTheBlock() {
        let conversation = NoteReduction.blockPrompt(for: block())

        #expect(conversation.messages.count == 2)
        #expect(conversation.messages[0].role == .system)
        #expect(conversation.messages[1].role == .user)
        #expect(conversation.messages[1].content.contains("Der TLB hält die letzten Übersetzungen."))
        #expect(conversation.messages[1].content.contains("01:00"))
    }

    /// The design labels the annotation bar "goes to the model". This is that
    /// promise, in a test.
    @Test("What the user typed reaches the model")
    func annotationsReachTheModel() {
        let marked = block([RecordingMarker(time: 65, text: "TLB-Größe kommt in der Klausur")])
        let content = NoteReduction.blockPrompt(for: marked).messages[1].content

        #expect(content.contains("TLB-Größe kommt in der Klausur"))
    }

    @Test("A bare marker adds nothing to the prompt")
    func emptyMarkersAreNotMentioned() {
        let marked = block([RecordingMarker(time: 65, text: "   ")])
        let content = NoteReduction.blockPrompt(for: marked).messages[1].content

        #expect(!content.contains("The student marked"))
    }

    @Test("A question from the room is labelled as one")
    func audienceLinesAreLabelled() {
        let text = NoteReduction.transcript(of: block().lines)

        #expect(text.contains("(Frage aus dem Publikum) Was passiert, wenn er voll ist?"))
        #expect(!text.contains("(Frage aus dem Publikum) Der TLB"))
    }

    @Test("The reduce prompt carries both the drafts and the transcript")
    func reducePromptCarriesBoth() {
        let notes = [
            NoteBlock(
                number: 1,
                markdown: "## Adressräume\nJeder Prozess sieht einen **Adressraum**.\n- 4 KiB",
                start: 0,
                end: 180
            )
        ]
        let transcript = [TranscriptLine(start: 0, end: 4, text: "Der virtuelle Adressraum ist eine Abmachung.")]

        let content = NoteReduction.reducePrompt(notes: notes, transcript: transcript).messages[1].content

        #expect(content.contains("Adressräume"))
        #expect(content.contains("4 KiB"))
        #expect(content.contains("Der virtuelle Adressraum ist eine Abmachung."))
        #expect(content.contains("Block 1"))
    }

    /// The reduce model is about to write its own emphasis; carrying the
    /// drafts' asterisks in tells it nothing and costs tokens on every card.
    @Test("The drafts reach the reduce without their formatting")
    func draftsAreFlattened() {
        let note = NoteBlock(number: 1, markdown: "## Adressräume\nEin **Adressraum**.", start: 0, end: 180)
        let draft = NoteReduction.draft(of: note)

        #expect(!draft.contains("**"))
        #expect(!draft.contains("##"))
        #expect(draft.contains("Adressräume"))
    }

    @Test("Timestamps grow a third field only past the hour")
    func timestampsAreReadable() {
        #expect(NoteReduction.timestamp(0) == "00:00")
        #expect(NoteReduction.timestamp(65) == "01:05")
        #expect(NoteReduction.timestamp(3_599) == "59:59")
        #expect(NoteReduction.timestamp(3_600) == "1:00:00")
        #expect(NoteReduction.timestamp(-5) == "00:00")
    }

    @Test("The schemas list every property as required")
    func schemasAreStrictEnough() {
        #expect(NoteReduction.blockSchema.schema.serialized.contains("\"required\":[\"markdown\"]"))
        #expect(NoteReduction.notesSchema.schema.serialized.contains("\"required\":[\"topic\",\"markdown\"]"))
        #expect(NoteReduction.blockSchema.schema.serialized.contains("\"additionalProperties\":false"))
    }

    /// The property order in a schema is the order a constrained decoder makes
    /// the model write the fields in, so it has to survive to the wire.
    @Test("The schema keeps the order its properties were written in")
    func schemaOrderIsStable() throws {
        for _ in 0..<20 {
            let text = NoteReduction.notesSchema.schema.serialized
            let topic = try #require(text.range(of: "\"topic\""))
            let markdown = try #require(text.range(of: "\"markdown\""))

            #expect(topic.lowerBound < markdown.lowerBound)
        }
    }
}

// MARK: -

@Suite("Map: an answer becomes a card")
struct NoteBlockMappingTests {

    private let block = TranscriptBlock(
        number: 3,
        lines: [TranscriptLine(start: 360, end: 540, text: "…")],
        markers: [],
        closing: .speechBudget
    )

    @Test("The card keeps the block's number and its minutes")
    func cardCarriesTheBlock() {
        let answer = NoteReduction.BlockAnswer(
            markdown: "# Page Faults und Thrashing\nEin **Page Fault** ist der normale Weg."
        )
        let note = NoteReduction.noteBlock(from: answer, for: block)

        #expect(note.number == 3)
        #expect(note.start == 360)
        #expect(note.end == 540)
        #expect(note.state == .written)
        // Sanitised on the way in, so nothing downstream has to.
        #expect(note.markdown.hasPrefix("## "))
        #expect(note.heading == "Page Faults und Thrashing")
    }

    /// A one-field schema is exactly where a model skips the envelope and
    /// writes the Markdown on its own.
    @Test("A bare string is accepted as well as an object")
    func bareStringsDecode() throws {
        let object = try StructuredJSON.decode(
            NoteReduction.BlockAnswer.self,
            from: "{\"markdown\": \"## Adressräume\\nAbsatz.\"}"
        )
        let bare = try StructuredJSON.decode(
            NoteReduction.BlockAnswer.self,
            from: "\"## Adressräume\\nAbsatz.\""
        )

        #expect(object == bare)
    }

    @Test("A deferred card is visibly waiting rather than silently missing")
    func deferredCards() {
        let note = NoteReduction.deferredBlock(for: block)

        #expect(note.state == .deferred)
        #expect(note.markdown.isEmpty)
        #expect(note.heading == nil)
        #expect(note.number == 3)
    }
}

// MARK: -

@Suite("Reduce: cards become notes")
struct NoteReductionTests {

    private func cards(_ count: Int) -> [NoteBlock] {
        (1...count).map { number in
            NoteBlock(
                number: number,
                markdown: "## Überschrift \(number)\nAbsatz \(number).",
                start: Double(number - 1) * 180,
                end: Double(number) * 180
            )
        }
    }

    @Test("The notes are the model's own sections, held to the subset")
    func notesCarryTheSections() {
        let answer = NoteReduction.NotesAnswer(
            topic: "Virtueller Speicher und Paging",
            sections: [
                .init(startsAt: "0:00", markdown: "# Seitenersetzung\nDie Auswahl entscheidet über die **Trefferrate**."),
            ]
        )

        let notes = NoteReduction.notes(from: answer)

        #expect(notes.topic == "Virtueller Speicher und Paging")
        // `#` is held down to `##`: the subset the notes are drawn in has one
        // heading level.
        #expect(notes.markdown.hasPrefix("## Seitenersetzung"))
        #expect(notes.blocks.count == 1)
    }

    @Test("A block starts where the model said it does")
    func blocksTakeTheirTimeFromTheAnswer() {
        let answer = NoteReduction.NotesAnswer(
            topic: "Paging",
            sections: [
                .init(startsAt: "0:00", markdown: "## Eins\nAbsatz mit **Begriff**."),
                .init(startsAt: "3:00", markdown: "## Zwei\nAbsatz mit **Anderes**."),
                .init(startsAt: "6:00", markdown: "## Drei\nAbsatz mit **Drittes**."),
            ]
        )

        let notes = NoteReduction.notes(from: answer)

        // Copied from the transcript by the model, not recovered from the
        // Markdown by searching for each section's bold term — which is what
        // this used to do, invented share of the recording and all.
        #expect(notes.chapters.map(\.title) == ["Eins", "Zwei", "Drei"])
        #expect(notes.chapters.map(\.time) == [0, 180, 360])
    }

    @Test("An hour-long recording keeps its hours")
    func longTimestampsAreRead() {
        #expect(NoteReduction.seconds(from: "0:00") == 0)
        #expect(NoteReduction.seconds(from: "12:40") == 760)
        #expect(NoteReduction.seconds(from: "1:05:30") == 3930)
        // Anything unreadable lands at the start rather than refusing the
        // section: a chapter row at zero is worse than nothing, and no notes
        // are worse than both.
        #expect(NoteReduction.seconds(from: "bald") == 0)
        #expect(NoteReduction.seconds(from: "") == 0)
    }

    @Test("Markers come along in time order")
    func markersAreSorted() {
        let answer = NoteReduction.NotesAnswer(
            topic: "Paging",
            sections: [
                .init(startsAt: "0:00", markdown: "## Eins\nAbsatz mit **Begriff**."),
                .init(startsAt: "3:00", markdown: "## Zwei\nAbsatz mit **Anderes**."),
            ]
        )
        let notes = NoteReduction.notes(
            from: answer,
            markers: [RecordingMarker(time: 300, text: "b"), RecordingMarker(time: 100, text: "a")]
        )

        #expect(notes.markers.map(\.text) == ["a", "b"])
        #expect(notes.chapters.map(\.hasMarker) == [true, true])
    }

    @Test("An answer with no sections is a rung that failed")
    func emptySectionsAreUnusable() {
        // The one shape this answer can take that parses and says nothing. It
        // has to reach the ladder as a failure — being stored as an empty set
        // is what put "No notes yet" over a lecture the model had read in full.
        #expect(NoteReduction.NotesAnswer(topic: "Paging", sections: []).isUsable == false)
        #expect(
            NoteReduction.NotesAnswer(
                topic: "Paging",
                sections: [.init(startsAt: "0:00", markdown: "## Nur eine Überschrift")]
            ).isUsable == false
        )
        #expect(
            NoteReduction.NotesAnswer(
                topic: "Paging",
                sections: [.init(startsAt: "0:00", markdown: "## Eins\nEin Absatz mit **Begriff** darin.")]
            ).isUsable
        )
    }

    @Test("A refused topic leaves the recording without one")
    func refusedTopicsBecomeNil() {
        let answer = NoteReduction.NotesAnswer(
            topic: "Zusammenfassung der Vorlesung",
            sections: [.init(startsAt: "0:00", markdown: "## Alles\nEin Absatz mit **Begriff**.")]
        )
        #expect(NoteReduction.notes(from: answer).topic == nil)
    }

    /// Worse notes than a reduce produces, and far better than none.
    @Test("With no reduce the cards are the notes")
    func fallbackJoinsTheCards() {
        let notes = NoteReduction.notes(fallbackFrom: cards(2))

        #expect(notes.markdown.contains("## Überschrift 1"))
        #expect(notes.markdown.contains("## Überschrift 2"))
        #expect(notes.chapters.count == 2)
    }

    /// The topic is the one thing only the reduce can see. Guessing it from the
    /// first card would put one card's subject in the library column for the
    /// whole recording.
    @Test("The fallback claims no topic")
    func fallbackHasNoTopic() {
        #expect(NoteReduction.notes(fallbackFrom: cards(3)).topic == nil)
    }

    @Test("A deferred card contributes nothing to the fallback notes")
    func fallbackSkipsDeferredCards() {
        var blocks = cards(2)
        blocks.append(NoteBlock(number: 3, markdown: "", start: 360, end: 540, state: .deferred))

        let notes = NoteReduction.notes(fallbackFrom: blocks)
        #expect(!notes.markdown.hasSuffix("\n\n"))
        #expect(notes.chapters.count == 2)
    }

    // MARK: - Decoding what models actually send

    @Test("A missing topic is no topic, not a failure")
    func missingTopicIsTolerated() throws {
        let answer = try StructuredJSON.decode(
            NoteReduction.NotesAnswer.self,
            from: "{\"sections\":[{\"starts_at\":\"0:00\",\"markdown\":\"## Eins\\nAbsatz.\"}]}"
        )

        #expect(answer.topic.isEmpty)
        #expect(NoteReduction.notes(from: answer).topic == nil)
    }

    @Test("An answer with no notes in it is not an answer")
    func missingSectionsFails() {
        #expect(throws: (any Error).self) {
            try StructuredJSON.decode(NoteReduction.NotesAnswer.self, from: "{\"topic\":\"Paging\"}")
        }
    }
}
