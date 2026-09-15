import Testing

@testable import Retain

/// The two ways the voice-activity model was believed too readily: a cough
/// closing a line, and a voice from across the room it never flagged at all.
///
/// The numbers are the ones the app runs with, in whole chunks so a test reads
/// as seconds of a lesson: 16 kHz, chunks of 4096 samples, 256 ms each.
@Suite("Live gate")
struct LiveGateTests {

    static let chunk = 4096
    static let rate = 16_000

    static func gate(
        hangover: Double = 3,
        longestLine: Double = 20,
        idleLag: Double = 3
    ) -> LiveGate {
        LiveGate(
            hangoverSamples: Int(hangover * Double(rate)),
            longestLineSamples: Int(longestLine * Double(rate)),
            idleLagSamples: Int(idleLag * Double(rate))
        )
    }

    static func run(
        _ gate: inout LiveGate,
        _ signal: LiveGate.Signal,
        chunks: Int
    ) -> [LiveGate.Step] {
        (0..<chunks).map { _ in gate.advance(signal, chunk: chunk) }
    }

    static func feeds(_ step: LiveGate.Step) -> Bool { true }

    static func closes(_ steps: [LiveGate.Step]) -> [Int] {
        steps.compactMap { if case .close(let at) = $0 { at } else { nil } }
    }

    // MARK: - The voice from the back of the room

    /// A lecture the model never calls speech is still transcribed.
    ///
    /// This is the report that took the gate off the audio path: a voice that
    /// is perfectly audible on the recording, and a live transcript that stayed
    /// empty. Every chunk now reaches the speech model, and the line is read
    /// off on the timer instead of on the model's say-so.
    @Test("Audio the model never flags is still fed and still becomes lines")
    func theUnflaggedVoiceIsTranscribed() {
        var gate = Self.gate()
        let steps = Self.run(&gate, .quiet, chunks: 400)

        #expect(steps.allSatisfy(Self.feeds))
        #expect(!Self.closes(steps).isEmpty)
    }

    /// And it is dated close to when it was said, rather than from the start of
    /// the quiet stretch before it.
    @Test("An unflagged line starts no further back than the idle lag")
    func theUnflaggedLineIsDatedCloseBy() {
        var gate = Self.gate()
        _ = Self.run(&gate, .quiet, chunks: 40)

        #expect(gate.processed - gate.lineStart <= 3 * Self.rate + Self.chunk)
    }

    // MARK: - The cough

    /// A cough in the middle of a sentence must not cost the sentence.
    @Test("A brief drop-out does not break the line")
    func theCoughKeepsTheLine() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        _ = Self.run(&gate, .quiet, chunks: 20)

        var duringTheCough = [gate.advance(.end, chunk: Self.chunk)]
        duringTheCough += Self.run(&gate, .quiet, chunks: 2)
        duringTheCough.append(gate.advance(.start, chunk: Self.chunk))

        #expect(duringTheCough.allSatisfy { $0 == .feed })
        #expect(gate.isOpen)
    }

    @Test("Speech resuming inside the hangover continues the same line")
    func theLineIsNotRestarted() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        let start = gate.lineStart

        _ = gate.advance(.end, chunk: Self.chunk)
        _ = Self.run(&gate, .quiet, chunks: 4)
        _ = gate.advance(.start, chunk: Self.chunk)

        #expect(gate.lineStart == start)
    }

    // MARK: - Breaking lines where the speech stops

    @Test("Silence past the hangover closes the line once")
    func realSilenceCloses() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        _ = gate.advance(.end, chunk: Self.chunk)
        let silenceBegan = gate.processed
        let after = Self.run(&gate, .quiet, chunks: 20)

        #expect(Self.closes(after) == [silenceBegan])
        #expect(!gate.isOpen)
    }

    /// Somebody who talks without a gap the model notices still gets lines, and
    /// the decoder still gets reset — and the next line picks up immediately,
    /// which is the mistake that would be invisible until a lecture went silent
    /// halfway through.
    @Test("An unbroken line is cut and the next one opens at once")
    func theLongLineIsCut() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        let steps = Self.run(&gate, .quiet, chunks: 200)

        #expect(Self.closes(steps).count >= 2)
        #expect(gate.isOpen)
    }

    /// The line after a cut starts where the cut was, not later.
    @Test("A cut hands the timeline straight over")
    func theCutHandsOver() {
        var gate = Self.gate()
        _ = gate.advance(.start, chunk: Self.chunk)

        var cutAt: Int?
        var opened: Int?
        for _ in 0..<200 {
            switch gate.advance(.quiet, chunk: Self.chunk) {
            case .close(let at) where cutAt == nil: cutAt = at
            case .open(let start) where cutAt != nil && opened == nil: opened = start
            default: break
            }
        }

        #expect(opened == cutAt)
    }
}
