import Foundation
import Testing

@testable import Retain

@Suite("Speaker roles")
struct SpeakerRolesTests {

    private func segment(_ id: String, _ start: TimeInterval, _ end: TimeInterval) -> SpeakerSegment {
        SpeakerSegment(speakerID: id, start: start, end: end)
    }

    @Test("Nothing in, nothing out — no guess from an empty recording")
    func emptyGivesNothing() {
        #expect(SpeakerRoles.assign([]).isEmpty)
    }

    @Test("The cluster that speaks longest is the lecturer")
    func dominantSpeakerIsTheLecturer() {
        // The shape of a real lecture: the front talks, the room asks twice.
        let roles = SpeakerRoles.assign([
            segment("A", 0, 600),
            segment("B", 600, 615),
            segment("A", 615, 1200),
            segment("C", 1200, 1220),
            segment("A", 1220, 1800),
        ])

        #expect(roles["A"] == .lecturer)
        #expect(roles["B"] == .audience)
        #expect(roles["C"] == .audience)
    }

    @Test("One voice for the whole hour is the lecturer")
    func soleSpeakerIsTheLecturer() {
        #expect(SpeakerRoles.assign([segment("A", 0, 3600)]) == ["A": .lecturer])
    }

    /// The case the threshold exists for. Four people taking even turns is a
    /// seminar, not a lecture, and calling whichever one edges ahead "the
    /// lecturer" would put a confident wrong label across the transcript.
    @Test("Four even speakers give no lecturer rather than a coin toss")
    func evenSplitGivesNoLecturer() {
        let roles = SpeakerRoles.assign([
            segment("A", 0, 100),
            segment("B", 100, 200),
            segment("C", 200, 300),
            segment("D", 300, 400),
        ])
        #expect(roles.values.allSatisfy { $0 == .unknown })
        #expect(roles.count == 4)
    }

    @Test("Just over half is enough to be the lecturer")
    func thresholdIsInclusive() {
        let roles = SpeakerRoles.assign([segment("A", 0, 51), segment("B", 51, 100)])
        #expect(roles["A"] == .lecturer)
        #expect(roles["B"] == .audience)
    }

    @Test("Just under half is not")
    func belowThresholdGivesNothing() {
        let roles = SpeakerRoles.assign([
            segment("A", 0, 49),
            segment("B", 49, 80),
            segment("C", 80, 100),
        ])
        #expect(roles["A"] == .unknown)
    }

    /// Two clusters with exactly the same time is contrived, but an answer that
    /// changes between runs is the kind of bug nobody can reproduce.
    @Test("A tie resolves the same way every time")
    func tiesAreStable() {
        let segments = [segment("B", 0, 100), segment("A", 100, 200)]
        let first = SpeakerRoles.assign(segments)
        for _ in 0..<20 {
            #expect(SpeakerRoles.assign(segments) == first)
        }
    }

    @Test("Zero-length segments count for nothing")
    func zeroLengthSegmentsAreIgnored() {
        let roles = SpeakerRoles.assign([
            segment("A", 0, 100),
            segment("B", 100, 100),
        ])
        #expect(roles["A"] == .lecturer)
        #expect(roles["B"] == nil)
    }

    @Test("A gap between segments belongs to nobody, not to the nearest voice")
    func gapsAreUnknown() {
        let segments = [segment("A", 0, 10), segment("B", 20, 30)]
        let roles = SpeakerRoles.assign(segments)

        #expect(SpeakerRoles.role(at: 5, in: segments, roles: roles) == .lecturer)
        #expect(SpeakerRoles.role(at: 15, in: segments, roles: roles) == .unknown)
        #expect(SpeakerRoles.role(at: 25, in: segments, roles: roles) == .audience)
    }
}

// MARK: -

@Suite("Transcript assembly")
struct TranscriptAssemblyTests {

    private func words(_ items: [(String, TimeInterval, TimeInterval)]) -> [WordTiming] {
        items.map { WordTiming(text: $0.0, start: $0.1, end: $0.2) }
    }

    /// Words back to back, no pauses, one speaker.
    private func run(_ texts: [String], from start: TimeInterval = 0, each: TimeInterval = 0.3) -> [WordTiming] {
        texts.enumerated().map { index, text in
            WordTiming(
                text: text,
                start: start + Double(index) * each,
                end: start + Double(index) * each + each
            )
        }
    }

    @Test("No words, no lines")
    func emptyGivesNothing() {
        #expect(TranscriptAssembly.lines(from: []).isEmpty)
    }

    @Test("Words with no pause between them form one line")
    func continuousSpeechIsOneLine() {
        let lines = TranscriptAssembly.lines(from: run(["Der", "virtuelle", "Adressraum"]))
        #expect(lines.count == 1)
        #expect(lines[0].text == "Der virtuelle Adressraum")
        #expect(lines[0].start == 0)
        #expect(abs(lines[0].end - 0.9) < 0.0001)
        #expect(lines[0].isProvisional == false)
    }

    @Test("A pause longer than the break ends the line")
    func aPauseBreaksTheLine() {
        var items = run(["Erster", "Satz"])
        items += run(["Zweiter", "Satz"], from: 10)

        let lines = TranscriptAssembly.lines(from: items)
        #expect(lines.count == 2)
        #expect(lines[0].text == "Erster Satz")
        #expect(lines[1].text == "Zweiter Satz")
        #expect(lines[1].start == 10)
    }

