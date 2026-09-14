import SwiftUI

// MARK: - The pane

/// The left half of board 01: note blocks as they are written, and the
/// annotation composer along the bottom.
struct NotesPane: View {

    let shell: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                NotesList(notes: shell.session.notes, markers: shell.session.markers)
            }
            .scrollBounceBehavior(.basedOnSize)

            AnnotationComposer(shell: shell)
                .padding(RetainMetrics.annotationBarRecordingMargin)
        }
    }
}

// MARK: - The blocks themselves

/// The note blocks and the annotations between them.
///
/// Its own view rather than the body of the scroll view, so that what the notes
/// pane draws can be laid out and looked at without a scroll view around it —
/// which is the only way to compare it against board 01 without recording a
/// lecture first.
struct NotesList: View {

    let notes: [NoteBlock]
    let markers: [RecordingMarker]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(notes) { block in
                NoteBlockView(
                    block: block,
                    markers: NoteBlockLayout.markers(of: block, in: markers)
                )
                .padding(.top, block.number == 1 ? 0 : RetainMetrics.noteBlockGapRecording)
            }

            // Everything the user marked that no block covers yet. With no
            // summariser configured that is all of them, and it is the
            // difference between a pane that shows the user's own notes and a
            // pane that is empty for an hour.
            ForEach(NoteBlockLayout.loose(markers, blocks: notes)) { marker in
                AnnotationCard(marker: marker)
                    .padding(.top, RetainMetrics.noteAnnotationGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RetainMetrics.notesPaneRecording)
    }
}

// MARK: - One block

/// A numbered card: the number, the heading, the Markdown under it, and any
/// annotation that fell inside it.
struct NoteBlockView: View {

    let block: NoteBlock
    let markers: [RecordingMarker]

    private var isBeingWritten: Bool { block.state != .written }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: RetainMetrics.noteHeadingNumberGap) {
                Text(verbatim: NoteBlockLayout.number(block.number))
                    .retainStyle(RetainTypography.noteBlockNumber)
                    .foregroundStyle(isBeingWritten ? RetainPalette.inkDisabled : RetainPalette.inkFaintest)

                Text(verbatim: block.heading ?? "")
                    .retainStyle(RetainTypography.noteHeading)
                    .foregroundStyle(isBeingWritten ? RetainPalette.inkDim : RetainPalette.inkPrimary)

                if isBeingWritten {
                    Text(verbatim: String(localized: "writing …", comment: "Shown beside the heading of a note block the model has not finished"))
                        .retainStyle(RetainTypography.writingLabel)
                        .foregroundStyle(RetainPalette.inkLabel)
                }
            }

            let body = NoteBlockLayout.body(of: block.markdown)
            if !body.isEmpty {
                RetainMarkdownView(
                    markdown: body,
                    layout: .recording,
                    isBeingWritten: isBeingWritten,
                    showsTrailingCaret: isBeingWritten
                )
                .padding(.top, RetainMetrics.noteParagraphGapRecording)
                .padding(.leading, RetainMetrics.noteBodyIndentRecording)
            }

            ForEach(markers) { marker in
                AnnotationCard(marker: marker)
                    .padding(.top, RetainMetrics.noteAnnotationGap)
                    .padding(.leading, RetainMetrics.noteBodyIndentRecording)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - One annotation

/// "You · 00:46:41" with a blue rule down its left — what `⌘⇧M` leaves in the
/// notes.
struct AnnotationCard: View {

    let marker: RecordingMarker

    var body: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.noteAnnotationLabelGap) {
            Text(verbatim: AnnotationCard.label(at: marker.time))
                .retainStyle(RetainTypography.uppercaseLabel)
                .foregroundStyle(RetainPalette.blue)

            Text(verbatim: marker.text)
                .retainStyle(RetainTypography.annotationBody)
                .foregroundStyle(RetainPalette.inkBodyStrong)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, RetainMetrics.leftRuleGapMain)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(RetainPalette.blue)
                .frame(width: RetainMetrics.leftRuleWidth)
        }
        .frame(maxWidth: NoteBlockLayout.paragraphWidth, alignment: .leading)
    }

    /// "You · 00:46:41", assembled from the catalog key and the elapsed time.
    static func label(at time: TimeInterval) -> String {
        String(
            localized: "You · \(ElapsedTime.clock(time))",
            comment: "Label above an annotation the user typed during the lecture, with the moment they typed it"
        )
    }
}

