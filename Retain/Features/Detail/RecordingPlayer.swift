import AVFoundation
import Foundation

/// Plays back one recording's audio so a click in the transcript lands
/// somewhere.
///
/// `AVAudioPlayer` rather than `AVAudioEngine`: this is file playback of a
/// finished CAF with no processing on it, and the engine would mean a render
/// callback and a graph to keep alive for something the system already does.
/// Nothing here runs on the audio thread, so the real-time rules that govern
/// `Core/Audio/` do not reach it.
///
/// **The export draws no transport.** There is no play button, no scrubber and
/// no playhead on boards 03 or 04 — the only thing drawn is that a line, a
/// chapter and a source chip are places to jump to. So this exposes seeking and
/// nothing that would need a control drawn for it.
@Observable
final class RecordingPlayer {

    /// Whether there is audio to play at all. A recording whose file was moved
    /// or deleted still has notes and a transcript worth reading, so this is a
    /// state rather than an error: the text stays, the clicks do nothing.
    private(set) var isLoaded = false

    private(set) var isPlaying = false

    /// Where playback stands, as of the last thing that moved it. Not polled —
    /// nothing is drawn from it, and a timer ticking against a battery the app
    /// is supposed to last a school day on would be paid for nothing.
    private(set) var time: TimeInterval = 0

    private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?

    // MARK: - Loading

    /// Opens the audio for a recording.
    ///
    /// The store keeps the file's name and not its path, so the folder is
    /// resolved here rather than written into the database.
    func load(filename: String?) {
        guard let filename, !filename.isEmpty else {
            unload()
            return
        }
        load(RecordingStore.directory.appendingPathComponent(filename))
    }

    func load(_ url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            time = 0
            isLoaded = true
            isPlaying = false
        } catch {
            // A missing or unreadable file is ordinary — the recording may
            // predate a move of the folder — and there is nothing drawn to
            // report it with.
            unload()
        }
    }

    func unload() {
        player?.stop()
        player = nil
        isLoaded = false
        isPlaying = false
        time = 0
        duration = 0
    }

    // MARK: - Moving

    /// Jumps to a second and plays from it.
    ///
    /// Seeking without playing would leave a click in the transcript with no
    /// effect anybody can hear, which is the same as the click not working.
    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = DetailSeek.clamped(seconds, duration: duration)
        time = player.currentTime
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        time = player?.currentTime ?? time
        isPlaying = false
    }

    /// What a second click on the line that is already playing does.
    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            pause()
        } else {
            player.play()
            isPlaying = true
        }
    }
}
