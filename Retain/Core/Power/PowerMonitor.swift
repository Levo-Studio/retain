import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// Watches the power source and Low Power Mode, and answers which model size
/// a reduce may use right now.
///
/// **Nothing here polls.** `IOPSNotificationCreateRunLoopSource` calls back when
/// the power source changes, and `NSProcessInfoPowerStateDidChange` covers Low
/// Power Mode. A timer asking `pmset` every few seconds would keep waking a
/// laptop that is doing nothing, which is the cost this whole type exists to
/// avoid.
@MainActor
@Observable
final class PowerMonitor {

    private(set) var state: PowerState = PowerMonitor.currentState()
    private(set) var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// The size the reduce step may use right now.
    ///
    /// The map step is not asked: a block summary always runs on the small
    /// model, whatever the power source, because it has to finish while the
    /// lecture is still running.
    var reduceModelSize: ModelSize {
        ModelSizeDecision.size(power: state, lowPowerMode: isLowPowerMode)
    }

    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var lowPowerObserver: (any NSObjectProtocol)?

    // MARK: - Watching

    /// Starts watching. Calling it twice does nothing the second time.
    ///
    /// Started and stopped explicitly rather than in `init`/`deinit`: the
    /// monitor lives for as long as the app does, and a run-loop source torn
    /// down from a deinitialiser that may or may not run on the main thread is
    /// a race nobody would ever see fail.
    func start() {
        guard powerSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            // The source is attached to the main run loop below, so this
            // callback is already on the main thread.
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue()

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Both flags are re-read rather than only the one that changed:
            // unplugging a charger flips the power source and can switch Low
            // Power Mode on in the same breath, and reading one of the two
            // leaves the pair briefly disagreeing.
            MainActor.assumeIsolated { self?.refresh() }
        }

        refresh()
    }

    func stop() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        powerSource = nil

        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        lowPowerObserver = nil
    }

    func refresh() {
        state = Self.currentState()
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // MARK: - Reading

    static func currentState() -> PowerState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .unknown }
        guard let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return .unknown
        }

        switch type as String {
        case kIOPMACPowerKey:
            return .mains
        // A UPS is a battery that happens to be large. It still runs out.
        case kIOPMBatteryPowerKey, kIOPMUPSPowerKey:
            return .battery
        default:
            return .unknown
        }
    }
}
