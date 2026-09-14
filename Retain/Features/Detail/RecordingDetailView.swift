import SwiftUI

/// Boards 03 and 04: one recording, written out.
///
/// The chrome is the same on both — title bar, meta strip, two tabs, and a rail
/// 330 points wide down the right — and only the left column changes. That is
/// why they are one view: switching tabs is not a new screen, it is the same
/// window showing the notes or the words they were made from.
struct RecordingDetailView: View {

    @Bindable var model: RecordingDetailModel

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            DetailMetaStrip(model: model)
            tabBar

            HStack(spacing: 0) {
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                RetainDivider(axis: .vertical)

                RecordingRail(model: model)
                    .frame(width: RetainMetrics.chaptersRailWidth)
            }
            .frame(maxHeight: .infinity)
        }
        .background(RetainPalette.surfaceWindow)
        .task { await model.load() }
    }

    // MARK: - Chrome

    private var titleBar: some View {
        RetainTitleBar(title: DetailCopy.joined(courseName, started)) {
            Button {
                NotesExport.run(markdown: model.notes.markdown, recording: model.recording, course: courseName)
            } label: {
                Text(verbatim: DetailCopy.export)
            }
            // The outlined button on the inset fill, which is the same control
            // the settings and dialog boards draw.
            .buttonStyle(
                RetainSecondaryButtonStyle(
                    textStyle: RetainTypography.titleBarButton,
                    padding: RetainMetrics.titleBarButtonPadding,
                    cornerRadius: RetainMetrics.radiusExportButton,
                    isFilled: true
                )
            )
            .disabled(model.blocks.isEmpty)
        }
    }

    private var tabBar: some View {
        HStack(spacing: RetainMetrics.tabGap) {
            tab(.notes, title: DetailCopy.notesTab)
            tab(.transcript, title: DetailCopy.transcriptTab)
            Spacer(minLength: 0)
        }
        .padding(RetainMetrics.tabBarPadding)
        .background(RetainPalette.surfaceWindow)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    private func tab(_ which: RecordingDetailModel.Tab, title: String) -> some View {
        let isActive = model.tab == which

        return Button {
            model.tab = which
        } label: {
            Text(verbatim: title)
                .retainStyle(RetainTypography.tab)
                .foregroundStyle(isActive ? RetainPalette.inkPrimary : RetainPalette.inkLabel)
                .padding(RetainMetrics.tabPadding)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? RetainPalette.accent : .clear)
                        .frame(height: RetainMetrics.activeTabUnderlineHeight)
                }
        }
        .buttonStyle(RetainSurfaceButtonStyle())
    }

    // MARK: - The left column

    @ViewBuilder
    private var pane: some View {
        switch model.tab {
        case .notes: DetailNotesPane(model: model)
        case .transcript: TranscriptPane(model: model)
        }
    }

    // MARK: - Labels

    private var courseName: String { model.course?.name ?? "" }

    private var started: String {
        model.recording.startedAt.formatted(
            .dateTime.day().month(.wide).year().hour().minute()
        )
    }
}

// MARK: - The meta strip

/// The three cells under the title bar: what the recording is about, which
/// course it belongs to, and how long it ran.
struct DetailMetaStrip: View {

    let model: RecordingDetailModel

    var body: some View {
        RetainWeightedColumns(weights: RetainMetrics.metaStripColumnWeights) {
            cell(DetailCopy.topicLabel, value: topic, padding: RetainMetrics.metaStripCellFirst, rule: true)
            cell(DetailCopy.courseLabel, value: course, padding: RetainMetrics.metaStripCellOther, rule: true)
            cell(
                DetailCopy.durationLabel,
                value: duration,
                padding: RetainMetrics.metaStripCellOther,
                rule: false,
                ink: RetainPalette.inkBody
            )
        }
        .background(RetainPalette.surfaceMetaStrip)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    private func cell(
        _ label: String,
        value: String,
        padding: EdgeInsets,
        rule: Bool,
        ink: Color = RetainPalette.inkPrimary
    ) -> some View {
        VStack(alignment: .leading, spacing: RetainMetrics.metaValueGap) {
            Text(verbatim: label)
                .retainStyle(RetainTypography.uppercaseLabel)
                .foregroundStyle(RetainPalette.inkLabel)
            Text(verbatim: value)
                .retainStyle(RetainTypography.metaValue)
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .overlay(alignment: .trailing) {
            if rule { RetainDivider(axis: .vertical) }
        }
    }

    // MARK: Values

    /// A recording the model never got a topic out of shows when it happened
    /// instead — the same answer the library table gives, from the same place,
    /// so the two screens can never disagree about what a recording is called.
    private var topic: String {
        RecordingPresentation.title(of: model.recording)
    }

    private var course: String {
        guard let course = model.course else { return "" }
        guard let term = model.term else { return course.name }
        return DetailCopy.joined(course.name, term.title)
    }

    private var duration: String {
        DetailCopy.joined(
            DetailCopy.minutes(RetainTimeFormat.wholeMinutes(model.recording.duration)),
            DetailCopy.markers(model.markerCount)
        )
    }
}
