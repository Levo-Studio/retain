import Foundation

/// What writing a recording's notes again costs.
///
/// Running the model over a transcript that already has notes is not the same
/// action as writing them for the first time, and the difference is the
/// highlights. A highlight is a passage of the notes somebody marked by hand;
/// it hangs off the note block it was marked in, and replacing the blocks takes
/// it with them. Nobody can mark a passage again that they no longer have.
///
/// So this is counted before the question is asked, the same way a term's and a
/// recording's deletion are.
nonisolated struct ReanalysisImpact: Equatable, Sendable {

    /// Blocks the model wrote, which are the ones being replaced.
    let noteBlocks: Int

    /// Passages the reader marked in them. **The part that cannot come back.**
    let highlights: Int

    /// Lines the model will be given. Zero means there is nothing to work from
    /// and the action is refused rather than confirmed.
    let transcriptLines: Int

    /// Nothing written yet — the first-time case, which needs no warning at all
    /// because there is nothing to lose.
    var isFirstTime: Bool { noteBlocks == 0 }

    var canRun: Bool { transcriptLines > 0 }
}
