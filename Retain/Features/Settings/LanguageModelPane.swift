import SwiftUI

/// The Language-model section — the one board 06 draws in full.
///
/// Base URL, an optional API key, a model out of the server's own list, a
/// button that asks whether anybody is listening, and a line with a dot saying
/// what came back.
struct LanguageModelPane: View {

    @Bindable var model: SettingsModel

    var body: some View {
        SettingsPaneSection(
            section: .languageModel,
            title: String(localized: "Local language model", comment: "Settings section heading"),
            description: String(
                localized: "Summaries run on a model on this Mac. Nothing leaves the device.",
                comment: "Settings section description under the language model heading"
            )
        ) {
            SettingsForm {
                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Base URL", comment: "Settings field label for the LM Studio address")
                    )
                    addressField
                }

                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "API key", comment: "Settings field label for the optional API key"),
                        note: String(localized: "optional", comment: "Note beside the API key field label")
                    )
                    apiKeyField
                }

                GridRow {
                    SettingsFieldLabel(
                        text: String(localized: "Model", comment: "Settings field label for the model picker")
                    )
                    modelRow
                }

                if let message = model.connection.message {
                    GridRow {
                        Color.clear.frame(width: RetainMetrics.settingsForm.labelColumn, height: 0)
                        SettingsStatusLine(
                            text: message,
                            colour: dotColour,
                            inkColour: inkColour
                        )
                    }
                }
            }
        }
        .task {
            // The Keychain is read here and not at launch — a read from a build
            // the stored item does not recognise raises a system password
            // sheet, and during launch that lands in front of an app that has
            // not finished starting.
            model.loadAPIKey()
            await model.refreshModels()
        }
        .onDisappear { model.commitAPIKey() }
    }

    // MARK: - Rows

    /// The field plus, when the address is one Retain refuses to open, the
    /// reason under it.
    ///
    /// The reason is not drawn anywhere: the export shows only a working
    /// `http://localhost:1234/v1`. It is here because hard rule 9 means an
    /// address that is not this Mac is refused rather than attempted, and a
    /// refusal with no explanation is a field that silently does nothing.
    private var addressField: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.settingsHeadingDescriptionGap) {
            RetainTextField(
                placeholder: BaseAddress.default,
                text: $model.address
            )
            if let rejection = model.addressRejection {
                Text(rejection)
                    .retainStyle(RetainTypography.captionSmall)
                    .foregroundStyle(RetainPalette.redInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The key field plus, when the Keychain refused the item, the reason
    /// under it.
    ///
    /// The field writes through to the Keychain as it is typed — see
    /// `SettingsModel.apiKeyDraft` — so nothing here commits anything; Return
    /// and losing focus only retry a write that failed.
    ///
    /// The reason is not drawn in the export, which has no failure state for
    /// this row. It is here because the alternative is what Retain used to do:
    /// swallow the error and report the key as stored while every request went
    /// out without it.
    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.settingsHeadingDescriptionGap) {
            RetainTextField(
                placeholder: model.apiKeyPlaceholder,
                text: $model.apiKeyDraft,
                isSecure: true,
                onSubmit: model.commitAPIKey,
                onFocusLost: model.commitAPIKey
            )
            if let problem = model.apiKeyProblem {
                Text(problem)
                    .retainStyle(RetainTypography.captionSmall)
                    .foregroundStyle(RetainPalette.redInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modelRow: some View {
        HStack(spacing: RetainMetrics.settingsModelRowGap) {
            RetainPickerField(
                selection: $model.selectedModel,
                options: model.availableModels.map(\.id),
                title: { $0 }
            ) {
                Text(ModelPicker.label(selected: model.selectedModel, available: model.availableModels))
                    .retainStyle(RetainTypography.fieldText)
                    .foregroundStyle(
                        ModelPicker.isPlaceholder(selected: model.selectedModel, available: model.availableModels)
                            ? RetainPalette.inkLabel
                            : RetainPalette.inkPrimary
                    )
                    .lineLimit(1)
            }
            .disabled(!ModelPicker.isEnabled(available: model.availableModels))
            .opacity(ModelPicker.isEnabled(available: model.availableModels)
                     ? 1 : RetainInteraction.disabledOpacity)

            Button {
                Task { await model.testConnection() }
            } label: {
                Text("Test connection", comment: "Settings button that checks the LM Studio connection")
            }
            .buttonStyle(
                RetainSecondaryButtonStyle(
                    textStyle: RetainTypography.fieldLabelSettings,
                    padding: RetainMetrics.settingsInlineButtonPadding,
                    cornerRadius: RetainMetrics.radiusTextField,
                    isFilled: true
                )
            )
            .disabled(model.isTesting || model.addressRejection != nil)
            .fixedSize()
        }
    }

    // MARK: - The dot

    private var dotColour: Color {
        switch model.connection {
        case .connected: RetainPalette.accent
        case .failed: RetainPalette.redError
        // Not drawn: the export has no "testing" state. Amber is the hue the
        // export already uses for work in progress — the status dot while a
        // recording is being summarised.
        case .testing: RetainPalette.amber
        case .untested: RetainPalette.inkLabel
        }
    }

    private var inkColour: Color? {
        switch model.connection {
        case .connected: nil
        case .failed: RetainPalette.redInk
        default: RetainPalette.inkBody
        }
    }
}
