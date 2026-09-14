import Foundation
import Testing

@testable import Retain

/// Where a click in the recording detail lands in the audio.
@Suite("Seeking")
struct DetailSeekTests {

    private let blocks = [
        NoteBlock(number: 1, markdown: "## Wann eine Seite verdrängt werden darf\nAbsatz.", start: 240, end: 2940),
        NoteBlock(number: 2, markdown: "## Working Set und Thrashing\nAbsatz.", start: 2940, end: 5520),
    ]

    private let duration: TimeInterval = 5520

    // MARK: - A line

    @Test("A clicked line seeks to where the line starts")
    func aLine() {
        #expect(DetailSeek.target(forLineStartingAt: 3130, duration: duration) == 3130)
    }

    @Test("A line past the end of the recording seeks to the end, not past it")
    func aLineBeyondTheEnd() {
        #expect(DetailSeek.target(forLineStartingAt: 9999, duration: duration) == duration)
    }

    @Test("A recording with no length yet can still be sought inside")
    func noDurationKnown() {
        #expect(DetailSeek.target(forLineStartingAt: 3130, duration: nil) == 3130)
        #expect(DetailSeek.target(forLineStartingAt: 3130, duration: 0) == 3130)
    }

    @Test("Nothing seeks before the first second")
    func negative() {
        #expect(DetailSeek.target(forLineStartingAt: -5, duration: duration) == 0)
    }

    // MARK: - A chapter

    @Test("A chapter seeks to the minute its row draws")
    func aChapter() {
        #expect(DetailSeek.target(forChapterAt: 2940, duration: duration) == 2940)
    }

    // MARK: - A source chip

    @Test("A transcript chip carries its own second")
    func aTranscriptChip() {
        #expect(
            DetailSeek.target(for: .transcript(2300), blocks: blocks, duration: duration) == 2300
        )
    }

    @Test("A note chip lands where that block starts — the same place its chapter row does")
    func aNoteChip() {
        let chip = DetailSeek.target(for: .note(2), blocks: blocks, duration: duration)

        #expect(chip == 2940)
        #expect(chip == DetailSeek.target(forChapterAt: blocks[1].start, duration: duration))
    }

    /// The notes can be written again after an answer was, and a chip reading
    /// "Note 9" that jumps to the start of the recording is worse than one that
    /// does nothing.
    @Test("A chip citing a note that no longer exists resolves to nothing, not to zero")
    func aNoteChipForAMissingBlock() {
        #expect(DetailSeek.target(for: .note(9), blocks: blocks, duration: duration) == nil)
    }

    @Test("A chip past the end of the recording is pulled back to it")
    func aChipBeyondTheEnd() {
        #expect(
            DetailSeek.target(for: .transcript(99_999), blocks: blocks, duration: duration) == duration
        )
    }
}
