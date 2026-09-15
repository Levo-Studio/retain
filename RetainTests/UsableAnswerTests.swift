import Foundation
import Testing

@testable import Retain

/// The rung of the ladder that succeeds without answering.
///
/// Found on the owner's machine, in the database: two note blocks whose entire
/// content was `## ...`. The model had been asked for a note under a strict
/// `json_schema` and had returned valid JSON, with the right field, and a stop
/// reason saying it had finished — a heading and nothing under it. The card was
/// stored and drawn as three dots, and the owner reported the notes column as
/// frozen.
///
/// The same model, on the same transcript, asked as free text, writes a
/// complete German note. Retain's ladder is there for exactly that — strict,
/// then `json_object`, then free text — and it never descended, because
/// descending needs a *failure* and this rung did not fail. `Codable` cannot
/// see the difference between a note and an empty shape; `UsableAnswer` can.
@Suite("An answer that is an answer")
struct UsableAnswerTests {

    // MARK: - What counts as a note

    @Test("A heading with nothing under it is not a note")
    func aBareHeadingIsRejected() {
        // Verbatim what was in the owner's database.
        #expect(NoteReduction.BlockAnswer(markdown: "## ...").isUsable == false)
        #expect(NoteReduction.BlockAnswer(markdown: "## Lern…").isUsable == false)
        #expect(NoteReduction.BlockAnswer(markdown: "").isUsable == false)
        #expect(NoteReduction.BlockAnswer(markdown: "   \n\n  ").isUsable == false)
    }

    @Test("A body of a handful of characters is not a note either")
    func aScrapIsRejected() {
        #expect(NoteReduction.BlockAnswer(markdown: "## Korallen\n\nJa.").isUsable == false)
    }

    @Test("A short but real note passes")
    func aShortNotePasses() {
        // A three-minute block honestly summarised in one sentence is a note,
        // and the bar must not be so high that it fails.
        let short = NoteReduction.BlockAnswer(
            markdown: "## Korallen\n\nAlgen leben in **Korallen** und liefern Zucker."
        )
        #expect(short.isUsable)
    }

    @Test("A full note passes")
    func aFullNotePasses() {
        let answer = NoteReduction.BlockAnswer(markdown: """
            ## Symbiontische Algen in Korallen

            In vielen **Korallen** leben Algen in den Zellen. Sie liefern durch \
            Photosynthese Nahrung, die Koralle bietet Schutz.

            - Symbiose
            - Photosynthese
            """)
        #expect(answer.isUsable)
    }

    @Test("A note with no heading at all is still a note")
    func aHeadinglessNotePasses() {
        // The model is asked for a heading and usually writes one, but a note
        // without it is still something a reader can use — and the schema's
        // own decoder accepts a bare string for the same reason.
        #expect(
            NoteReduction.BlockAnswer(
                markdown: "Algen leben in **Korallen** und liefern Zucker durch Photosynthese."
            ).isUsable
        )
    }
}
