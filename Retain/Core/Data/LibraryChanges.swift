import Foundation
import GRDB

/// Says when the library changed, so a window that is already open does not
/// have to be closed and reopened to see it.
///
/// **This exists because the app had to be quit.** Every window loaded its
/// lists once and kept them: a course created in Settings did not appear in the
/// library, a deleted term stayed in the picker, and a course deleted anywhere
/// stayed in the sidebar until the process was restarted. Each window was right
/// about what it had read — it just had no way of being told that it was no
/// longer true.
///
/// What is watched is the **shape** of the library: terms, courses, which terms
/// a course runs in, and the recording rows. Not their contents — a transcript
/// line arriving during a lecture must not reload the library, and that happens
/// ten times a second.
nonisolated enum LibraryChanges {

    /// The tables every window's lists are built from.
    private static var tracked: [any DatabaseRegionConvertible] {
        [Table("term"), Table("course"), Table("courseTerm"), Table("recording")]
    }

    /// One element per transaction that touched any of them.
    ///
    /// A signal and not a value: the three windows read different things out of
    /// these tables, and a stream carrying one window's answer would be no use
    /// to the others. What they share is the question "has any of this moved",
    /// and this answers that.
    ///
    /// The first element arrives immediately, so a caller can use this as its
    /// only load rather than loading once and subscribing afterwards — which is
    /// two code paths with a gap between them where a change is missed.
    static func stream(in database: RetainDatabase) -> AsyncValueObservation<Int64> {
        // The fetch is a counter, not the data. Fetching the rows would hand
        // every window the same answer and make each of them throw most of it
        // away; counting transactions is all the windows need to know, and it
        // is one page of SQLite's own bookkeeping rather than a read of the
        // library.
        //
        // `data_version` is bumped by any transaction the connection did not
        // make itself, which is exactly the case this is for — another window
        // wrote something. Its value is never compared for size, only for
        // change, so wrapping is not a concern.
        ValueObservation
            .tracking(regions: tracked) { db in
                try Int64.fetchOne(db, sql: "PRAGMA data_version") ?? 0
            }
            .values(in: database.writer)
    }
}
