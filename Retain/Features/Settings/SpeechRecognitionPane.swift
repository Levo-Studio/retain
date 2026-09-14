import SwiftUI

/// The Speech-recognition section: the one-time model download, as a card.
struct SpeechRecognitionPane: View {

    @Bindable var model: SettingsModel

    /// Rebuilt from the download's own progress reports rather than a timer, so
    /// the estimate is a measurement and not a countdown.
    @State private var estimate = DownloadEstimate()
    @State private var remaining: TimeInterval?

    var body: some View {
        SettingsPaneSection(
            section: .speechRecognition,
            title: String(localized: "Speech recognition", comment: "Settings section heading and sidebar row"),
            description: String(
                localized: "Runs on the Neural Engine. The model is downloaded once and used offline after that.",
                comment: "Settings section description under the speech recognition heading"
            )
        ) {
            card
                .frame(maxWidth: RetainMetrics.settingsForm.maxWidth, alignment: .leading)
        }
        .onChange(of: fraction) { _, new in
            guard let new else { return }
            let now = Date()
            estimate = estimate.observing(new, at: now)
            remaining = estimate.remaining(at: new, now: now)
        }
    }

    // MARK: -

    private var state: SpeechModels.State { model.speechModels?.state ?? .notLoaded }

    private var fraction: Double? {
        if case .downloading(let value) = state { return value }
        return nil
    }

    private var card: some View {
        let content = SpeechDownloadCard.make(for: state, remaining: remaining)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(content.title)
                    .retainStyle(RetainTypography.settingsCardTitle)
                    .foregroundStyle(RetainPalette.inkPrimary)

                Spacer(minLength: RetainMetrics.settingsModelRowGap)

                if let value = content.value {
                    Text(value)
                        .retainStyle(RetainTypography.settingsCardValue)
                        .foregroundStyle(RetainPalette.inkBody)
                }
            }

            if let fraction = content.fraction {
                RetainProgressTrack(fraction: fraction)
                    .padding(.top, RetainMetrics.settingsCardProgressGap)
            }

            HStack(spacing: RetainMetrics.settingsModelRowGap) {
                Text(content.caption)
                    .retainStyle(RetainTypography.settingsCardCaption)
                    .foregroundStyle(RetainPalette.inkLabel)
                    .fixedSize(horizontal: false, vertical: true)

                if let action = content.action {
                    Button {
                        Task { await model.speechModels?.prepare() }
                    } label: {
                        Text(title(for: action))
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

                Spacer(minLength: 0)
            }
            .padding(.top, RetainMetrics.settingsCardCaptionGap)
        }
        .padding(RetainMetrics.settingsDownloadCardPadding)
        .background(
            RetainPalette.surfaceInsetControl,
            in: RoundedRectangle(cornerRadius: RetainMetrics.radiusDownloadCard)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RetainMetrics.radiusDownloadCard)
                .strokeBorder(RetainPalette.lineControlBorder, lineWidth: RetainMetrics.borderWidth)
        }
    }

    private func title(for action: SpeechDownloadCard.Action) -> String {
        switch action {
        case .download:
            String(localized: "Download", comment: "Button that starts the one-time speech model download")
        case .retry:
            // The same word the "No connection" dialog uses.
            String(localized: "Try again", comment: "Button that retries the speech model download or the LM Studio connection")
        }
    }
}
