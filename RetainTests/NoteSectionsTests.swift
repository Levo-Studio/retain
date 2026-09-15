import Foundation
import Testing

@testable import Retain

/// Cutting the finished notes into the blocks the interface is built from.
///
/// **This suite exists for a lecture that produced nothing.** The finished
/// blocks used to be the draft cards passed straight through, which worked for
/// as long as there were drafts. Nothing is summarised during a lecture any
/// more, so the function was handed an empty array and returned one: the model
/// answered in full, the Markdown came back, the block list did not, nothing
/// was written to the store, and the window said "No notes yet" over a lecture
/// it had just read.
@Suite("Cutting the notes into blocks")
struct NoteSectionsTests {

    private func line(_ text: String, at start: TimeInterval) -> TranscriptLine {
        TranscriptLine(start: start, end: start + 10, text: text, speaker: .lecturer)
    }

    private var lecture: [TranscriptLine] {
        [
            line("Heute geht es um Symbiose, und zwar am Beispiel der Korallenriffe", at: 0),
            line("Symbiose ist das Zusammenleben zweier Arten mit Nutzen für beide", at: 40),
            line("In den Zellen der Koralle leben Zooxanthellen, das sind Algen", at: 120),
            line("Wird das Wasser zu warm, kommt es zur Korallenbleiche", at: 300),
        ]
    }

    // MARK: - Cutting

    @Test("Every heading starts a block")
    func headingsBecomeBlocks() {
        let markdown = """
            ## Symbiose

            Zusammenleben zweier Arten mit Nutzen für **Symbiose** beide.

            ## Zooxanthellen

            In der Koralle leben **Zooxanthellen**, die Photosynthese betreiben.

            ## Korallenbleiche

            Zu warmes Wasser führt zur **Korallenbleiche**.
            """

        let blocks = NoteSections.blocks(from: markdown, transcript: lecture)

        #expect(blocks.count == 3)
        #expect(blocks.map(\.number) == [1, 2, 3])
        #expect(blocks.first?.markdown.hasPrefix("## Symbiose") == true)
    }

    @Test("An answer with no heading at all is still one block")
    func aBareParagraphIsOneBlock() {
        let blocks = NoteSections.blocks(
            from: "Algen leben in **Korallen** und liefern Zucker.",
            transcript: lecture
        )
        // A model that answered with a paragraph has written something, and
        // dropping it would lose it silently.
        #expect(blocks.count == 1)
    }

    @Test("Nothing in, nothing out")
    func emptyStaysEmpty() {
        #expect(NoteSections.blocks(from: "", transcript: lecture).isEmpty)
        #expect(NoteSections.blocks(from: "   \n\n ", transcript: lecture).isEmpty)
    }

    // MARK: - Anchoring

    @Test("A block starts where its own term was said")
    func blocksAreAnchoredToTheTranscript() {
        let markdown = """
            ## Zooxanthellen

            In der Koralle leben **Zooxanthellen**.

            ## Bleiche

            Zu warmes Wasser führt zur **Korallenbleiche**.
            """

        let blocks = NoteSections.blocks(from: markdown, transcript: lecture)

        // Not a share of the recording: the minute the word was actually said.
        #expect(blocks.first?.start == 120)
        #expect(blocks.last?.start == 300)
    }

    @Test("Times never run backwards")
    func anchorsAreMonotonic() {
        // "Symbiose" is said at 0 and the section about it comes second, so a
        // naive search would anchor block two before block one.
        let markdown = """
            ## Bleiche

            Zu warmes Wasser führt zur **Korallenbleiche**.

            ## Symbiose

            Das Zusammenleben heißt **Symbiose**.
            """

        let blocks = NoteSections.blocks(from: markdown, transcript: lecture)
        let starts = blocks.map(\.start)
        #expect(starts == starts.sorted())
    }

    @Test("A term that was never said falls back to a share of the recording")
    func anUnfoundTermFallsBack() {
        let markdown = """
            ## Etwas anderes

            Hier steht ein **Quantenfeld**, das niemand gesagt hat.
            """

        let blocks = NoteSections.blocks(from: markdown, transcript: lecture)
        // The first section's share is the beginning, which is also the only
        // honest answer when there is nothing to anchor to.
        #expect(blocks.first?.start == 0)
    }

    @Test("A two-letter term anchors nothing")
    func shortTermsAreIgnored() {
        #expect(NoteSections.boldTerm(in: "Das **ei** ist rund.") == nil)
        #expect(NoteSections.boldTerm(in: "Die **Koralle** lebt.") == "Koralle")
        #expect(NoteSections.boldTerm(in: "Kein Begriff hier.") == nil)
    }
}
