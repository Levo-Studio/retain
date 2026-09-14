import AppKit
import Foundation
import UniformTypeIdentifiers

/// What the title bar's `Export` button does.
///
/// The export draws the button and nothing behind it — no menu, no format
/// picker, no destination — and the owner has settled that it is not a menu.
/// So it is the one thing it can be without inventing a format: the notes are
/// Markdown already, and this writes them out as a file.
nonisolated enum NotesExport {

    /// The suggested file name: the course and when the recording started,
    /// which is what identifies a recording. No lesson number, because there
    /// is none.
    static func suggestedName(recording: Recording, course: String) -> String {
        let stamp = recording.startedAt.formatted(
            .verbatim(
                "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
                locale: .init(identifier: "en_US_POSIX"),
                timeZone: .current,
                calendar: .init(identifier: .gregorian)
            )
        )
        let name = course.isEmpty ? stamp : "\(course) \(stamp)"
        return name.replacingOccurrences(of: "/", with: "-")
    }

    @MainActor
    static func run(markdown: String, recording: Recording, course: String) {
        guard !markdown.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = suggestedName(recording: recording, course: course)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(markdown.utf8).write(to: url, options: .atomic)
    }
}
