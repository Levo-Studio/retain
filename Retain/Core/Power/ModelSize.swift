import Foundation

/// Where the Mac is getting its power from.
nonisolated enum PowerState: Hashable, Sendable {

    /// Plugged in. The only state in which the large model is allowed to run.
    case mains

    case battery

    /// Nothing answered. A desktop with no battery reports mains, so this is
    /// not "no battery" — it is "the question could not be answered", and it is
    /// treated as battery below.
    case unknown
}

/// Which of the two configured models a job runs on.
nonisolated enum ModelSize: Hashable, Sendable, Codable {

    /// 3–8B. Summarises one block while the lecture is running, and is the only
    /// size that ever runs on battery.
    case small

    /// The reduce model. Sees every block summary plus the batch transcript at
    /// once, which is where the size actually buys something.
    case large
}

/// Decides which model size a job may use.
///
/// Hard rule 7: **the large model runs on mains only.** Retain has to survive a
/// whole school day on one charge, and a 30B model held resident and fed the
/// whole transcript is the single most expensive thing the app can do. A
/// lecture summarised slightly less well is a worse outcome than a laptop that
/// dies in the fifth period, so the rule has no override.
///
/// Pure and separate from `PowerMonitor` so the decision is a table that can be
/// read and tested, rather than an `if` buried in whichever object happened to
/// be holding the power state.
nonisolated enum ModelSizeDecision {

    /// - Parameters:
    ///   - power: where the Mac is drawing from.
    ///   - lowPowerMode: `ProcessInfo.processInfo.isLowPowerModeEnabled`. It
    ///     wins even on mains: the user asked the whole machine to do less, and
    ///     a background summariser is exactly the kind of work they meant.
    static func size(power: PowerState, lowPowerMode: Bool) -> ModelSize {
        if lowPowerMode { return .small }
        return power == .mains ? .large : .small
    }
}
