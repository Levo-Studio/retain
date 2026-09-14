import Foundation
import Testing

@testable import Retain

/// What the library table puts in each column — and above all what it puts in
/// the Topic column when there is no topic.
@Suite("Library table")
struct RecordingPresentationTests {

    private let english = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC") ?? .gmt

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private func recording(
        topic: String? = nil,
        at startedAt: Date = StoreFixture.instant(2026, 9, 7, 10, 15),
        duration: TimeInterval = 5520,
        state: RecordingState = .done
    ) -> Recording {
        Recording(
            id: 1,
            courseID: 1,
            termID: 1,
            startedAt: startedAt,
            duration: duration,
            state: state,
            topic: topic
        )
    }

    // MARK: - The Topic column

    @Test("A recording with a topic shows it")
    func withATopic() {
        let row = recording(topic: "Seitenersetzung und Working Set")

        #expect(RecordingPresentation.title(of: row, locale: english, timeZone: utc) == "Seitenersetzung und Working Set")
        #expect(RecordingPresentation.hasTopic(row))
    }

    /// The model derives the topic and may never have run. The column then
    /// carries the one thing a recording always has — when it happened — and
    /// never a placeholder, which would sort and read as if it were a topic.
    @Test("A recording with no topic shows when it happened, not a placeholder")
    func withNoTopic() {
        let title = RecordingPresentation.title(of: recording(), locale: english, timeZone: utc)

        #expect(!RecordingPresentation.hasTopic(recording()))
        #expect(title.contains("2026"))
        #expect(title.contains("September"))
        #expect(title.contains("10:15"))
        #expect(!title.contains("—"))
        #expect(!title.localizedStandardContains("untitled"))
    }

    @Test("A topic of nothing but spaces is no topic")
    func withABlankTopic() {
        let row = recording(topic: "   ")

        #expect(!RecordingPresentation.hasTopic(row))
        #expect(RecordingPresentation.title(of: row, locale: english, timeZone: utc).contains("2026"))
    }

    // MARK: - The Started column

    /// The export draws the day alone, because it had a lesson number to tell
    /// two recordings apart with. There is none, so the time of day is drawn.
    @Test("Started carries the day and the time of day")
    func started() {
        let text = RecordingPresentation.started(
            of: recording(),
            now: StoreFixture.instant(2026, 9, 14, 9, 0),
            calendar: calendar,
            locale: english,
            timeZone: utc
        )

        #expect(text.contains("7"))
        #expect(text.contains("Sep"))
        #expect(text.contains("10:15"))
    }

    @Test("A recording made today says so, as the export does")
    func today() {
        let text = RecordingPresentation.started(
            of: recording(at: StoreFixture.instant(2026, 9, 14, 8, 30)),
            now: StoreFixture.instant(2026, 9, 14, 9, 0),
            calendar: calendar,
            locale: english,
            timeZone: utc
        )

        #expect(text.contains(LibraryCopy.today))
        #expect(text.contains("08:30") || text.contains("8:30"))
    }

    @Test("Two recordings on one afternoon are told apart by the time")
    func twoInOneDay() {
        let morning = recording(at: StoreFixture.instant(2026, 9, 7, 10, 15))
        let afternoon = recording(at: StoreFixture.instant(2026, 9, 7, 14, 45))

        let one = RecordingPresentation.started(of: morning, calendar: calendar, locale: english, timeZone: utc)
        let two = RecordingPresentation.started(of: afternoon, calendar: calendar, locale: english, timeZone: utc)

        #expect(one != two)
    }

    // MARK: - Duration and status

    @Test("Duration is whole minutes, and a recording with no length yet has an empty cell")
    func duration() {
        #expect(RecordingPresentation.duration(of: recording(duration: 5520)) == LibraryCopy.minutes(92))
        #expect(RecordingPresentation.duration(of: recording(duration: 0)) == "")
    }

    @Test("All four states are named, and only the running one is the running one")
    func states() {
        #expect(RecordingPresentation.state(of: recording(state: .recording)) == LibraryCopy.stateRecording)
        #expect(RecordingPresentation.state(of: recording(state: .transcribing)) == LibraryCopy.stateTranscribing)
        #expect(RecordingPresentation.state(of: recording(state: .summarizing)) == LibraryCopy.stateSummarizing)
        #expect(RecordingPresentation.state(of: recording(state: .done)) == LibraryCopy.stateDone)

        #expect(RecordingPresentation.isRunning(recording(state: .recording)))
        #expect(!RecordingPresentation.isRunning(recording(state: .summarizing)))
    }

    // MARK: - The course header's total

    @Test("A course's total is hours and minutes once it runs to an hour")
    func total() {
        #expect(RecordingPresentation.total(48_240) == LibraryCopy.hoursAndMinutes(hours: 13, minutes: 24))
        #expect(RecordingPresentation.total(2820) == LibraryCopy.minutes(47))
        #expect(RecordingPresentation.total(3600) == LibraryCopy.hoursAndMinutes(hours: 1, minutes: 0))
    }
}

// MARK: -

@Suite("Clock forms")
struct RetainTimeFormatTests {

    /// The board draws `00:50:14` forty-nine minutes in: the zero hour is
    /// written out, which `NoteReduction.timestamp` does not do.
    @Test("A transcript timestamp always has its hours")
    func clock() {
        #expect(RetainTimeFormat.clock(3014) == "00:50:14")
        #expect(RetainTimeFormat.clock(3130) == "00:52:10")
        #expect(RetainTimeFormat.clock(4460) == "01:14:20")
        #expect(RetainTimeFormat.clock(0) == "00:00:00")
    }

    /// The last chapter of a ninety-two minute recording reads `01:14`, so the
    /// rail is hours and minutes and not minutes and seconds.
    @Test("A chapter row is hours and minutes")
    func hourMinute() {
        #expect(RetainTimeFormat.hourMinute(240) == "00:04")
        #expect(RetainTimeFormat.hourMinute(2940) == "00:49")
        #expect(RetainTimeFormat.hourMinute(4440) == "01:14")
    }

    @Test("Seeking is never rounded up past the word it should land before")
    func truncates() {
        #expect(RetainTimeFormat.clock(50.9) == "00:00:50")
    }

    @Test("A duration rounds to the minute a person would say")
    func minutes() {
        #expect(RetainTimeFormat.wholeMinutes(5520) == 92)
        #expect(RetainTimeFormat.wholeMinutes(5500) == 92)
        #expect(RetainTimeFormat.wholeMinutes(0) == 0)
        #expect(RetainTimeFormat.wholeMinutes(-10) == 0)
    }

    @Test("Hours and minutes together never read as more time than there was")
    func split() {
        let split = RetainTimeFormat.hoursAndMinutes(48_240)
        #expect(split.hours == 13)
        #expect(split.minutes == 24)
        #expect(!RetainTimeFormat.spansAnHour(3540))
        #expect(RetainTimeFormat.spansAnHour(3600))
    }
}
