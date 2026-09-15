import SwiftUI

/// Which dialog the settings window has open over it.

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

    @State private var sheet: LibrarySheet?

    var body: some View {
        VStack(spacing: 0) {
            SettingsTitleBar(drawsTrafficLights: drawsTrafficLights)

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
        .libraryEditingSheet(
            $sheet,
            terms: model.terms,
            library: model.library,
            reload: { await model.loadLibrary() }
        )
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
}
