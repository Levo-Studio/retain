import Foundation

/// Where recordings live on disk.
///
/// `~/Library/Application Support/Retain/Recordings/`, not Documents: a lecture
/// recording is Retain's own data, the user reaches it through Retain, and a
/// folder of opaque CAF files in Documents is clutter they did not ask for.
/// Retain is not sandboxed, so this is the real path and not a container.
///
/// Nothing in here stays for long. A recording is deleted as soon as it has
/// been transcribed — see `TransientAudio` — so on a settled install this folder
/// holds the lecture currently being recorded and nothing else.
///
/// The name carries the date and a random suffix rather than a running number.
/// Two recordings started in the same minute must not collide, and a number
/// would have to be derived from what is already in the folder — which makes
/// the filename depend on a directory listing that can be wrong.
nonisolated enum RecordingStore {

    static var directory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Retain", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    static func newRecordingURL(startedAt date: Date = .now) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let suffix = UUID().uuidString.prefix(6)

        return directory
            .appendingPathComponent("\(formatter.string(from: date))-\(suffix)")
            .appendingPathExtension(CaptureFormat.fileExtension)
    }
}
