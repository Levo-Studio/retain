import SwiftUI

/// The recordings of the selected course.
///
/// Four columns, not five. The export's first column is `Nr.` — a lesson number
/// — and there is no lesson and no number: a recording is identified by when it
/// started, so the topic leads and the date carries the time of day beside it.
struct RecordingTable: View {

    let model: LibraryModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            courseHeading

            VStack(spacing: 0) {
                header

                if model.recordings.isEmpty {
                    Text(verbatim: LibraryCopy.noRecordings)
                        .retainStyle(RetainTypography.tableCellOther)
                        .foregroundStyle(RetainPalette.inkLabel)
                        .padding(RetainMetrics.tableRow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.recordings.enumerated()), id: \.element.id) { index, recording in
                                RecordingTableRow(
                                    recording: recording,
                                    isLast: index == model.recordings.count - 1,
                                    isSelecting: model.isSelecting,
                                    isSelected: model.isSelected(recording)
                                ) {
                                    // While several are being picked, a row is
                                    // a tick rather than a door. Opening one
                                    // would leave the selection behind in a
                                    // window nobody is looking at.
                                    if model.isSelecting {
                                        withAnimation(RetainMotion.selection(reduceMotion: reduceMotion)) {
                                            model.toggle(recording)
                                        }
                                    } else {
                                        model.open(recording)
                                    }
                                }
                                // Right-click rather than a button in the row:
                                // board 05 draws the table as four columns of
                                // text with no control in them, and the course
                                // rows in the sidebar beside it already carry
                                // their action the same way.
                                .contextMenu {
                                    Button(LibraryCopy.deleteRecording) {
                                        Task { await model.confirmDeletion(of: recording) }
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }

                Spacer(minLength: 0)
            }
            .padding(RetainMetrics.libraryBody)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var courseHeading: some View {
        HStack(alignment: .firstTextBaseline, spacing: RetainMetrics.libraryCourseHeadingGap) {
            Text(verbatim: model.selectedCourse?.course.name ?? "")
                .retainStyle(RetainTypography.libraryCourseHeading)
                .foregroundStyle(RetainPalette.inkPrimary)

            Text(verbatim: model.courseSubtitle)
                .retainStyle(RetainTypography.libraryCourseSubtitle)
                .foregroundStyle(RetainPalette.inkLabel)
        }
        .padding(RetainMetrics.libraryCourseHeading)
    }

    private var header: some View {
        RecordingTableColumns {
            Text(verbatim: LibraryCopy.topicColumn)
            Text(verbatim: LibraryCopy.startedColumn)
            Text(verbatim: LibraryCopy.durationColumn)
            Text(verbatim: LibraryCopy.statusColumn)
        }
        .retainStyle(RetainTypography.uppercaseLabel)
        .foregroundStyle(RetainPalette.inkLabel)
        .padding(RetainMetrics.tableHeaderRow)
        .overlay(alignment: .bottom) { RetainDivider() }
    }
}

// MARK: - One recording

struct RecordingTableRow: View {

    let recording: Recording
    let isLast: Bool

    /// Whether the table is picking several at once.
    var isSelecting = false
    var isSelected = false

    let open: () -> Void

    var body: some View {
        Button(action: open) {
            RecordingTableColumns {
                HStack(spacing: 0) {
                    // Width rather than presence, so the title slides over and
                    // the tick grows into the space instead of the row being
                    // re-laid out around a view that appeared.
                    tick
                        .frame(width: isSelecting ? RetainMetrics.selectionTickSize : 0)
                        .padding(.trailing, isSelecting ? RetainMetrics.selectionTickGap : 0)
                        .clipped()

                    Text(verbatim: RecordingPresentation.title(of: recording))
                        .retainStyle(RetainTypography.tableCellTitle)
                        .foregroundStyle(titleInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: RecordingPresentation.started(of: recording))
                    .retainStyle(RetainTypography.tableCellOther)
                    .foregroundStyle(RetainPalette.inkBody)
                    .lineLimit(1)

                Text(verbatim: RecordingPresentation.duration(of: recording))
                    .retainStyle(RetainTypography.tableCellOther)
                    .foregroundStyle(RetainPalette.inkBody)

                Text(verbatim: RecordingPresentation.state(of: recording))
                    .retainStyle(RetainTypography.tableStatus)
                    .foregroundStyle(isRunning ? RetainPalette.redInk : RetainPalette.inkLabel)
            }
            .padding(RetainMetrics.tableRow)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast { Rectangle().fill(RetainPalette.lineTableRowSeparator).frame(height: RetainMetrics.borderWidth) }
            }
        }
        .buttonStyle(
            RetainSurfaceButtonStyle(
                // The running recording is the row the export picks out with
                // the meta-strip colour behind it.
                resting: isRunning ? RetainPalette.metaStripSwatch : nil
            )
        )
    }

    /// An empty box until the row is ticked.
    ///
    /// A box and not only a mark: with nothing drawn, a row that is not ticked
    /// and a table that is not selecting look the same, and the reader has
    /// nowhere to aim.
    private var tick: some View {
        RoundedRectangle(cornerRadius: RetainMetrics.radiusCheckbox, style: .continuous)
            .fill(isSelected ? RetainPalette.accent : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: RetainMetrics.radiusCheckbox, style: .continuous)
                    .strokeBorder(
                        isSelected ? RetainPalette.accent : RetainPalette.lineControlBorderEmphasised,
                        lineWidth: RetainMetrics.borderWidth
                    )
            }
            .overlay {
                if isSelected {
                    Text(verbatim: RetainGlyph.tick)
                        .retainStyle(RetainTypography.captionSmall)
                        .foregroundStyle(RetainPalette.surfaceWindow)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    private var isRunning: Bool { RecordingPresentation.isRunning(recording) }

    /// The running row's title is drawn at full strength and every other at the
    /// slightly softer body ink, which is what makes the current one read as
    /// the one thing happening.
    private var titleInk: Color {
        isRunning ? RetainPalette.inkPrimary : RetainPalette.inkBodyStrong
    }
}

// MARK: - The grid

/// `1fr 120px 96px 84px`, gap 14 — the export's five columns with the lesson
/// number taken out of the front.
struct RecordingTableColumns<Content: View>: View {

    @ViewBuilder var content: Content

    static var columns: [CGFloat?] {
        [
            nil,
            RetainMetrics.libraryTableDateColumn,
            RetainMetrics.libraryTableDurationColumn,
            RetainMetrics.libraryTableStatusColumn,
        ]
    }

    var body: some View {
        RetainFixedColumns(columns: Self.columns, spacing: RetainMetrics.libraryTableGap) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
