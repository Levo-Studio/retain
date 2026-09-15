import SwiftUI

// MARK: - Title bar

/// The strip the window's buttons sit in, with "Settings" under them.
///
/// The export draws the name here beside the lights, and beside them nothing
/// can be flush with anything: macOS owns the first seventy-odd points, so a
/// name starting after them sits adrift of a sidebar whose rows start at 22.
/// The bar keeps `titleBarTopRoom` clear above its row instead — the buttons
/// sit in that, and the name begins on the sidebar's own edge underneath
/// them. See `RetainTitleBar`, which is the same bar for the other windows.
struct SettingsTitleBar: View {

    /// The export paints three flat grey circles, which is what macOS draws
    /// for a window that is **not** frontmost. In a real window the system's
    /// own buttons sit in exactly that place and are the ones that work, so the
    /// strip reserves their width instead of drawing over them; the drawn
    /// circles are for previews and for the snapshot that is checked against
    /// the board.
    var drawsTrafficLights = true

    var body: some View {
        HStack(spacing: 0) {
            // Drawn only where there are no real buttons to draw over: a
            // preview, or the snapshot checked against the board.
            if drawsTrafficLights {
                RetainTrafficLightSpace(drawsButtons: true)
                    .padding(.trailing, RetainMetrics.titleBarGap)
            }

            RetainWindowMark()

            Text(verbatim: String(localized: "Settings", comment: "Settings window title, and the button that opens it"))
                .retainStyle(RetainTypography.titleBarSubtitle)
                .foregroundStyle(RetainPalette.inkDim)
                .padding(.leading, RetainMetrics.titleBarMarkGap)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, RetainMetrics.sidebarPadding.leading + RetainMetrics.sidebarRowSettings.leading)
        .padding(.trailing, RetainMetrics.titleBarPadding.trailing)
        .frame(height: RetainMetrics.titleBarHeight)
        // The same room above and below as every other window's bar. This one
        // is its own view because Settings draws the traffic lights itself when
        // it is hosted without them, so the values are taken rather than
        // inherited.
        .padding(.top, RetainMetrics.titleBarTopRoom)
        .padding(.bottom, RetainMetrics.titleBarBottomRoom)
        .background(RetainPalette.surfaceTitleBar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RetainPalette.lineDivider)
                .frame(height: RetainMetrics.borderWidth)
        }
    }
}

// MARK: - Sidebar

/// The 210-point list of sections.
struct SettingsSidebar: View {

    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.sidebarRowGap) {
            ForEach(SettingsSection.allCases) { section in
                row(section)
            }
            Spacer(minLength: 0)
        }
        .padding(RetainMetrics.sidebarPadding)
        .frame(width: RetainMetrics.settingsSidebarWidth, alignment: .leading)
        .background(RetainPalette.surfaceRail)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(RetainPalette.lineDivider)
                .frame(width: RetainMetrics.borderWidth)
        }
    }

    private func row(_ section: SettingsSection) -> some View {
        let isSelected = section == selection
        return Button {
            selection = section
        } label: {
            Text(section.title)
                .retainStyle(RetainTypography.sidebarRow)
                .foregroundStyle(isSelected ? RetainPalette.inkPrimary : RetainPalette.inkBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(RetainMetrics.sidebarRowSettings)
                .background(
                    isSelected ? RetainPalette.surfaceSelectedRow : .clear,
                    in: RoundedRectangle(cornerRadius: RetainMetrics.radiusSidebarRow)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - A section

/// The heading and the sentence under it.
struct SettingsSectionHeader: View {

    let title: String

    /// The sections that have one. The microphone section on board 06 does not.
    var description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .retainStyle(RetainTypography.settingsSectionHeading)
                .foregroundStyle(RetainPalette.inkPrimary)

            if let description {
                Text(description)
                    .retainStyle(RetainTypography.settingsDescription)
                    .foregroundStyle(RetainPalette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        maxWidth: RetainTypography.chWidth(of: RetainTypography.settingsDescription)
                            * RetainMetrics.settingsDescriptionWidth,
                        alignment: .leading
                    )
                    .padding(.top, RetainMetrics.settingsHeadingDescriptionGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One block of the settings document: a heading, whatever it contains, and the
/// rule that separates it from the section above.
struct SettingsPaneSection<Content: View>: View {

    let section: SettingsSection
    let title: String
    var description: String?

    /// The first section in the document has nothing above it to be separated
    /// from.
    var isFirst = false

    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                Rectangle()
                    .fill(RetainPalette.lineDivider)
                    .frame(height: RetainMetrics.borderWidth)
                    .padding(.bottom, RetainMetrics.settingsSectionRuleGap)
            }

            SettingsSectionHeader(title: title, description: description)

            content()
                .padding(.top, description == nil
                         ? RetainMetrics.settingsFormGapAfterHeading
                         : RetainMetrics.settingsFormGapAfterDescription)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(section)
    }
}

// MARK: - The form

/// The two-column settings form: a 160-point label column, the value beside it.
struct SettingsForm<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        Grid(
            alignment: .leading,
            horizontalSpacing: RetainMetrics.settingsForm.columnGap,
            verticalSpacing: RetainMetrics.settingsForm.rowGap
        ) {
            content()
        }
        .frame(maxWidth: RetainMetrics.settingsForm.maxWidth, alignment: .leading)
    }
}

/// The left-hand cell of a form row.
struct SettingsFieldLabel: View {

    let text: String

    /// The word set in label ink after the label itself — "API key *optional*".
    var note: String?

    var body: some View {
        label
            .retainStyle(RetainTypography.fieldLabelSettings)
            .foregroundStyle(RetainPalette.inkBody)
            .frame(width: RetainMetrics.settingsForm.labelColumn, alignment: .leading)
    }

    private var label: Text {
        guard let note else { return Text(text) }
        return Text(text) + Text(verbatim: " ") + Text(note).foregroundStyle(RetainPalette.inkLabel)
    }
}

/// A row whose value is not a control: the status line under the model picker,
/// the permission state.
struct SettingsStatusLine: View {

    let text: String
    let colour: Color
    var inkColour: Color?

    var body: some View {
        HStack(spacing: RetainMetrics.settingsStatusRowGap) {
            RetainStatusDot(colour: colour)
            Text(text)
                .retainStyle(RetainTypography.captionLarge)
                .foregroundStyle(inkColour ?? colour)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
