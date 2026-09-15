import Foundation

/// The 10 Hz tick that moves audio out of the ring buffer and into the file.
///
/// **A type of its own because of the crash it caused.** The tick used to be a
/// `DispatchSource` created inline in `RecordingEngine`, and its handler was a
/// closure literal written inside a `@MainActor` method. This project builds
/// with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so that closure was
/// inferred `@MainActor` — and `setEventHandler` takes a `@Sendable` closure
/// through a `@preconcurrency` declaration, which does not reject the mismatch
/// but compiles in a runtime isolation check instead. The first time the timer
/// fired, on a `.utility` queue, the check called `dispatch_assert_queue`, which
/// trapped. Starting a recording killed the app a tenth of a second later,
/// every time, with a `SIGTRAP` and no message.
///
/// So the handler is declared `@Sendable` explicitly and lives here, where the
/// declaration is the whole file and cannot be lost in an edit. Nothing in this
/// type is on the main actor.
nonisolated final class DrainTimer {

    private let source: any DispatchSourceTimer

    /// - Parameters:
    ///   - interval: how often to tick.
    ///   - queue: never the main queue. Draining reads the ring buffer and
    ///     writes a file, which is `.utility` work.
    ///   - tick: **must be `@Sendable`.** It runs on `queue`, and a handler the
    ///     compiler believes belongs to the main actor traps there.
    init(
        interval: DispatchTimeInterval,
        leeway: DispatchTimeInterval = .milliseconds(50),
        queue: DispatchQueue = .global(qos: .utility),
        tick: @escaping @Sendable () -> Void
    ) {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        source.setEventHandler(handler: tick)
        self.source = source
        source.resume()
    }

    func cancel() {
        source.cancel()
    }

    deinit {
        source.cancel()
    }
}
