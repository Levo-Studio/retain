import SwiftUI

// MARK: - The pane

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
        // **Inset from the window.** The board draws this bar inside a notes
        // column that had its own padding; the column is gone and the bar was
        // left flush against three edges of the window, its rounded corners
        // running into the frame.
        .padding(RetainMetrics.annotationBarInset)
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


// MARK: -

nonisolated enum RecordingNotesCopy {

    /// Beside a block whose request already failed. Amber, not red: nothing is
    /// lost — the block is queued and goes out again as soon as the model
    /// answers. See `LectureSession.retryDeferredBlocks`.
    static var waitingForModel: String {
        String(localized: "waiting for the model",
               comment: "Shown beside a note block whose summary could not be fetched and is queued")
    }
}

// MARK: -

/// The annotation composer's placeholder.
///
/// It lived with the popover's cards, which is where the composer first
/// appeared. The popover is gone with the menu bar item; the recording window's
/// own composer is the only one left, so the wording moved to where it is used.
nonisolated enum RetainAnnotationCopy {

    static var placeholder: String {
        String(
            localized: "Note — goes to the model",
            comment: "Placeholder of the annotation composer, which sends what is typed to the language model"
        )
    }
}
