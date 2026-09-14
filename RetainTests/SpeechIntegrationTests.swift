import AVFoundation
import FluidAudio
import Foundation
import Testing

@testable import Retain

/// Runs the real models against a real audio file.
///
/// These download roughly a gigabyte of weights and then work for as long as
/// the recording lasts, so they do not run unless asked. Put a file at
/// `~/Library/Application Support/Retain/TestAudio/lecture.wav` and they will:
///
/// ```bash
/// DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
///   -project Retain.xcodeproj -scheme Retain \
///   -destination 'platform=macOS,arch=arm64' \
///   -only-testing:RetainTests/SpeechIntegration \
///   CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
/// ```
///
/// A path in `RETAIN_TEST_AUDIO` is used instead when it is set — which works
/// from Xcode, where the scheme carries the environment, but not from
/// `xcodebuild`, whose test host does not inherit the shell's.
///
/// The file can be anything AVFoundation reads — WAV, CAF, m4a — at any rate;
/// `AudioSamples` converts it. Use German speech, which is what the models are
/// configured for.
///
/// What is asserted here is shape, not wording: that words come back, that the
/// timings run forward and inside the recording, and that the pass is faster
/// than the lecture was. Whether the transcript is *right* is a human reading
/// it, which is what the phase 3 acceptance asks for and what no assertion can
/// stand in for. The transcript is written next to the audio so it can be read.
@Suite("SpeechIntegration", .enabled(if: SpeechFixture.isAvailable))
struct SpeechIntegrationTests {

    @Test("The batch pass transcribes a real recording", .timeLimit(.minutes(60)))
    func batchTranscribesRealAudio() async throws {
        let url = try #require(SpeechFixture.url)

        // Downloads on the first run and is cached on disk by FluidAudio
        // afterwards. No MLModelConfiguration: hard rule 4.
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let pass = LectureTranscription(models: models)

        let output = try await pass.run(url) { stage in
            switch stage {
            case .transcribing(let fraction):
                print("  transcribing \(Int(fraction * 100)) %")
            case .separatingSpeakers(let fraction):
                print("  separating speakers \(Int(fraction * 100)) %")
            case .done:
                print("  done")
            }
        }

        let duration = try SpeechFixture.duration(of: url)

        #expect(!output.lines.isEmpty, "no lines came back from a recording with speech in it")
        #expect(!output.text.isEmpty)

        // Times run forward, do not overlap, and stay inside the recording.
        // The millisecond of slack is float noise, not a real overlap: two
        // lines that share a boundary can differ by a few parts in 10^15 after
        // the arithmetic that produced them.
        for (previous, next) in zip(output.lines, output.lines.dropFirst()) {
            #expect(previous.end <= next.start + 0.001)
        }
        for line in output.lines {
            #expect(line.start >= 0)
            #expect(line.end <= duration + 1)
            #expect(line.start < line.end)
        }

        // Nothing from the batch pass is provisional; that flag belongs to the
        // live pass alone.
        #expect(output.lines.allSatisfy { !$0.isProvisional })

        // Faster than real time, or the pass would still be running when the
        // next lecture starts.
        #expect(output.realTimeFactor > 1, "ran at \(output.realTimeFactor)× real time")

        // On macOS 14 diarization does not run at all; see SpeakerDiarizer.
        if SpeakerDiarizer.availability == .available {
            #expect(output.hasSpeakers, "diarization produced no segments")
        }

        // Through the store the app uses, which is where a transcript lives
        // now — and a check that a real lecture's worth of lines, with real
        // German in them, survives the round trip and is findable afterwards.
        let database = try RetainDatabase.inMemory()
        let library = try await StoreFixture.library(in: database)
        let recordingID = try #require(library.recording.id)
        let transcript = TranscriptRepository(database)
        try await transcript.replaceLines(output.lines, for: recordingID)

        let stored = try await transcript.lines(for: recordingID)
        #expect(stored.map(\.text) == output.lines.map(\.text))

        let termID = try #require(library.term.id)
        let firstWord = try #require(
            output.lines.lazy.flatMap { $0.text.split(separator: " ") }.first { $0.count > 5 }
        )
        #expect(
            try await SearchRepository(database).search(String(firstWord), in: termID).isEmpty == false,
            "a word out of the transcript was not findable"
        )

        let transcriptURL = try writeTranscript(output.lines, beside: url)
        print("""

            \(output.lines.count) lines, \(output.text.split(separator: " ").count) words, \
            \(String(format: "%.1f", output.realTimeFactor))× real time
            speakers: \(output.hasSpeakers ? "separated" : "not separated")
            transcript: \(transcriptURL.path)

            """)
    }

    /// Writes the transcript beside the audio as JSON.
    ///
    /// Test-only, and deliberately not part of the app: the app keeps
    /// transcripts in the database. This exists because the phase 3 acceptance
    /// is a person reading a German lecture back and saying whether it is
    /// right, which needs a file they can open.
    private func writeTranscript(_ lines: [TranscriptLine], beside recording: URL) throws -> URL {
        let url = recording.deletingPathExtension().appendingPathExtension("transcript.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(lines).write(to: url, options: .atomic)
        return url
    }

    @Test("Audio loads as 16 kHz mono float whatever it was")
    func loadsAnyFormat() throws {
        let url = try #require(SpeechFixture.url)
        let samples = try AudioSamples.load(url)
        let duration = try SpeechFixture.duration(of: url)

        #expect(!samples.isEmpty)
        let loaded = Double(samples.count) / CaptureFormat.sampleRate
        #expect(abs(loaded - duration) < 0.5, "loaded \(loaded)s of a \(duration)s file")
    }

    @Test("A slice of the file is the slice that was asked for")
    func loadsASlice() throws {
        let url = try #require(SpeechFixture.url)
        let duration = try SpeechFixture.duration(of: url)
        let end = min(5.0, duration)

        let slice = try AudioSamples.load(url, from: 0, to: end)
        #expect(abs(Double(slice.count) / CaptureFormat.sampleRate - end) < 0.2)

        #expect(try AudioSamples.load(url, from: 10, to: 5).isEmpty, "a backwards range is empty, not a crash")
    }
}

// MARK: -

nonisolated enum SpeechFixture {

    /// `~/Library/Application Support/Retain/TestAudio/lecture.wav`.
    ///
    /// A fixed path rather than only an environment variable because on macOS
    /// the test host launched by `xcodebuild` does not inherit the shell's
    /// environment, so an exported variable silently skips the suite instead of
    /// running it — which looks exactly like a pass.
    static var conventionalURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Retain", isDirectory: true)
            .appendingPathComponent("TestAudio", isDirectory: true)
            .appendingPathComponent("lecture.wav")
    }

    static var url: URL? {
        if let path = ProcessInfo.processInfo.environment["RETAIN_TEST_AUDIO"], !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return FileManager.default.fileExists(atPath: conventionalURL.path) ? conventionalURL : nil
    }

    static var isAvailable: Bool { url != nil }

    static func duration(of url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
