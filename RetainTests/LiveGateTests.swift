import Testing

@testable import Retain

/// A cough closing a line, which is what these are about.
///
/// The numbers are the ones the app runs with, expressed in whole chunks so a
/// test reads as seconds of a lesson: 16 kHz, chunks of 4096 samples, which is
/// 256 ms each.
@Suite("Live gate")
struct LiveGateTests {

    static let chunk = 4096
    static let rate = 16_000

    static func gate(
        hangover: Double = 3.0,
        preRoll: Double = 0.5,
        longestLine: Double = 20
    ) -> LiveGate {
        LiveGate(
            hangoverSamples: Int(hangover * Double(rate)),
            preRollSamples: Int(preRoll * Double(rate)),
            longestLineSamples: Int(longestLine * Double(rate))
        )
    }

    /// Runs one signal for a number of chunks and collects what came back.
    static func run(
        _ gate: inout LiveGate,
        _ signal: LiveGate.Signal,
        chunks: Int
    ) -> [LiveGate.Step] {
        (0..<chunks).map { _ in gate.advance(signal, chunk: chunk) }
    }

    // MARK: - The report

    /// A cough in the middle of a sentence must not cost the sentence.
    ///
    /// The gate says the speech stopped, the speaker carries on half a second
    /// later, and every chunk in between still reaches the model. This is the
    /// case that failed in the room: the line closed on the `end`, the audio
    /// after it was thrown away, and the lesson lost about twenty seconds.
    @Test("A brief drop-out neither closes the line nor loses audio")
    func coughKeepsTheLine() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        _ = Self.run(&gate, .quiet, chunks: 20)

        var duringTheCough = [gate.advance(.end, chunk: Self.chunk)]
        duringTheCough += Self.run(&gate, .quiet, chunks: 2)
        duringTheCough.append(gate.advance(.start, chunk: Self.chunk))

        #expect(duringTheCough.allSatisfy { $0 == .feed })
        #expect(gate.isOpen)
    }

    /// The other half of the same case: the line survives, so the words on
    /// either side of the cough end up in one line rather than none.
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

    // MARK: - Still closing lines

    /// Silence that really is silence still ends the line, or the transcript
    /// would be one line per lecture.
    @Test("Silence past the hangover closes the line once")
    func realSilenceCloses() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        _ = gate.advance(.end, chunk: Self.chunk)
        let after = Self.run(&gate, .quiet, chunks: 30)

        let closes = after.filter { if case .close = $0 { true } else { false } }
        #expect(closes.count == 1)
        #expect(!gate.isOpen)
    }

    /// The line is dated where the speech stopped, not three seconds later.
    @Test("The closed line ends where the silence began")
    func theLineEndsAtTheSilence() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        _ = gate.advance(.end, chunk: Self.chunk)
        let silenceBegan = gate.processed

        var closedAt: Int?
        for _ in 0..<30 where closedAt == nil {
            if case .close(let at) = gate.advance(.quiet, chunk: Self.chunk) { closedAt = at }
        }

        #expect(closedAt == silenceBegan)
    }

    /// Between lines the audio is kept, not fed, so the gate still saves the
    /// battery it was put there to save.
    @Test("Audio between lines is kept rather than decoded")
    func silenceIsNotDecoded() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        _ = gate.advance(.end, chunk: Self.chunk)
        _ = Self.run(&gate, .quiet, chunks: 30)

        #expect(Self.run(&gate, .quiet, chunks: 10).allSatisfy { $0 == .keep })
    }

    /// And what was kept starts the next line, so it does not begin mid-word.
    @Test("A line starts before the chunk that opened it")
    func theLineStartsInThePreRoll() {
        var gate = Self.gate()

        _ = Self.run(&gate, .quiet, chunks: 40)
        let openedAt = gate.processed

        guard case .open(let lineStart) = gate.advance(.start, chunk: Self.chunk) else {
            Issue.record("the gate did not open")
            return
        }

        #expect(lineStart == openedAt - Int(0.5 * Double(Self.rate)))
    }

    // MARK: - The long line

    /// Somebody who talks for twenty minutes without a gap the model notices
    /// still gets lines, and the decoder still gets reset — and the feed does
    /// not stop, which is the mistake that would be invisible until a lecture
    /// went silent halfway through.
    @Test("An unbroken line is cut and the feed carries straight on")
    func theLongLineIsCut() {
        var gate = Self.gate()

        _ = gate.advance(.start, chunk: Self.chunk)
        let steps = Self.run(&gate, .quiet, chunks: 200)

        let cuts = steps.filter { if case .cut = $0 { true } else { false } }
        #expect(cuts.count >= 2)
        #expect(!steps.contains(.keep))
        #expect(gate.isOpen)
    }
}
