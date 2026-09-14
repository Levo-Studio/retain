import CoreAudio
import Foundation

/// An audio input the user can pick in Settings.
///
/// A value, not a handle: it is read once and passed around, and `id` is what
/// anything that needs to talk to Core Audio uses. Devices come and go, so a
/// stored `id` is checked against the current list rather than trusted.
nonisolated struct InputDevice: Identifiable, Hashable, Sendable {

    /// The `AudioObjectID`. Unique while the device is present and reused after
    /// it is gone, so it is never persisted on its own.
    let id: AudioObjectID

    /// What Settings shows: "MacBook Pro Microphone".
    let name: String

    /// Survives a reboot and a reconnect, unlike `id`. This is what a chosen
    /// microphone is remembered by.
    let uid: String

    /// Input channels the device offers. Retain reads the first one; see
    /// `RecordingEngine` for why.
    let inputChannels: Int

    /// The rate the device is running at. Retain resamples to 16 kHz rather
    /// than asking the device to change, because changing it affects every
    /// other app using the same device.
    let sampleRate: Double
}

// MARK: - Reading the device list

nonisolated enum InputDeviceList {

    /// Every device that has at least one input channel, in the order Core
    /// Audio reports them.
    static func current() -> [InputDevice] {
        allDeviceIDs().compactMap(device(for:))
    }

    static func defaultDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return deviceID
    }

    static func device(for id: AudioObjectID) -> InputDevice? {
        let channels = inputChannelCount(of: id)
        guard channels > 0 else { return nil }
        guard let uid = string(kAudioDevicePropertyDeviceUID, of: id) else { return nil }
        let name = string(kAudioObjectPropertyName, of: id) ?? uid
        return InputDevice(
            id: id,
            name: name,
            uid: uid,
            inputChannels: channels,
            sampleRate: sampleRate(of: id)
        )
    }

    // MARK: - Core Audio plumbing

    private static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, buffer.baseAddress!
            )
        }
        return status == noErr ? ids : []
    }

    private static func inputChannelCount(of id: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        // AudioBufferList is variable length, so it has to be allocated by hand
        // rather than declared. Off the audio thread, so allocating is fine.
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func sampleRate(of id: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr else { return 0 }
        return rate
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // Core Audio hands back a retained CFStringRef, so the out-parameter is
        // Unmanaged and the reference has to be taken rather than borrowed.
        // Declaring it as a plain CFString instead compiles and leaks, and the
        // compiler warns that it is likely wrong for exactly that reason.
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }

        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }
}
