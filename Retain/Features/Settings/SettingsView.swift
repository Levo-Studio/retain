import SwiftUI

/// Which dialog the settings window has open over it.
nonisolated enum SettingsSheet: Identifiable, Equatable, Sendable {

    case nameTerm(Term?)
    case newCourse(Int64?)

    var id: String {
        switch self {
        case .nameTerm(let term): "term-\(term?.id ?? 0)"
        case .newCourse(let termID): "course-\(termID ?? 0)"
        }
    }
}

// MARK: -

/// Board 06, whole: the title bar, the 210-point sidebar and the pane.
///
/// The pane is **one document**, not five. That is what the board draws — the
/// Language-model row is selected in the sidebar and three section headings are
/// stacked under each other in the pane, separated by a rule — so the sidebar
/// is a jump list over a scrolling column rather than a switch between five
/// screens. Sections read in sidebar order, and every one after the first
/// carries the rule above it.
struct SettingsView: View {

    @Bindable var model: SettingsModel

    /// `false` inside a real window, where macOS draws the buttons itself.
    var drawsTrafficLights = true

    @State private var sheet: SettingsSheet?

    var body: some View {
        VStack(spacing: 0) {
            SettingsTitleBar(
                title: String(localized: "Settings", comment: "Settings window title, and the button that opens it"),
                drawsTrafficLights: drawsTrafficLights
            )

            HStack(spacing: 0) {
                SettingsSidebar(selection: $model.section)
                pane
            }
        }
        .frame(
            width: RetainMetrics.detailWindowSize.width,
            height: RetainMetrics.detailWindowSize.height
        )
        .background(RetainPalette.surfaceWindow)
        .sheet(item: $sheet) { sheet in
            dialog(for: sheet)
        }
    }

    // MARK: - The pane

    private var pane: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: RetainMetrics.settingsSectionGap) {
                    GeneralPane(model: model, sheet: $sheet)
                    LanguageModelPane(model: model)
                    SpeechRecognitionPane(model: model)
                    MicrophonePane(model: model)
                    ShortcutsPane()
                }
                .padding(RetainMetrics.settingsPane)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: model.section) { _, section in
                withAnimation(RetainMotion.resolve(.easeInOut(duration: scrollDuration), reduceMotion: reduceMotion)) {
                    scroll.scrollTo(section, anchor: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RetainPalette.surfaceWindow)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The export gives no duration for this, because it draws no scroll. It
    /// sits at the short end of the range the four drawn loops use.
    private var scrollDuration: Double { RetainMotion.sweep.duration / 4 }

    // MARK: - Dialogs

    @ViewBuilder
    private func dialog(for sheet: SettingsSheet) -> some View {
        switch sheet {
        case .nameTerm(let term):
            NameTermDialog(
                terms: model.terms,
                draft: term.map(TermDraft.init) ?? TermDraft(startsOn: .now, endsOn: .now),
                save: { draft in
                    self.sheet = nil
                    Task { await save(draft) }
                },
                cancel: { self.sheet = nil }
            )

        case .newCourse(let termID):
            NewCourseDialog(
                terms: model.terms,
                draft: CourseDraft(termID: termID ?? model.selectedTermID),
                create: { draft in
                    self.sheet = nil
                    Task { await create(draft) }
                },
                cancel: { self.sheet = nil }
            )
        }
    }

    /// Saving a term is two statements, never one.
    ///
    /// The row is written with `isCurrent` cleared and the flag is then set
    /// through `makeCurrent(_:)`, which clears the old one and sets the new one
    /// inside a single transaction. Writing `isCurrent = true` directly would
    /// hit the partial unique index and fail — which is the database doing its
    /// job, and not something to work around by dropping the index.
    private func save(_ draft: TermDraft) async {
        guard let library = model.library else { return }
        guard let saved = try? await library.save(draft.term()), let id = saved.id else { return }
        if draft.isCurrent {
            try? await library.makeCurrent(id)
        }
        await model.loadLibrary()
    }

    private func create(_ draft: CourseDraft) async {
        guard let library = model.library, let course = draft.course() else { return }
        _ = try? await library.save(course)
        await model.loadCourses()
    }
}
