import CoreAudio
import Foundation

/// Watches the input devices and says when something about them changed.
///
/// **Hard rule 3: nothing in here polls.** Every change arrives through
/// `AudioObjectAddPropertyListenerBlock`. Asking Core Audio the same question on
/// a timer is what drove `coreaudiod` to 65 % CPU in another app and leaked
/// thousands of audio contexts, and a recording that runs for a whole school
/// day is exactly the case where that bill comes due. There is no timer here
/// and there must never be one.
///
/// Three properties are watched, and each one for its own reason:
///
/// - the device list, so Settings can offer a microphone that was just plugged
///   in and stop offering one that was unplugged;
/// - the default input, because a user who plugs in headphones expects the
///   recording to follow unless they picked a device by hand;
/// - the nominal sample rate of the device being recorded, because another app
///   can change it underneath us and every sample after that point would be
///   resampled from the wrong rate.
nonisolated final class InputDeviceWatcher: @unchecked Sendable {

    /// What happened. The engine decides what to do about it; the watcher only
    /// reports.
    enum Change: Sendable {
        case deviceListChanged
        case defaultInputChanged
        /// The device Retain is recording from is now running at a different
        /// rate. Everything buffered belongs to the old one.
        case sampleRateChanged(AudioObjectID)
    }

    private let queue = DispatchQueue(label: "studio.levo.retain.device-watcher", qos: .utility)
    private let handler: @Sendable (Change) -> Void

    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var rateListener: (AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)?
    private let lock = NSLock()

    init(onChange handler: @escaping @Sendable (Change) -> Void) {
        self.handler = handler
        listen(to: kAudioHardwarePropertyDevices, reporting: .deviceListChanged)
        listen(to: kAudioHardwarePropertyDefaultInputDevice, reporting: .defaultInputChanged)
    }

    deinit {
        for (address, block) in systemListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block
            )
        }
        if let (id, address, block) = rateListener {
            var address = address
            AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
        }
    }

    // MARK: - Following one device

    /// Starts reporting sample-rate changes for `id` and stops reporting them
    /// for whatever was being followed before. Pass `nil` while nothing is being
    /// recorded, so no listener sits on a device Retain is not using.
    func follow(_ id: AudioObjectID?) {
        lock.lock()
        defer { lock.unlock() }

        if let (previous, address, block) = rateListener {
            var address = address
            AudioObjectRemovePropertyListenerBlock(previous, &address, queue, block)
            rateListener = nil
        }

        guard let id else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let handler = handler
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler(.sampleRateChanged(id)) }

        guard AudioObjectAddPropertyListenerBlock(id, &address, queue, block) == noErr else { return }
        rateListener = (id, address, block)
    }

    // MARK: - Plumbing

    private func listen(to selector: AudioObjectPropertySelector, reporting change: Change) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let handler = handler
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler(change) }

        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block
        ) == noErr else { return }

        systemListeners.append((address, block))
    }
}