    @Test("A pause shorter than the break does not")
    func aShortPauseKeepsTheLine() {
        var items = run(["Erster", "Teil"])
        // 0.6 s of silence: drawing breath, not a new thought.
        items += run(["zweiter", "Teil"], from: 1.2)

        let lines = TranscriptAssembly.lines(from: items)
        #expect(lines.count == 1)
        #expect(lines[0].text == "Erster Teil zweiter Teil")
    }

    /// A lecturer who does not pause still has to produce something clickable.
    @Test("A very long run is cut into lines anyway")
    func longRunsAreCapped() {
        let items = run((0..<400).map { "wort\($0)" })
        let lines = TranscriptAssembly.lines(from: items)

        #expect(lines.count > 1)
        // Each line may overshoot by the one word that crossed the limit.
        for line in lines {
            #expect(line.duration <= TranscriptAssembly.maximumDuration + 1)
        }
    }

    @Test("Every word ends up in exactly one line, in order")
    func nothingIsLostOrDuplicated() {
        var items = run(["eins", "zwei", "drei"])
        items += run(["vier", "fünf"], from: 5)
        items += run((0..<200).map { "w\($0)" }, from: 20)

        let lines = TranscriptAssembly.lines(from: items)
        let rejoined = lines.map(\.text).joined(separator: " ").split(separator: " ").map(String.init)
        #expect(rejoined == items.map(\.text))
    }

    @Test("Lines run forward and do not overlap")
    func linesAreOrdered() {
        var items = run(["a", "b"])
        items += run(["c", "d"], from: 5)
        items += run(["e", "f"], from: 12)

        let lines = TranscriptAssembly.lines(from: items)
        for (previous, next) in zip(lines, lines.dropFirst()) {
            #expect(previous.end <= next.start)
            #expect(previous.start < previous.end)
        }
    }

    @Test("With no diarization every line is unknown rather than guessed")
    func noSegmentsMeansUnknown() {
        let lines = TranscriptAssembly.lines(from: run(["eins", "zwei"]), segments: [])
        #expect(lines.allSatisfy { $0.speaker == .unknown })
    }

    @Test("A change of speaker ends the line even without a pause")
    func aSpeakerChangeBreaksTheLine() {
        // The lecturer speaks, the room interrupts with no gap at all.
        let items = run(["Und", "deshalb", "brauchen", "wir", "Was", "wenn"], each: 1.0)
        let segments = [
            SpeakerSegment(speakerID: "A", start: 0, end: 4),
            SpeakerSegment(speakerID: "B", start: 4, end: 6),
            SpeakerSegment(speakerID: "A", start: 6, end: 100),
        ]

        let lines = TranscriptAssembly.lines(from: items, segments: segments)
        #expect(lines.count == 2)
        #expect(lines[0].text == "Und deshalb brauchen wir")
        #expect(lines[0].speaker == .lecturer)
        #expect(lines[1].text == "Was wenn")
        #expect(lines[1].speaker == .audience)
    }

    /// A word straddling a handover belongs to whoever said most of it. Reading
    /// the start alone flips the first word after every change to the wrong
    /// speaker.
    @Test("A word that straddles a handover goes to whoever said most of it")
    func straddlingWordsFollowTheirMidpoint() {
        let items = [
            WordTiming(text: "früh", start: 0, end: 2),
            // Starts just before the handover at 4 s but is mostly after it.
            WordTiming(text: "quer", start: 3.9, end: 5.9),
            WordTiming(text: "spät", start: 6, end: 7),
        ]
        let segments = [
            SpeakerSegment(speakerID: "A", start: 0, end: 4),
            SpeakerSegment(speakerID: "B", start: 4, end: 8),
            SpeakerSegment(speakerID: "A", start: 8, end: 60),
        ]

        let lines = TranscriptAssembly.lines(from: items, segments: segments)
        let quer = lines.first { $0.text.contains("quer") }
        #expect(quer?.speaker == .audience)
    }

    @Test("Blank words do not produce an empty line")
    func blankWordsAreDropped() {
        let items = words([("", 0, 0.3), ("  ", 0.3, 0.6)])
        #expect(TranscriptAssembly.lines(from: items).isEmpty)
    }

    @Test("The batch pass replaces the live one outright")
    func batchReplacesLive() {
        let live = [TranscriptLine(start: 0, end: 1, text: "Der virtuelle Adressraum ist", isProvisional: true)]
        let batch = [TranscriptLine(start: 0, end: 1, text: "Der virtuelle Adressraum ist eine Abmachung")]

        let result = TranscriptAssembly.replacingProvisional(live, with: batch)
        #expect(result == batch)
        #expect(result.allSatisfy { !$0.isProvisional })
    }

    /// If the batch pass produced nothing — it failed, or it has not run — the
    /// live transcript is what the user has, and emptying the view would lose
    /// the lecture they just sat through.
    @Test("An empty batch result leaves the live transcript alone")
    func emptyBatchKeepsLive() {
        let live = [TranscriptLine(start: 0, end: 1, text: "etwas", isProvisional: true)]
        #expect(TranscriptAssembly.replacingProvisional(live, with: []) == live)
    }
}
