import Foundation

/// Every word boards 03 and 04 put on screen.
///
/// Gathered in one place so the string catalog can be read against it. The
/// export is German and the interface is English: these are the translations
/// from the table at the bottom of `docs/design/README.md`, with *Stunde* read
/// as **recording** throughout, since there is no lesson and no lesson number.
nonisolated enum DetailCopy {

    // MARK: - Chrome

    static var export: String {
        String(localized: "Export", comment: "Title-bar button on the recording detail window — the export's Exportieren")
    }

    static var topicLabel: String {
        String(localized: "Topic", comment: "Meta-strip label above the topic the model derived — the export's THEMA")
    }

    static var courseLabel: String {
        String(localized: "Course", comment: "Meta-strip label above the course and term — the export's FACH")
    }

    static var durationLabel: String {
        String(localized: "Duration", comment: "Meta-strip label above the length and marker count — the export's DAUER")
    }

    static var notesTab: String {
        String(localized: "Notes", comment: "Tab showing the written-out notes — the export's Notizen")
    }

    static var transcriptTab: String {
        String(localized: "Transcript", comment: "Tab showing the full transcript — the export's Transkript")
    }

    /// Two values with the export's middle dot between them.
    ///
    /// One string rather than three: the window's title, the Course cell and
    /// the Duration cell are all a pair joined this way, and three separate
    /// calls would collapse to this one key in the catalog anyway.
    static func joined(_ left: String, _ right: String) -> String {
        String(localized: "\(left) · \(right)",
               comment: "Two values side by side, separated by the export's middle dot")
    }

    static func minutes(_ count: Int) -> String {
        String(localized: "\(count) min", comment: "A recording's length in whole minutes")
    }

    static func markers(_ count: Int) -> String {
        String(localized: "\(count) markers", comment: "How many points the user marked during the recording")
    }

    // MARK: - The rail

    static var railSearchPlaceholder: String {
        String(localized: "Search notes and transcript …",
               comment: "Placeholder of the field above the chapters rail, searching inside this one recording")
    }

    static var chaptersSegment: String {
        String(localized: "Chapters", comment: "Rail segment showing the chapters — the export's Kapitel")
    }

    static var chatSegment: String {
        String(localized: "Chat", comment: "Rail segment showing the conversation about this recording")
    }

    static var examRelevant: String {
        String(localized: "exam relevant", comment: "Footer of the chapters rail — the export's klausurrelevant")
    }

    static var noChapters: String {
        String(localized: "No chapters yet.",
               comment: "Chapters rail with nothing in it, because no note block has been written")
    }

    // MARK: - The notes

    /// "You · 00:52:10" above an annotation the user typed during the lecture.
    static func annotationLabel(time: String) -> String {
        String(localized: "You · \(time)",
               comment: "Label above a note the user typed during the recording, with the second they typed it at")
    }

    static var emptyNotes: String {
        String(localized: "The notes for this recording have not been written yet.",
               comment: "Notes tab of a recording the model has not summarised")
    }

    // MARK: - The transcript

    static var speaker: String {
        String(localized: "Speaker", comment: "Who a transcript line belongs to: the person teaching — the export's Lehrerin")
    }

    static var audience: String {
        String(localized: "Audience", comment: "Who a transcript line belongs to: the room — the export's Publikum")
    }

    /// "Speaker · Marker" on a line the user marked.
    static func markedLine(_ speaker: String) -> String {
        String(localized: "\(speaker) · Marker",
               comment: "Label of a transcript line the user marked while it was being said")
    }

    static var findPlaceholder: String {
        String(localized: "Find in transcript …", comment: "Placeholder of the find bar over the transcript")
    }

    /// "3 of 11" beside the find field.
    static func findCount(current: Int, total: Int) -> String {
        String(localized: "\(current) of \(total)",
               comment: "Which find match is current, out of how many — the export's 3 von 11")
    }

    static var findNoMatches: String {
        String(localized: "no matches", comment: "The find bar with a query that matches nothing")
    }

    static var findPrevious: String {
        String(localized: "Previous match", comment: "Accessibility label of the find bar's up arrow")
    }

    static var findNext: String {
        String(localized: "Next match", comment: "Accessibility label of the find bar's down arrow")
    }

    static var emptyTranscript: String {
        String(localized: "This recording has no transcript yet.",
               comment: "Transcript tab of a recording that has not been transcribed")
    }

    // MARK: - The chat

    static var chatIntro: String {
        String(localized: "Questions about this recording. The model sees the notes and the transcript.",
               comment: "Standing note at the top of the chat rail, saying what the model is given")
    }

    /// Not in the export: boards 03 and 04 draw the chat only once it can be
    /// used. The owner's decision is that it cannot be until the recording has
    /// stopped *and* the summary is written, so the rail has to say which of
    /// the two is still outstanding.
    ///
    /// The words come from `SummarizationError`, which already has to say the
    /// same two things when a question is sent anyway. One sentence in one
    /// place: the rail and the failure can never word it differently.
    static func chatNotReady(_ availability: ChatAvailability) -> String {
        SummarizationError.chatNotReady(availability).errorDescription ?? ""
    }

    static var askPlaceholder: String {
        String(localized: "Ask a question …", comment: "Placeholder of the chat composer — the export's Frage stellen …")
    }

    static var send: String {
        String(localized: "Send", comment: "Accessibility label of the chat composer's return key")
    }

    /// "Note 1" on a source chip under an answer.
    static func noteChip(_ number: Int) -> String {
        String(localized: "Note \(number)", comment: "Chat source chip citing a note block — the export's Notiz 1")
    }

    static var thinking: String {
        String(localized: "Writing an answer", comment: "Accessibility label of the three-dot typing indicator")
    }
}
