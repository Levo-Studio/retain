import Foundation
import IOKit
import Observation

/// What the title bar and the popover header read out as "8.6 W".
///
/// **Whose watts these are is not something macOS will say.** There is no
/// public API that attributes power to a process, and nothing in the export
/// says the number is Retain's own — board 01 puts it beside "Microphone on"
/// and board 02 beside "Recording". What can be measured is what the whole
/// machine is drawing from its battery, which is the number the same figure in
/// Activity Monitor and in `pmset` is derived from, and which is the one thing
/// a student watching a recording run for ninety minutes actually cares about.
///
/// It is therefore **the system's draw, not Retain's**, and it exists only on
/// battery: plugged in, the battery is being charged rather than discharged and
/// the same registers say how fast that is going, which is a different number
/// with the same unit. On mains the reading is `nil` and the interface drops
/// the figure rather than printing something untrue.
nonisolated struct PowerDraw: Sendable, Equatable {

    /// Watts, always positive.
    let watts: Double

    // MARK: - The arithmetic

    /// `AppleSmartBattery` reports current in milliamps, signed — negative
    /// while discharging — and voltage in millivolts. Their product is
    /// microwatts.
    static func watts(milliamps: Int, millivolts: Int) -> Double {
        abs(Double(milliamps) * Double(millivolts)) / 1_000_000
    }

    /// Whether a reading means the machine is running off its battery.
    ///
    /// A positive current is charge going in, which says nothing about what the
    /// machine is spending.
    static func isDischarging(milliamps: Int) -> Bool { milliamps < 0 }

    // MARK: - Reading it

    /// The battery's instantaneous draw, or `nil` on mains and on a machine
    /// without a battery.
    ///
    /// Read on demand rather than watched: there is no notification for this
    /// number, and the alternative to asking for it is a callback that does not
    /// exist. `PowerDrawMonitor` is what decides how often it is worth asking.
    static func current() -> PowerDraw? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        // `InstantAmperage` is the unsmoothed reading; `Amperage` is the
        // averaged one. The averaged one is what a meter that is read every few
        // seconds wants — the instant value swings by watts between two samples
        // of the same steady workload and would make the figure unreadable.
        guard let milliamps = properties["Amperage"] as? Int,
              let millivolts = properties["Voltage"] as? Int,
              isDischarging(milliamps: milliamps) else {
            return nil
        }

        return PowerDraw(watts: watts(milliamps: milliamps, millivolts: millivolts))
    }
}

// MARK: - Keeping it current

/// Samples the draw while something is being recorded.
///
/// It is a poll, and it is one deliberately: hard rule 3 forbids polling **Core
/// Audio properties**, because a listener exists there and polling it drove
/// another app's `coreaudiod` to 65 % CPU. The battery gauge has no listener at
/// all, and it updates on the order of seconds. Five seconds is slower than the
/// figure changes and far slower than anything that would keep a sleeping
/// machine awake — and nothing samples at all unless a recording is running.
@MainActor
@Observable
final class PowerDrawMonitor {

    private(set) var draw: PowerDraw?

    /// Slow on purpose. See above.
    static let interval: Duration = .seconds(5)

    @ObservationIgnored private var sampling: Task<Void, Never>?

    func start() {
        guard sampling == nil else { return }
        draw = PowerDraw.current()

        sampling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled else { return }
                self?.draw = PowerDraw.current()
            }
        }
    }

    func stop() {
        sampling?.cancel()
        sampling = nil
        draw = nil
    }

    deinit {
        sampling?.cancel()
    }
}