// MARK: - The composer

/// `⌘⇧M`. Not a bare marker: what is typed goes to the model with the block it
/// falls in, and comes back out in the notes.
struct AnnotationComposer: View {

    let shell: ShellModel

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: RetainMetrics.annotationBarGap) {
            Rectangle()
                .fill(RetainPalette.blue)
                .frame(
                    width: RetainMetrics.annotationRuleRecording.width,
                    height: RetainMetrics.annotationRuleRecording.height
                )

            TextField(
                "",
                text: $text,
                prompt: Text(verbatim: RetainAnnotationCopy.placeholder)
                    .foregroundStyle(RetainPalette.inkLabel)
            )
            .textFieldStyle(.plain)
            .focused($isFocused)
            .retainStyle(RetainTypography.metaValue)
            .foregroundStyle(RetainPalette.inkBodyStrong)
            .onSubmit(send)

            Text(verbatim: AnnotationComposer.chip(markers: shell.session.markers.count))
                .retainStyle(RetainTypography.titleBarStatus)
                .foregroundStyle(RetainPalette.inkLabel)
                .padding(RetainMetrics.annotationChipPadding)
                .background(
                    RetainPalette.surfaceHotkeyChip,
                    in: RoundedRectangle(cornerRadius: RetainMetrics.radiusHotkeyChip)
                )
        }
        .retainFieldChrome(
            isFocused: isFocused,
            cornerRadius: RetainMetrics.radiusAnnotationBarRecording,
            padding: RetainMetrics.annotationBarRecordingPadding
        )
        .onChange(of: shell.annotationFocusRequests) { _, _ in
            isFocused = true
        }
    }

    private func send() {
        shell.annotate(text)
        text = ""
    }

    /// "⌘⇧M · 2 markers". The shortcut is written as the export writes it, and
    /// the count beside it is how many the lecture has so far.
    static func chip(markers: Int) -> String {
        String(
            localized: "⌘⇧M · \(markers) markers",
            comment: "The chip inside the annotation composer, with the shortcut and how many markers there are"
        )
    }
}

// MARK: - Laying a block out

/// The small decisions about how a note block is arranged, kept out of the
/// views so they can be tested.
nonisolated enum NoteBlockLayout {

    /// Zero padded to two digits, as the export draws it.
    static func number(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    /// The block's Markdown without its heading, which the view draws itself so
    /// that the number can sit beside it.
    static func body(of markdown: String) -> String {
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            lines.removeFirst()
        }
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The markers that fall inside a block, which is where the export draws
    /// them — inside the card, under the paragraph.
    static func markers(of block: NoteBlock, in markers: [RecordingMarker]) -> [RecordingMarker] {
        markers.filter { $0.hasText && $0.time >= block.start && $0.time <= block.end }
    }

    /// Markers no block covers yet, which is every marker made since the last
    /// block closed.
    static func loose(_ markers: [RecordingMarker], blocks: [NoteBlock]) -> [RecordingMarker] {
        markers.filter { marker in
            marker.hasText && !blocks.contains { marker.time >= $0.start && marker.time <= $0.end }
        }
    }

    /// `64ch` at the recording screen's paragraph style — the measure an
    /// annotation shares with the prose above it.
    static var paragraphWidth: CGFloat {
        RetainTypography.chWidth(of: RetainTypography.noteParagraphRecording)
            * RetainMetrics.noteParagraphWidthRecording
    }
}
