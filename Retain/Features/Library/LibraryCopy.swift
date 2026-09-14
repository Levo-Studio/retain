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

    /// Drawn with `RetainGlyph.add` in front of it, which is how the export
    /// writes it — and the same words board 07's sheet is titled with, so it is
    /// the same key.
    static var editCourse: String {
        String(localized: "Edit course", comment: "Edit-course dialog title, and the action that opens it")
    }

    static var newCourse: String {
        String(localized: "New course", comment: "Creating a course: the library sidebar's action and the dialog that opens")
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

    /// "Oct 2025 – Mar 2026 · 4 courses" under the term's name, or "4 courses"
    /// on its own for a term nobody dated.
    ///
    /// The period is the optional half. `TermPeriod` decides how it reads; this
    /// only decides whether the middle dot is there, because a line beginning
    /// with a separator is worse than a line that is simply shorter.
    static func termSubtitle(period: String?, courses: String) -> String {
        guard let period else { return courses }
        return joined(period, courses)
    }

    /// Two values side by side, separated by the export's middle dot.
    ///
    /// One key rather than one per place it is used: the separator is the
    /// export's and the words either side of it are already translated, so a
    /// second copy would be a second thing to keep in step for no gain.
    static func joined(_ left: String, _ right: String) -> String {
        String(localized: "\(left) · \(right)",
               comment: "Two values side by side, separated by the export's middle dot")
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

    /// "Today · 10:15" and "7 Sep · 10:15" — the export's own separator, since
    /// the column now carries two values where it used to carry one.
    static func startedAt(day: String, time: String) -> String {
        joined(day, time)
    }

    // MARK: - Where a recording has got to

    static var stateRecording: String {
        String(localized: "recording", comment: "A recording that is running right now — the export's läuft")
    }

    /// The batch pass over the audio, after the microphone stopped. "Re-",
    /// because the live transcript already exists and this is the authoritative
    /// pass being made over the same recording — and because the status-bar
    /// menu already owns the word "Transcribing" on its own.
    static var stateTranscribing: String {
        String(localized: "re-transcribing",
               comment: "A recording whose audio is being read through again after it stopped")
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
        String(localized: "in the transcript", comment: "A search hit that is a line somebody said")
    }

    static var hitInNotes: String {
        String(localized: "in the notes", comment: "A search hit that is in a note block")
    }

    static var hitInAnnotation: String {
        String(localized: "in your note",
               comment: "A search hit that is in something the user typed during the recording")
    }
}

// MARK: - A term's period, however much of it there is

/// The caption under a term's name in board 05's sidebar — the "Oct 2025 –
/// Mar 2026" half of it.
///
/// **A period is never mandatory and nothing computes with it.** It is a
/// caption, so all four shapes of it have to read as a caption: both endpoints,
/// one endpoint, the other endpoint, and none. What is not allowed is a dash
/// with nothing on one side of it, or a date nobody typed standing in for one
/// they did not.
///
/// Kept here, beside the rest of board 05's words, rather than on `Term`: the
/// model is a row and knows nothing about how it is drawn, and this is the only
/// place in the app that turns a period into words.
nonisolated enum TermPeriod {

    /// The caption, or `nil` when there is no period at all — which is a line
    /// that is simply absent, not an empty one and not a placeholder.
    static func caption(of term: Term) -> String? {
        switch (term.startsOn, term.endsOn) {
        case let (start?, end?):
            String(localized: "\(TermMonth.label(start)) – \(TermMonth.label(end))",
                   comment: "A term's period, with both endpoints — the export's Okt 2025 – März 2026")
        case let (start?, nil):
            String(localized: "from \(TermMonth.label(start))",
                   comment: "A term's period whose end was left empty")
        case let (nil, end?):
            String(localized: "until \(TermMonth.label(end))",
                   comment: "A term's period whose start was left empty")
        case (nil, nil):
            nil
        }
    }
}
