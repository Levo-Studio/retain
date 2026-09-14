import Foundation
import Testing

@testable import Retain

@Suite("Settings — speech, microphone and sections")
struct SettingsPaneTests {

    // MARK: - The speech-model card

    @Test("Nothing downloaded offers the download and draws an empty bar")
    func notLoaded() {
        let card = SpeechDownloadCard.make(for: .notLoaded)
        #expect(card.fraction == 0)
        #expect(card.action == .download)
        #expect(card.caption == "not downloaded yet")
        #expect(card.value == nil)
    }

    @Test("A download in flight draws the bar, the progress and an estimate")
    func downloading() {
        let card = SpeechDownloadCard.make(for: .downloading(0.69), remaining: 40)
        #expect(card.fraction == 0.69)
        #expect(card.action == nil)
        #expect(card.caption == "downloading · about 40 seconds left")
        #expect(card.value?.hasPrefix("69") == true)
    }

    @Test("A download with nothing yet to say about the time says nothing about it")
    func downloadingWithoutAnEstimate() {
        #expect(SpeechDownloadCard.make(for: .downloading(0.02)).caption == "downloading")
        #expect(SpeechDownloadCard.downloadingCaption(remaining: 0) == "downloading")
        #expect(SpeechDownloadCard.downloadingCaption(remaining: .infinity) == "downloading")
    }

    @Test("A finished download fills the bar and offers nothing")
    func ready() {
        let card = SpeechDownloadCard.make(for: .ready)
        #expect(card.fraction == 1)
        #expect(card.action == nil)
        #expect(card.caption == "downloaded · used offline")
    }

    /// The message and nothing else: no stack trace, no file path, no URL.
    @Test("A failure shows the error's own message and offers a retry")
    func failed() {
        let card = SpeechDownloadCard.make(for: .failed("The network connection was lost."))
        #expect(card.caption == "The network connection was lost.")
        #expect(card.action == .retry)
        #expect(card.fraction == 0)
    }

    /// The percentage is the user's own number format — "69 %" in a German
    /// locale, "69%" in an English one — so what is asserted is the arithmetic
    /// and not the separator: rounded to a whole percent, clamped to 0…1.
    @Test("The progress value is a whole percentage, clamped")
    func progressValue() {
        #expect(SpeechDownloadCard.progressValue(0).hasPrefix("0"))
        #expect(SpeechDownloadCard.progressValue(0.694).hasPrefix("69"))
        #expect(SpeechDownloadCard.progressValue(0.696).hasPrefix("70"))
        #expect(SpeechDownloadCard.progressValue(1).hasPrefix("100"))
        #expect(SpeechDownloadCard.progressValue(-1).hasPrefix("0"))
        #expect(SpeechDownloadCard.progressValue(2).hasPrefix("100"))
        #expect(SpeechDownloadCard.progressValue(0.5).contains("%"))
        #expect(!SpeechDownloadCard.progressValue(0.694).contains("."))
    }

    /// The form board 06 actually draws, for the day `SpeechModels` reports
    /// byte counts.
    @Test("Byte counts read the way the board writes them")
    func byteCounts() {
        #expect(SpeechDownloadCard.bytes(downloaded: 412_000_000, of: 598_000_000) == "412 MB of 598 MB")
    }

    // MARK: - The estimate

    @Test("An estimate needs two samples")
    func estimateNeedsTwoSamples() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let estimate = DownloadEstimate().observing(0, at: start)
        #expect(estimate.remaining(at: 0, now: start) == nil)
    }

    @Test("Half done in ten seconds is ten seconds to go")
    func estimateFromRate() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let estimate = DownloadEstimate().observing(0, at: start)
        let remaining = try #require(estimate.remaining(at: 0.5, now: start.addingTimeInterval(10)))
        #expect(abs(remaining - 10) < 0.001)
    }

    @Test("A finished download has nothing left to estimate")
    func estimateAtTheEnd() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let estimate = DownloadEstimate().observing(0, at: start)
        #expect(estimate.remaining(at: 1, now: start.addingTimeInterval(10)) == nil)
    }

    @Test("A fraction that goes backwards starts a new measurement")
    func estimateReseeds() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var estimate = DownloadEstimate().observing(0.9, at: start)
        estimate = estimate.observing(0.1, at: start.addingTimeInterval(100))

        // Measured from the restart, not from the first sample: a quarter of
        // the way in ten seconds is thirty seconds to go.
        let remaining = try #require(estimate.remaining(at: 0.35, now: start.addingTimeInterval(110)))
        #expect(abs(remaining - 26) < 0.5)
    }

    // MARK: - The level meter

    @Test("The readout is whole decibels with a real minus sign")
    func decibelReadout() {
        #expect(MicrophoneReadout.decibels(AudioLevel(peak: -3, rms: -18)) == "\u{2212}18 dB")
        #expect(MicrophoneReadout.decibels(AudioLevel(peak: -3, rms: -18.4)) == "\u{2212}18 dB")
        #expect(MicrophoneReadout.decibels(AudioLevel(peak: -3, rms: -17.6)) == "\u{2212}18 dB")
        #expect(MicrophoneReadout.decibels(AudioLevel(peak: 0, rms: 0)) == "0 dB")
    }

    @Test("The minus sign is U+2212 and not a hyphen")
    func minusSignIsTypographic() {
        let readout = MicrophoneReadout.decibels(AudioLevel(peak: -3, rms: -18))
        #expect(!readout.contains("-"))
        #expect(readout.contains(MicrophoneReadout.minusSign))
    }

    @Test("Silence reads as the floor, not as an empty string")
    func silenceReadout() {
        #expect(MicrophoneReadout.decibels(.silent) == "\u{2212}120 dB")
        #expect(AudioLevel.silent.barFraction == 0)
    }

    @Test("A thousand-decibel reading would still have no grouping separator")
    func noGroupingInTheReadout() {
        #expect(MicrophoneReadout.decibels(AudioLevel(peak: 0, rms: -1200)) == "\u{2212}1200 dB")
    }

    // MARK: - Permission

    @Test("Only the granted state is drawn, and it says what the board says")
    func permissionCopy() {
        #expect(MicrophoneReadout.permission(.granted) == "granted")
        #expect(MicrophoneReadout.remedy(.granted) == nil)
    }

    /// Asking a second time after a refusal does nothing on macOS, so the
    /// refused state must not offer another ask.
    @Test("A refusal offers System Settings, not another ask")
    func refusalOffersSettings() {
        #expect(MicrophoneReadout.remedy(.denied) == .openSystemSettings)
        #expect(MicrophoneReadout.remedy(.undetermined) == .ask)
    }

    // MARK: - The sidebar

    @Test("The sidebar has the five sections the board draws, in that order")
    func sections() {
        #expect(SettingsSection.allCases == [.general, .languageModel, .speechRecognition, .microphone, .shortcuts])
        #expect(SettingsSection.allCases.map(\.title) == [
            "General", "Language model", "Speech recognition", "Microphone", "Shortcuts",
        ])
    }
}
