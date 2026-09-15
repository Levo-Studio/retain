import Foundation
import Testing

@testable import Retain

/// The tick that moves audio out of the ring buffer.
///
/// This suite exists for one crash. The tick used to be a `DispatchSource`
/// built inline in `RecordingEngine`, and its handler was a closure literal
/// written inside a `@MainActor` method — which, with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, made it a `@MainActor` closure.
/// `setEventHandler` takes a `@Sendable` one through a `@preconcurrency`
/// declaration, so the mismatch was not an error; the compiler emitted a
/// runtime isolation check instead. On the first tick, on a `.utility` queue,
/// that check called `dispatch_assert_queue` and trapped.
///
/// The effect was that **starting a recording killed the app**, about a tenth
/// of a second in, with `SIGTRAP` and nothing on screen. Everything up to that
/// point worked, which is why it survived a green suite: nothing here ran a
/// timer.
///
/// A test that catches this cannot assert on a value — the failure is a trap
/// that takes the process with it. What it can do is let the timer fire and
/// require that the process is still alive afterwards, which is exactly what
/// the old code could not do.
@Suite("Drain timer")
struct DrainTimerTests {

    @Test("The tick runs off the main actor without trapping")
    func theTickFiresOffTheMainActor() async throws {
        let ticks = Ticks()

        let timer = DrainTimer(interval: .milliseconds(20), leeway: .milliseconds(1)) {
            ticks.record()
        }
        defer { timer.cancel() }

        try await Task.sleep(for: .milliseconds(300))

        // Reaching this line at all is the assertion: the old handler trapped
        // on its first fire and the test process went with it.
        #expect(ticks.count >= 3, "the timer did not fire often enough to prove it fires at all")
    }

    @Test("Cancelling stops the tick")
    func cancellingStops() async throws {
        let ticks = Ticks()
        let timer = DrainTimer(interval: .milliseconds(20), leeway: .milliseconds(1)) {
            ticks.record()
        }

        try await Task.sleep(for: .milliseconds(150))
        timer.cancel()
        let atCancel = ticks.count

        try await Task.sleep(for: .milliseconds(150))
        #expect(ticks.count == atCancel)
    }

    /// A counter the timer's queue and the test can both touch.
    ///
    /// `nonisolated` on purpose. Leave it off and this file's default puts it
    /// on the main actor, and the two tests below stop compiling — which is the
    /// improvement: `DrainTimer` takes its handler as `@Sendable`, so a handler
    /// that belongs to the main actor is now a build error instead of a trap a
    /// tenth of a second into a lecture.
    private nonisolated final class Ticks: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func record() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
