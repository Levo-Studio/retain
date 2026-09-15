import AVFoundation
import CoreAudio
import Foundation
import Observation

/// Records the microphone to a CAF and says how it is going.
///
/// The shape of this type is set by hard rule 5: the tap callback copies one
/// channel into a ring buffer and does nothing else, and everything that is
/// real work — resample, quantise, write, measure — happens on the writer's
/// `.utility` queue. Nothing here holds a power assertion (rules 2 and 8) and
/// nothing here polls Core Audio (rule 3).
@MainActor
@Observable
final class RecordingEngine {

    enum State: Equatable, Sendable {
        case idle
        case recording
        case paused
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var level: AudioLevel = .silent
    private(set) var duration: TimeInterval = 0
    private(set) var url: URL?

    /// Blocks of audio the callback could not hand over. Zero in a healthy run;
    /// anything else is lost audio and is surfaced rather than swallowed.
    private(set) var overruns: UInt64 = 0

    /// Inputs the user can choose from, kept current by the watcher rather than
    /// by asking on a timer.
    private(set) var devices: [InputDevice] = []

    /// The device to record from, by its persistent UID. `nil` follows the
    /// system default, which is what a user who plugs in a headset expects.
    var preferredDeviceUID: String? {
        didSet { if state == .recording { restartForDeviceChange() } }
    }

    /// Every block of 16 kHz mono float as it is written, for the live
    /// transcriber.
    ///
    /// Set before `start`. It is handed to the writer rather than read from the
    /// ring buffer because the ring buffer allows exactly one consumer, and
    /// because by the time the writer has it the audio is already in the format
    /// the speech models want.
    var onSamples: (@Sendable ([Float]) -> Void)?

    // MARK: - Machinery

    private let engine = AVAudioEngine()
    private var ring: AudioRingBuffer?
    private var writer: RecordingWriter?
    private var watcher: InputDeviceWatcher?
    private var drainTimer: DrainTimer?
    private var tappedFormat: AVAudioFormat?

    /// Four seconds at 48 kHz float, one channel. Sized so that a stall on the
    /// writer queue — a spinning disk, a busy machine, a Spotlight pass — costs
    /// nothing at all rather than a hole in the lecture. If four seconds is not
    /// enough, something is wrong that a bigger buffer would only hide.
    private static let ringCapacityBytes = 4 * 48_000 * MemoryLayout<Float>.size

    /// How often the writer is asked to drain. Not a poll of Core Audio — it
    /// touches nothing but our own ring buffer — and slow enough that a whole
    /// day of it is nothing, while still moving the meter about as often as the
    /// eye can use.
    private static let drainInterval: DispatchTimeInterval = .milliseconds(100)

    init() {
        devices = InputDeviceList.current()
        watcher = InputDeviceWatcher { [weak self] change in
            Task { @MainActor [weak self] in self?.handle(change) }
        }
    }

    // MARK: - Recording

    func start(writingTo url: URL) async {
        guard state != .recording else { return }

        guard await MicrophoneAccess.request() == .granted else {
            state = .failed(String(localized: "Retain has no access to the microphone.",
                                   comment: "Recording failed because permission was refused"))
            return
        }

        guard let ring = AudioRingBuffer(capacity: Self.ringCapacityBytes) else {
            state = .failed(String(localized: "Retain could not reserve memory for the recording.",
                                   comment: "Recording failed because the audio buffer could not be allocated"))
            return
        }

        let input = engine.inputNode
        if let id = resolvedDeviceID() {
            // Setting the device on the engine's own audio unit rather than
            // changing the system default: Retain picking a microphone must not
            // change which one every other app records from.
            do {
                try setInputDevice(id, on: input)
            } catch {
                state = .failed(String(localized: "Retain could not open that microphone.",
                                       comment: "Recording failed because the chosen input device could not be opened"))
                return
            }
            watcher?.follow(id)
        }

        let hardware = input.inputFormat(forBus: 0)
        guard hardware.sampleRate > 0, let tapped = CaptureFormat.tapped(at: hardware.sampleRate) else {
            state = .failed(String(localized: "The microphone reported a format Retain cannot read.",
                                   comment: "Recording failed because the input format was unusable"))
            return
        }

        let writer = RecordingWriter(
            url: url,
            ring: ring,
            onProgress: { [weak self] progress in
                Task { @MainActor [weak self] in self?.apply(progress) }
            },
            onFailure: { [weak self] failure in
                Task { @MainActor [weak self] in self?.fail(failure) }
            },
            onSamples: onSamples ?? { _ in }
        )

        do {
            try writer.open(sourceFormat: tapped)
        } catch {
            state = .failed(String(localized: "Retain could not create the recording file.",
                                   comment: "Recording failed because the output file could not be opened"))
            return
        }

        self.ring = ring
        self.writer = writer
        self.tappedFormat = tapped
        self.url = url
        duration = 0
        overruns = 0

        AudioTap.install(on: input, format: hardware, filling: ring)

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            state = .failed(String(localized: "Retain could not start the audio engine.",
                                   comment: "Recording failed because AVAudioEngine refused to start"))
            return
        }

