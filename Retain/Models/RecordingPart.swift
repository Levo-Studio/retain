import Foundation

/// Where one part of a merged recording begins.
///
/// A lesson recorded in two sittings — the microphone stopped at the break and
/// was started again afterwards — is two rows in the library and one lesson in
/// the room. Merging joins them into one recording, and these say where each
/// part of it started, so the transcript can mark the seam instead of reading
/// as a single lecture with an unexplained jump in it.
///
/// **A recording made in one sitting has none of these.** Their absence is the
/// ordinary case and means exactly what it looks like.
nonisolated struct RecordingPart: Identifiable, Hashable, Sendable, Codable {

    var id: Int64?

    var recordingID: Int64

    /// Where this part begins inside the merged timeline, in seconds from the
    /// start of it. The first part is zero.
    var offset: TimeInterval

    /// When this part was originally recorded.
    ///
    /// Kept because the offsets alone cannot say it: the gap between two
    /// sittings is not recorded audio, so a merged timeline is continuous even
    /// where the afternoon was not. This is what lets the transcript say the
    /// second part began twenty minutes later.
    var startedAt: Date

    /// How long this part ran.
    var duration: TimeInterval

    init(
        id: Int64? = nil,
        recordingID: Int64,
        offset: TimeInterval,
        startedAt: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.recordingID = recordingID
        self.offset = offset
        self.startedAt = startedAt
        self.duration = duration
    }
}
