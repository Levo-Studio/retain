import Foundation

// MARK: - Estimating what is left

/// How long the one-time model download still has to run.
///
/// `SpeechModels` reports a fraction and nothing else — no byte counts, no
/// rate — so the estimate is made here, from how far the fraction has moved
/// since the download started. That is also why it is a value with a method
/// rather than a timer: given two samples it is arithmetic, and arithmetic can
/// be tested.
nonisolated struct DownloadEstimate: Equatable, Sendable {

    /// The first sample seen for the current download, which the rate is
    /// measured from. Re-seeded whenever the fraction goes backwards, because
    /// that means a second download started.
    private var startFraction: Double?
    private var startedAt: Date?

    init() {}

    /// Folds in a progress report.
    func observing(_ fraction: Double, at now: Date) -> DownloadEstimate {
        var updated = self
        if let start = startFraction, fraction >= start, startedAt != nil {
            return updated
        }
        updated.startFraction = fraction
        updated.startedAt = now
        return updated
    }

    /// Seconds still to go, or `nil` while there is not enough to say.
    ///
    /// `nil` rather than a guess: the caption then simply does not carry an
    /// estimate, which is better than one that says four hours for the first
    /// second of every download.
    func remaining(at fraction: Double, now: Date) -> TimeInterval? {
        guard let startFraction, let startedAt else { return nil }
        let progressed = fraction - startFraction
        guard progressed > 0, fraction < 1 else { return nil }

        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return nil }

        let rate = progressed / elapsed
        guard rate > 0 else { return nil }

        return (1 - fraction) / rate
    }
}

// MARK: - The card

/// Everything the speech-recognition card draws, worked out from
/// `SpeechModels.State`.
///
/// Board 06 draws exactly one of the four states — a download in flight, at
/// 69 %, with byte counts and a time estimate beside it. The other three are
/// states the app is in far more often than that one, and the export does not
/// draw them; what they say is noted below as invented.
struct SpeechDownloadCard: Equatable, Sendable {

    /// The model set being fetched. The export names one model,
    /// `parakeet-tdt-0.6b · Deutsch`; Retain fetches three sets at once —
    /// streaming, batch and voice activity — so the card names the set and the
    /// language rather than one file inside it.
    let title: String

    /// The right-hand side of the title row. Byte counts where they are known,
    /// a percentage where they are not — see `progressValue`.
    let value: String?

    /// 0…1, or `nil` where the card draws no bar.
    let fraction: Double?

    /// The line under the bar.
    let caption: String

    /// Which button, if any, the card offers.
    let action: Action?

    enum Action: Equatable, Sendable {
        case download
        case retry
    }

    // MARK: - From the state

    static func make(
        for state: SpeechModels.State,
        remaining: TimeInterval? = nil
    ) -> SpeechDownloadCard {
        switch state {
        case .notLoaded:
            SpeechDownloadCard(
                title: modelSetTitle,
                value: nil,
                fraction: 0,
                // Invented: the export draws no not-yet-downloaded state.
                caption: String(localized: "not downloaded yet",
                                comment: "Speech model card caption before the one-time download has run"),
                action: .download
            )

        case .downloading(let fraction):
            SpeechDownloadCard(
                title: modelSetTitle,
                value: progressValue(fraction),
                fraction: fraction,
                caption: downloadingCaption(remaining: remaining),
                action: nil
            )

        case .ready:
            SpeechDownloadCard(
                title: modelSetTitle,
                value: nil,
                fraction: 1,
                // Invented: the export draws no finished state.
                caption: String(localized: "downloaded · used offline",
                                comment: "Speech model card caption once the models are on disk"),
                action: nil
            )

        case .failed(let reason):
            SpeechDownloadCard(
                title: modelSetTitle,
                value: nil,
                fraction: 0,
                // The error's own message. Never a stack trace and never a path.
                caption: reason,
                action: .retry
            )
        }
    }

    /// German, because the streaming model is asked for `de-DE` and that is a
    /// locked decision, not a preference.
    static var modelSetTitle: String {
        String(localized: "Speech models · German",
               comment: "Title of the speech model download card in settings")
    }

    /// The export writes "412 MB of 598 MB".
    ///
    /// **Retain cannot.** `SpeechModels.State.downloading` carries a fraction
    /// and no byte counts, and nothing under `Core/Speech/` exposes a total, so
    /// the same slot holds the percentage instead. `bytes(downloaded:of:)`
    /// below is the drawn form, ready for the day the byte counts exist.
    static func progressValue(_ fraction: Double) -> String {
        min(max(fraction, 0), 1).formatted(.percent.precision(.fractionLength(0)))
    }

    /// The drawn form of the same slot, for when there are byte counts to put
    /// in it.
    static func bytes(downloaded: Int64, of total: Int64) -> String {
        let done = downloaded.formatted(.byteCount(style: .file))
        let whole = total.formatted(.byteCount(style: .file))
        return String(localized: "\(done) of \(whole)",
                      comment: "Byte counts on the speech model download card")
    }

    /// "downloading · about 40 seconds left", or just "downloading" while
    /// there is nothing honest to say about the time.
    static func downloadingCaption(remaining: TimeInterval?) -> String {
        guard let remaining, remaining.isFinite, remaining > 0 else {
            return String(localized: "downloading",
                          comment: "Speech model card caption while the download runs and no estimate is available")
        }
        let time = Duration.seconds(remaining.rounded())
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return String(localized: "downloading · about \(time) left",
                      comment: "Speech model card caption with a time estimate")
    }
}
