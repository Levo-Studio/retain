import SwiftUI

/// The whole window while a lecture is running: the transcript, and nothing
/// else.
///
/// **The notes column is gone from here, and so is the model.** Retain used to
/// summarise the lecture as it went — a card every three minutes, each written
/// from those three minutes in isolation and from the live transcript, which
/// sits around 10 % word error against the batch pass's 5.9 %. The cards
/// overlapped, repeated themselves and cut topics in half, and they were the
/// notes the lecture ended with. The owner's reading of it was that the live
/// notes were rubbish and only a re-analysis produced anything worth keeping,
/// which is exactly what a model reading three minutes at a time off the worse
/// transcript would produce.
///
/// So nothing is sent while the lecture runs. The model is given the finished
/// transcript, once, with the whole hour in front of it. What is on screen in
/// the meantime is the one thing that is actually true at that moment: the
/// words, as they are recognised.
struct LiveTranscriptPane: View {

    let shell: ShellModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            AnnotationComposer(shell: shell)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Broken out of `body` rather than nested in it: the type checker gives up
    /// on the whole thing as one expression.
    private var transcript: some View {
        ScrollViewReader { scroll in
            ScrollView {
                column
                    .overlay(alignment: .bottom) {
                        Color.clear.frame(height: 1).id(Self.endID)
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: lines.count) { follow(scroll) }
            .onChange(of: shell.session.partial) { follow(scroll) }
            .task { follow(scroll) }
        }
    }

    private var column: some View {
        let shown = lines
        let newest = shown.last?.id

        return LazyVStack(alignment: .leading, spacing: RetainMetrics.transcriptFullLineGap) {
            ForEach(shown) { line in
                TranscriptLineRow(
                    line: line,
                    // The reading size, not the rail's. The transcript has the
                    // window to itself now.
                    bodyStyle: RetainTypography.transcriptLineMain,
                    isNewest: line.id == newest
                )
                .id(line.id)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: RetainMetrics.transcriptFullColumn, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(RetainMetrics.transcriptFullPadding)
    }

    // MARK: -

    private static let endID = "live-transcript-end"

    /// The finished lines plus the one currently forming.
    ///
    /// The partial is a line like any other as far as this is concerned — it is
    /// the newest, so it is the one at full strength with the caret after it —
    /// and it is built here rather than kept in the session because it is not a
    /// line yet: it has no end and it will be replaced by one.
    private var lines: [TranscriptLine] {
        guard !shell.session.partial.isEmpty else { return shell.session.lines }
        return shell.session.lines + [
            TranscriptLine(
                id: Self.partialID,
                start: shell.session.lines.last?.end ?? 0,
                end: shell.session.recorder.duration,
                text: shell.session.partial,
                isProvisional: true
            )
        ]
    }

    /// One id for the line being spoken, so it is updated in place rather than
    /// inserted and removed on every partial result.
    private static let partialID = UUID()

    private func follow(_ scroll: ScrollViewProxy) {
        withAnimation(RetainMotion.reveal(reduceMotion: reduceMotion)) {
            scroll.scrollTo(Self.endID, anchor: .bottom)
        }
    }
}