        startDraining()
        state = .recording
    }

    func pause() {
        guard state == .recording else { return }
        engine.pause()
        stopDraining()
        writer?.drain()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        do {
            try engine.start()
            startDraining()
            state = .recording
        } catch {
            state = .failed(String(localized: "Retain could not resume the recording.",
                                   comment: "Resuming a paused recording failed"))
        }
    }

    /// Stops, flushes and closes. Returns once the file on disk is complete, so
    /// the caller can hand the URL straight to the batch transcription.
    func finish() async {
        guard state == .recording || state == .paused else { return }

        AudioTap.remove(from: engine.inputNode)
        engine.stop()
        stopDraining()
        watcher?.follow(nil)

        if let writer {
            await withCheckedContinuation { continuation in
                writer.close { continuation.resume() }
            }
        }

        self.writer = nil
        self.ring = nil
        self.tappedFormat = nil
        state = .idle
    }

    // MARK: - The tap


    private func setInputDevice(_ id: AudioObjectID, on input: AVAudioInputNode) throws {
        // No force-unwrap: an input node without an audio unit is not a state
        // worth crashing a lecture over, and falling back to the system default
        // records something rather than nothing.
        guard let unit = input.audioUnit else { throw RecordingWriter.Failure.unsupportedFormat }

        var deviceID = id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard status == noErr else { throw RecordingWriter.Failure.unsupportedFormat }
    }

    // MARK: - Draining

    private func startDraining() {
        stopDraining()
        // The handler is built here rather than written inline in the call, and
        // `DrainTimer` takes it as `@Sendable`. Inline it was inferred
        // `@MainActor` — this file's default — and the runtime check that
        // inference compiles in trapped on the first tick. See `DrainTimer`.
        drainTimer = DrainTimer(interval: Self.drainInterval) { [weak self] in
            // Reading `writer` off the main actor would be a data race, so the
            // hop is real work rather than ceremony. It is 10 Hz.
            Task { @MainActor in self?.writer?.drain() }
        }
    }

    private func stopDraining() {
        drainTimer?.cancel()
        drainTimer = nil
    }

    // MARK: - Device changes

    private func resolvedDeviceID() -> AudioObjectID? {
        if let uid = preferredDeviceUID, let match = devices.first(where: { $0.uid == uid }) {
            return match.id
        }
        return InputDeviceList.defaultDeviceID()
    }

    private func handle(_ change: InputDeviceWatcher.Change) {
        devices = InputDeviceList.current()

        switch change {
        case .deviceListChanged:
            // A device Retain is not using came or went. If the one being
            // recorded from is gone, the rate listener will not fire, so check.
            if state == .recording, let uid = preferredDeviceUID,
               !devices.contains(where: { $0.uid == uid }) {
                restartForDeviceChange()
            }

        case .defaultInputChanged:
            // Only follow the default if the user has not picked a microphone
            // by hand. Overriding a deliberate choice because a headset was
            // plugged in is worse than ignoring the headset.
            if state == .recording, preferredDeviceUID == nil {
                restartForDeviceChange()
            }

        case .sampleRateChanged:
            guard state == .recording else { return }
            restartForDeviceChange()
        }
    }

    /// Re-points the tap at the current device without ending the recording.
    /// The file keeps growing, so a swapped microphone costs a gap of
    /// milliseconds rather than a second file to stitch on later.
    private func restartForDeviceChange() {
        guard state == .recording, let ring, let writer else { return }

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        engine.stop()

        if let id = resolvedDeviceID() {
            try? setInputDevice(id, on: input)
            watcher?.follow(id)
        }

        let hardware = input.inputFormat(forBus: 0)
        guard hardware.sampleRate > 0, let tapped = CaptureFormat.tapped(at: hardware.sampleRate) else {
            state = .failed(String(localized: "The microphone reported a format Retain cannot read.",
                                   comment: "Recording failed because the input format was unusable"))
            return
        }

        writer.restart(sourceFormat: tapped)
        tappedFormat = tapped
        AudioTap.install(on: input, format: hardware, filling: ring)

        do {
            engine.prepare()
            try engine.start()
        } catch {
            state = .failed(String(localized: "Retain lost the microphone and could not reopen it.",
                                   comment: "Recording failed after the input device changed"))
        }
    }

    // MARK: - Reporting

    private func apply(_ progress: RecordingWriter.Progress) {
        duration = progress.duration
        level = progress.level
        overruns = progress.overruns
    }

    private func fail(_ failure: RecordingWriter.Failure) {
        switch failure {
        case .unsupportedFormat:
            state = .failed(String(localized: "The microphone reported a format Retain cannot read.",
                                   comment: "Recording failed because the input format was unusable"))
        case .couldNotCreateFile:
            state = .failed(String(localized: "Retain could not create the recording file.",
                                   comment: "Recording failed because the output file could not be opened"))
        case .writeFailed:
            state = .failed(String(localized: "Retain could not write to the recording file.",
                                   comment: "Recording failed while writing audio to disk"))
        }
    }
}
