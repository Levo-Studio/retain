import SwiftUI

/// The Microphone section: which input, how loud it is, and whether Retain is
/// allowed to open it at all.
struct MicrophonePane: View {

    @Bindable var model: SettingsModel

    var body: some View {
        SettingsPaneSection(
            section: .microphone,
            // The export gives this section a heading and no description.
            title: String(localized: "Microphone", comment: "Settings section heading and sidebar row, and the label above the permission dialog title")
        ) {
            SettingsForm {
                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Input", comment: "Settings field label for the microphone picker")
                    )
                    inputPicker
                }

                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Level", comment: "Settings field label for the microphone level meter")
                    )
                    levelRow
                }

                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Permission", comment: "Settings field label for the microphone permission")
                    )
                    permissionRow
                }
            }
        }
        .onAppear { model.refreshAuthorization() }
    }

    // MARK: - Input

    /// `nil` is a real choice, not the absence of one: it means "follow
    /// whatever macOS is using", which is what somebody who plugs in a headset
    /// mid-lecture expects to happen.
    private var inputPicker: some View {
        RetainPickerField(
            selection: Binding(
                get: { model.preferredInputUID ?? "" },
                set: { model.preferredInputUID = $0.isEmpty ? nil : $0 }
            ),
            options: [""] + model.inputDevices.map(\.uid),
            title: deviceName
        ) {
            Text(deviceName(model.preferredInputUID ?? ""))
                .retainStyle(RetainTypography.fieldText)
                .foregroundStyle(RetainPalette.inkPrimary)
                .lineLimit(1)
        }
        .disabled(model.inputDevices.isEmpty)
        .opacity(model.inputDevices.isEmpty ? RetainInteraction.disabledOpacity : 1)
    }

    private func deviceName(_ uid: String) -> String {
        guard !uid.isEmpty else {
            return model.inputDevices.isEmpty
                ? MicrophoneReadout.noInputDevices
                : MicrophoneReadout.systemDefaultInput
        }
        return model.inputDevices.first { $0.uid == uid }?.name ?? MicrophoneReadout.systemDefaultInput
    }

    // MARK: - Level

    private var levelRow: some View {
        HStack(spacing: RetainMetrics.settingsLevelRowGap) {
            RetainProgressTrack(fraction: Double(model.level.barFraction))
            Text(MicrophoneReadout.decibels(model.level))
                .retainStyle(RetainTypography.levelReadout)
                .foregroundStyle(RetainPalette.inkLabel)
        }
    }

    // MARK: - Permission

    private var permissionRow: some View {
        HStack(spacing: RetainMetrics.settingsModelRowGap) {
            SettingsStatusLine(
                text: MicrophoneReadout.permission(model.authorization),
                colour: dotColour,
                inkColour: RetainPalette.inkBody
            )

            if let remedy = MicrophoneReadout.remedy(model.authorization) {
                Button {
                    switch remedy {
                    case .ask: Task { await model.requestMicrophoneAccess() }
                    case .openSystemSettings: MicrophoneAccess.openSystemSettings()
                    }
                } label: {
                    Text(MicrophoneReadout.remedyTitle(remedy))
                }
                .buttonStyle(
                    RetainSecondaryButtonStyle(
                        textStyle: RetainTypography.fieldLabelSettings,
                        padding: RetainMetrics.settingsInlineButtonPadding,
                        cornerRadius: RetainMetrics.radiusTextField,
                        isFilled: true
                    )
                )
                .fixedSize()
            }
        }
    }

    /// Granted is the accent, as drawn. The other two are not drawn: a refusal
    /// takes the error red the "No connection" dialog uses, and a permission
    /// that has not been asked for takes the amber the export uses for work
    /// that has not finished.
    private var dotColour: Color {
        switch model.authorization {
        case .granted: RetainPalette.accent
        case .denied: RetainPalette.redError
        case .undetermined: RetainPalette.amber
        }
    }
}
