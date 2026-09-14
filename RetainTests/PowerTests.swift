import Foundation
import Testing

@testable import Retain

@Suite("Model size")
struct ModelSizeDecisionTests {

    /// Hard rule 7, as a table. The only combination that gets the large model
    /// is a Mac that is plugged in and not being asked to save power.
    @Test("The large model runs on mains only")
    func theTable() {
        #expect(ModelSizeDecision.size(power: .mains, lowPowerMode: false) == .large)
        #expect(ModelSizeDecision.size(power: .mains, lowPowerMode: true) == .small)
        #expect(ModelSizeDecision.size(power: .battery, lowPowerMode: false) == .small)
        #expect(ModelSizeDecision.size(power: .battery, lowPowerMode: true) == .small)
    }

    /// Low Power Mode is the user asking the whole machine to do less, and a
    /// background summariser is exactly the kind of work they meant.
    @Test("Low Power Mode wins even with a charger in")
    func lowPowerModeWinsOnMains() {
        #expect(ModelSizeDecision.size(power: .mains, lowPowerMode: true) == .small)
    }

    /// "Unknown" is not "no battery" — a desktop reports mains. It is the
    /// question having gone unanswered, and guessing large would be guessing
    /// with somebody's afternoon of battery.
    @Test("An unanswered power source is treated as battery")
    func unknownIsTreatedAsBattery() {
        #expect(ModelSizeDecision.size(power: .unknown, lowPowerMode: false) == .small)
        #expect(ModelSizeDecision.size(power: .unknown, lowPowerMode: true) == .small)
    }

    @Test("The decision is a function of its two inputs and nothing else")
    func decisionIsStable() {
        for _ in 0..<50 {
            #expect(ModelSizeDecision.size(power: .mains, lowPowerMode: false) == .large)
        }
    }
}

// MARK: -

@Suite("Power monitor")
@MainActor
struct PowerMonitorTests {

    /// The monitor reads whatever this machine is doing, so the test can only
    /// check that it answered at all and that the answer is self-consistent.
    /// The decision itself is tested exhaustively above, where it is pure.
    @Test("The monitor answers with a state and a matching model size")
    func monitorAgreesWithTheDecision() {
        let monitor = PowerMonitor()
        monitor.refresh()

        #expect(
            monitor.reduceModelSize
                == ModelSizeDecision.size(power: monitor.state, lowPowerMode: monitor.isLowPowerMode)
        )
    }

    @Test("Starting twice and stopping unstarted are both harmless")
    func startAndStopAreIdempotent() {
        let monitor = PowerMonitor()
        monitor.stop()
        monitor.start()
        monitor.start()
        monitor.stop()
        monitor.stop()
    }
}
