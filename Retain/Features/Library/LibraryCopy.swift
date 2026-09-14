import Foundation

/// Every word board 05 puts on screen.
///
/// Two deliberate departures from the export, both settled by the owner and
/// both about the same thing: **there is no lesson.** The `Nr.` column is gone,
/// so the first column is the topic; and the `Datum` column now carries the
/// date *and* the time of day, because that pair is what identifies a
/// recording, so it is labelled "Started" rather than "Date".
///
/// The course header also drops the teacher. Board 05 draws "Frau Reinhardt"
/// and nothing in the app has ever had a teacher in it.
nonisolated enum LibraryCopy {

    static var windowTitle: String {
        String(localized: "Library", comment: "Title of the library window — the export's Bibliothek")
    }

    static var rename: String {
        String(localized: "Rename", comment: "Action beside the term's name in the library sidebar")
    }

    static var newCourse: String {
        String(localized: "+ New course", comment: "Action at the foot of the library sidebar — the export's + Kurs anlegen")
    }

    static var searchPlaceholder: String {
        String(localized: "Search every recording in this term …",
               comment: "Placeholder of the library's full-text search field")
    }

    static var sortByDate: String {
        String(localized: "by date", comment: "The library's sort order — the export's chronologisch")
    }

    // MARK: - Counts

    static func courses(_ count: Int) -> String {
        String(localized: "\(count) courses", comment: "How many courses are in a term")
    }

    static func recordings(_ count: Int) -> String {
        String(localized: "\(count) recordings", comment: "How many recordings are in a course")
    }

    /// "13 h 24 min" — every recording in the course added up.
    static func hoursAndMinutes(hours: Int, minutes: Int) -> String {
        String(localized: "\(hours) h \(minutes) min",
               comment: "A total length in hours and minutes, in the library's course header")
    }

    static func minutes(_ count: Int) -> String {
        String(localized: "\(count) min", comment: "A recording's length in whole minutes, in the library table")
    }

    /// "Oct 2025 – Mar 2026 · 4 courses" under the term's name.
    static func termPeriod(from: String, to: String, courses: String) -> String {
        String(localized: "\(from) – \(to) · \(courses)",
               comment: "A term's period and how many courses are in it, in the library sidebar")
    }

    /// "Third year, winter · 9 recordings · 13 h 24 min" beside a course.
    static func courseSummary(term: String, recordings: String, total: String) -> String {
        String(localized: "\(term) · \(recordings) · \(total)",
               comment: "Under a course heading: its term, how many recordings it has, and how long they run to")
    }

    // MARK: - The table

    static var topicColumn: String {
        String(localized: "Topic", comment: "Library table column showing what the model decided a recording is about")
    }

    /// The export says `Datum`. A recording is identified by its date *and* its
    /// time of day, so the column carries both and says so.
    static var startedColumn: String {
        String(localized: "Started", comment: "Library table column showing the date and time a recording started")
    }

    static var durationColumn: String {
        String(localized: "Duration", comment: "Library table column showing how long a recording ran")
    }

    static var statusColumn: String {
        String(localized: "Status", comment: "Library table column showing where a recording has got to")
    }

    static var today: String {
        String(localized: "Today", comment: "The Started column for a recording made today — the export's Heute")
    }

    /// "Today, 10:15" and "7 Sep, 10:15".
    static func startedAt(day: String, time: String) -> String {
        String(localized: "\(day), \(time)", comment: "A recording's start: which day, then the time of day")
    }

    // MARK: - Where a recording has got to

    static var stateRecording: String {
        String(localized: "recording", comment: "A recording that is running right now — the export's läuft")
    }

    static var stateTranscribing: String {
        String(localized: "transcribing", comment: "A recording whose audio is being read through again after it stopped")
    }

    static var stateSummarizing: String {
        String(localized: "summarizing", comment: "A recording whose notes are being written — the export's wird zusammengefasst")
    }

    static var stateDone: String {
        String(localized: "done", comment: "A recording with finished notes — the export's fertig")
    }

    // MARK: - Nothing there

    static var noTerms: String {
        String(localized: "No terms yet.", comment: "The library before the first term has been named")
    }

    static var noCourses: String {
        String(localized: "No courses in this term yet.", comment: "The library sidebar for a term with no courses")
    }

    static var noRecordings: String {
        String(localized: "No recordings in this course yet.", comment: "The library table for a course with no recordings")
    }

    static var noResults: String {
        String(localized: "Nothing in this term matches.", comment: "Full-text search that found nothing")
    }

    // MARK: - Search results

    /// Board 05 draws the search field and no result state. A hit is shown
    /// under the recording it is in, and these label where it came from.
    static var hitInTranscript: String {
        String(localized: "transcript", comment: "A search hit that is a line somebody said")
    }

    static var hitInNotes: String {
        String(localized: "notes", comment: "A search hit that is in a note block")
    }

    static var hitInAnnotation: String {
        String(localized: "your note", comment: "A search hit that is in something the user typed during the recording")
    }
}
