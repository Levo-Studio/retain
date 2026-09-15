import SwiftUI

/// Boards 03 and 04: one recording, written out.
///
/// The chrome is the same on both — title bar, meta strip, two tabs, and a rail
/// 330 points wide down the right — and only the left column changes. That is
/// why they are one view: switching tabs is not a new screen, it is the same
/// window showing the notes or the words they were made from.
struct RecordingDetailView: View {

    @Bindable var model: RecordingDetailModel

    /// The re-analysis confirmation. Held here rather than on the model: it is
    /// about this window being open, not about the recording.
    @State private var isConfirmingReanalysis = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        VStack(spacing: 0) {
            titleBar

            DetailMetaStrip(model: model)
            tabBar

            HStack(spacing: 0) {
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Folded by width rather than by removal. Taking the rail out
                // of the hierarchy would throw away its scroll position, its
                // search field and any answer in the chat, and bring them back
                // reset — and it would jump rather than move, because there is
                // nothing left to animate.
                if !model.isRailHidden {
                    RetainDivider(axis: .vertical)
                }

                RecordingRail(model: model)
                    .frame(width: model.isRailHidden ? 0 : RetainMetrics.chaptersRailWidth)
                    .opacity(model.isRailHidden ? 0 : 1)
                    .clipped()
                    .allowsHitTesting(!model.isRailHidden)
            }
            .frame(maxHeight: .infinity)
        }
        .background(RetainPalette.surfaceWindow)
        .task { await model.load() }
        // A second task, not a second call inside the first: `follow` never
        // returns while the window is open, and anything after it in the same
        // task would never run.
        .task { await model.follow() }
        .sheet(isPresented: $isConfirmingReanalysis) {
            ReanalyseDialog(
                impact: model.reanalysisImpact,
                confirm: {
                    isConfirmingReanalysis = false
                    Task { await model.reanalyse() }
                },
                cancel: { isConfirmingReanalysis = false }
            )
        }
    }

    // MARK: - Chrome

    private var titleBar: some View {
        // The name sits in the bar rather than on a line of its own under it.
        // That line was a whole row of window for one sentence, and the bar it
        // sat under was empty on the left — the owner asked for the two to be
        // one, with the name where it already was and the controls where they
        // already were.
        RetainTitleBar(
            title: DetailCopy.joined(courseName, started),
            bottomGap: RetainMetrics.titleBarBottomGap
        ) {
            // The chat and the notes both live off this model, and this window
            // is where a reader asks it questions. Whether it is going to
            // answer belongs where they are looking.
            ModelStatusPill()

            // Always here, beside Export. It used to exist only in the empty
            // notes column, which meant it vanished the moment it had worked
            // once — and a recording whose notes are wrong is exactly the one
            // somebody wants to run again.
            Button {
                isConfirmingReanalysis = true
            } label: {
                Text(verbatim: DetailCopy.reanalyse)
            }
            .buttonStyle(
                RetainSecondaryButtonStyle(
                    textStyle: RetainTypography.titleBarButton,
                    padding: RetainMetrics.titleBarButtonPadding,
                    cornerRadius: RetainMetrics.radiusExportButton,
                    isFilled: true
                )
            )
            .disabled(!model.canReanalyse)

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
            // Out past the tab bar's own inset, so it lines up with the Export
            // button in the bar above rather than sitting short of it. The
            // tabs keep the 34 the export draws them at; the padding is put on
            // the leading edge alone rather than on both.
            railToggle
                .padding(.trailing, RetainMetrics.titleBarPadding.trailing)
        }
        .padding(.leading, RetainMetrics.tabBarPadding.leading)
        .padding(.vertical, RetainMetrics.tabBarPadding.top)
        .background(RetainPalette.surfaceWindow)
        .overlay(alignment: .bottom) { RetainDivider() }
    }

    /// Folds the rail away, and brings it back.
    ///
    /// In the tab bar and not in the title bar because it belongs to the two
    /// tabs under it: the rail is beside both of them, and this is the one
    /// control that is about how they are laid out rather than about the
    /// recording.
    private var railToggle: some View {
        Button {
            withAnimation(RetainMotion.rail(reduceMotion: reduceMotion)) {
                model.isRailHidden.toggle()
            }
        } label: {
            Text(verbatim: model.isRailHidden ? RetainGlyph.unfoldRail : RetainGlyph.foldRail)
                .retainStyle(RetainTypography.tab)
                .foregroundStyle(RetainPalette.inkLabel)
                .padding(RetainMetrics.railTogglePadding)
                .accessibilityHidden(true)
        }
        .buttonStyle(RetainSurfaceButtonStyle(cornerRadius: RetainMetrics.radiusButton))
        .accessibilityLabel(DetailCopy.railToggle(isHidden: model.isRailHidden))
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
        // **No transition.** Both panes are already in memory — the notes, the
        // transcript and the highlights are read once when the window opens —
        // so a fade is a delay Retain is adding to something that is already
        // there. Motion belongs to work that is happening, not to content that
        // has arrived.
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
///
/// Two of the three are controls now. The topic and the course were the only
/// two facts in this window that the model had guessed and nobody could
/// correct — a lecture filed under the wrong course had to be deleted and
/// recorded again, and a topic the model got wrong was the recording's name in
/// the library for good.
struct DetailMetaStrip: View {

    @Bindable var model: RecordingDetailModel

    /// The course the picker was pointed at, waiting for the dialog. `nil`
    /// while nothing is being moved — the write happens on the dialog's
    /// confirmation and nowhere else.
    @State private var movingTo: Course?

    /// What is in the topic field while it is being edited. Separate from the
    /// recording on purpose: a keystroke is not a save, and abandoning an edit
    /// has to leave the stored name alone.
    @State private var draftTopic = ""
    @FocusState private var isEditingTopic: Bool

    var body: some View {
        RetainWeightedColumns(weights: RetainMetrics.metaStripColumnWeights) {
            cell(DetailCopy.topicLabel, padding: RetainMetrics.metaStripCellFirst, rule: true) {
                topicField
            }
            cell(DetailCopy.courseLabel, padding: RetainMetrics.metaStripCellOther, rule: true) {
                coursePicker
            }
            cell(DetailCopy.durationLabel, padding: RetainMetrics.metaStripCellOther, rule: false) {
                Text(verbatim: duration)
                    .retainStyle(RetainTypography.metaValue)
                    .foregroundStyle(RetainPalette.inkBody)
                    .lineLimit(1)
            }
        }
        .background(RetainPalette.surfaceMetaStrip)
        .overlay(alignment: .bottom) { RetainDivider() }
        .sheet(item: $movingTo) { course in
            MoveRecordingDialog(
                recording: model.recording,
                from: model.course,
                to: course,
                move: {
                    movingTo = nil
                    Task { await model.move(to: course) }
                },
                cancel: { movingTo = nil }
            )
        }
    }

    // MARK: - The topic

    /// Click it and type. There is no edit button and no pencil: the value is
    /// the field, drawn as the plain text it already was until the keyboard is
    /// in it.
    ///
    /// It saves on Return and on losing focus, because both are somebody
    /// finishing. Escape puts the stored name back — the draft is thrown away
    /// and never written, which is what makes clicking into it by accident
    /// harmless.
    private var topicField: some View {
        TextField(
            "",
            text: $draftTopic,
            prompt: Text(verbatim: RecordingPresentation.title(of: model.recording))
        )
        .textFieldStyle(.plain)
        .retainStyle(RetainTypography.metaValue)
        .foregroundStyle(RetainPalette.inkPrimary)
        .lineLimit(1)
        .focused($isEditingTopic)
        .accessibilityLabel(DetailCopy.renameRecording)
        .onSubmit { commitTopic() }
        .onExitCommand { cancelTopicEdit() }
        .onChange(of: isEditingTopic) { wasEditing, isEditing in
            if isEditing {
                draftTopic = model.recording.topic ?? ""
            } else if wasEditing {
                commitTopic()
            }
        }
        // The stored name wins whenever it changes underneath — a re-analysis
        // writes a new topic, and so does another window.
        .onChange(of: model.recording.topic) { _, stored in
            if !isEditingTopic { draftTopic = stored ?? "" }
        }
        .task { draftTopic = model.recording.topic ?? "" }
    }

    private func commitTopic() {
        let typed = draftTopic
        isEditingTopic = false
        Task { await model.rename(to: typed) }
    }

    private func cancelTopicEdit() {
        draftTopic = model.recording.topic ?? ""
        isEditingTopic = false
    }

    // MARK: - The course

    /// Retain's own dropdown, not an `NSMenu` — see `RetainPickerField`. It
    /// points at a course and the dialog does the moving, so a misclick in a
    /// list of courses that all start with the same two letters costs a Return
    /// rather than a lecture filed in the wrong place.
    private var coursePicker: some View {
        RetainPickerField(
            selection: Binding(
                get: { model.course },
                set: { picked in
                    guard let picked, picked.id != model.course?.id else { return }
                    movingTo = picked
                }
            ),
            options: model.coursesInTerm.map(Optional.some),
            title: { $0?.name ?? "" },
            cornerRadius: RetainMetrics.radiusButton,
            padding: RetainMetrics.metaPickerPadding
        ) {
            Text(verbatim: course)
                .retainStyle(RetainTypography.metaValue)
                .foregroundStyle(RetainPalette.inkPrimary)
                .lineLimit(1)
        }
        .accessibilityLabel(DetailCopy.changeCourse)
        // Nothing to pick from is nothing to open. A library with one course in
        // this term still draws the value; it just does not pretend there is a
        // choice behind it.
        .disabled(model.coursesInTerm.count < 2)
    }

    // MARK: - The cell

    private func cell<Value: View>(
        _ label: String,
        padding: EdgeInsets,
        rule: Bool,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: RetainMetrics.metaValueGap) {
            Text(verbatim: label)
                .retainStyle(RetainTypography.uppercaseLabel)
                .foregroundStyle(RetainPalette.inkLabel)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .overlay(alignment: .trailing) {
            if rule { RetainDivider(axis: .vertical) }
        }
    }

    // MARK: Values

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
