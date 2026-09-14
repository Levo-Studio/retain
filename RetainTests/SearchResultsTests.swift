import Foundation
import Testing

@testable import Retain

/// How the flat list of matches the repository returns becomes something to
/// read: grouped by recording, newest first, and inside a recording in the
/// order the things were said.
@Suite("Search results")
struct SearchResultsTests {

    private func hit(
        _ id: String,
        source: SearchHit.Source = .transcript,
        recording: Int64,
        startedAt: Date,
        topic: String? = "Seitenersetzung und Working Set",
        course: String = "Informatik",
        time: TimeInterval,
        text: String = "Genau diese Menge nennen wir das Working Set."
    ) -> SearchHit {
        SearchHit(
            id: id,
            source: source,
            recordingID: recording,
            recordingStartedAt: startedAt,
            recordingTopic: topic,
            courseID: 1,
            courseName: course,
            time: time,
            text: text
        )
    }

    private let older = StoreFixture.instant(2026, 8, 31, 10, 15)
    private let newer = StoreFixture.instant(2026, 9, 7, 10, 15)

    @Test("Matches from one recording become one group")
    func groupsByRecording() {
        let groups = SearchResults.groups(from: [
            hit("t-1", recording: 8, startedAt: newer, time: 3130),
            hit("t-2", recording: 8, startedAt: newer, time: 3181),
            hit("t-3", recording: 7, startedAt: older, time: 900),
        ])

        #expect(groups.count == 2)
        #expect(groups[0].hits.count == 2)
        #expect(groups[1].hits.count == 1)
    }

    @Test("The newest recording comes first — the order the export's control names")
    func newestFirst() {
        let groups = SearchResults.groups(from: [
            hit("t-3", recording: 7, startedAt: older, time: 900),
            hit("t-1", recording: 8, startedAt: newer, time: 3130),
        ])

        #expect(groups.map(\.recordingID) == [8, 7])
    }

    @Test("Inside a recording the earliest second comes first")
    func earliestSecondFirst() {
        let groups = SearchResults.groups(from: [
            hit("t-2", recording: 8, startedAt: newer, time: 3181),
            hit("n-1", source: .note, recording: 8, startedAt: newer, time: 240),
            hit("t-1", recording: 8, startedAt: newer, time: 3130),
        ])

        #expect(groups[0].hits.map(\.time) == [240, 3130, 3181])
    }

    /// Two recordings on one afternoon are ordinary, so the grouping may not
    /// fold them together or leave their order to chance.
    @Test("Two recordings that started on the same day stay two groups, in a settled order")
    func sameDayDifferentTime() {
        let morning = StoreFixture.instant(2026, 9, 7, 10, 15)
        let afternoon = StoreFixture.instant(2026, 9, 7, 14, 45)

        let groups = SearchResults.groups(from: [
            hit("a", recording: 8, startedAt: morning, time: 10),
            hit("b", recording: 9, startedAt: afternoon, time: 10),
        ])

        #expect(groups.map(\.recordingID) == [9, 8])
    }

    @Test("A group carries what it takes to label it, topic or not")
    func labels() {
        let groups = SearchResults.groups(from: [
            hit("a", recording: 8, startedAt: newer, topic: nil, time: 10)
        ])

        #expect(groups[0].topic == nil)
        #expect(groups[0].courseName == "Informatik")
        #expect(groups[0].startedAt == newer)
    }

    @Test("Nothing in, nothing out")
    func empty() {
        #expect(SearchResults.groups(from: []).isEmpty)
    }

    // MARK: - Rows

    @Test("A note hit reads as a sentence, not as Markdown")
    func noteSnippet() {
        let snippet = SearchResults.snippet(
            of: hit(
                "n-1",
                source: .note,
                recording: 8,
                startedAt: newer,
                time: 240,
                text: "## Working Set und Thrashing\nDas **Working Set** ist die Menge der Seiten."
            )
        )

        #expect(!snippet.contains("#"))
        #expect(!snippet.contains("*"))
        #expect(snippet == "Working Set und Thrashing")
    }

    @Test("A transcript hit is the line itself")
    func transcriptSnippet() {
        let line = "Genau diese Menge nennen wir das Working Set."
        #expect(SearchResults.snippet(of: hit("t-1", recording: 8, startedAt: newer, time: 3130, text: line)) == line)
    }

    @Test("Each of the three indexes says where it came from, and they differ")
    func sourceLabels() {
        let labels = Set([
            SearchResults.label(for: .transcript),
            SearchResults.label(for: .note),
            SearchResults.label(for: .annotation),
        ])
        #expect(labels.count == 3)
    }
}
