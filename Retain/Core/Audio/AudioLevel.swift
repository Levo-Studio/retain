import Foundation

/// What the meter in the title bar, the popover and Settings is drawn from.
///
/// Peak drives the warning about a microphone that is clipping; RMS drives the
/// bar, because peak alone jitters too hard to read. Both are in dBFS, where 0
/// is full scale and quieter is more negative.
nonisolated struct AudioLevel: Equatable, Sendable {

    /// Loudest single sample in the window, in dBFS.
    let peak: Float

    /// Root mean square over the window, in dBFS.
    let rms: Float

    /// Everything below this reads as silence rather than as a very quiet room.
    /// Picked to sit under the noise floor of a MacBook's own microphone in a
    /// quiet room, which measures around −60 dBFS, so that "Silence · MacBook
    /// Pro Microphone" in the ready state means nobody is talking rather than
    /// nobody is in the building.
    static let silenceThreshold: Float = -55

    static let silent = AudioLevel(peak: floor, rms: floor)

    /// The value a digital zero maps to. `log10(0)` is negative infinity, which
    /// is not a number a view can lay out, so the scale stops here — far below
    /// anything a microphone produces.
    static let floor: Float = -120

    var isSilent: Bool { rms < Self.silenceThreshold }

    var isClipping: Bool { peak >= -0.1 }

    /// Where the bar should sit, 0 to 1, with `floor`…0 dBFS mapped onto the
    /// part of the scale a meter is read in. Below −55 dBFS the bar is empty;
    /// a meter that twitches at the noise floor reads as a fault.
    var barFraction: Float {
        let span = -Self.silenceThreshold
        let clamped = min(max(rms, Self.silenceThreshold), 0)
        return (clamped - Self.silenceThreshold) / span
    }
}

// MARK: - Measuring

nonisolated extension AudioLevel {

    /// Measures a window of float samples.
    ///
    /// This runs on the writer queue, never in the audio callback: it is a pass
    /// over every sample with two multiplies, which is exactly the kind of work
    /// hard rule 5 keeps off the audio thread.
    static func measure(_ samples: UnsafeBufferPointer<Float>) -> AudioLevel {
        guard !samples.isEmpty else { return .silent }

        var peak: Float = 0
        var sumOfSquares: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak { peak = magnitude }
            sumOfSquares += sample * sample
        }

        let meanSquare = sumOfSquares / Float(samples.count)
        return AudioLevel(peak: decibels(peak), rms: decibels(meanSquare.squareRoot()))
    }

    static func measure(_ samples: [Float]) -> AudioLevel {
        samples.withUnsafeBufferPointer { measure($0) }
    }

    /// Amplitude 0…1 to dBFS, floored rather than allowed to reach −∞.
    static func decibels(_ amplitude: Float) -> Float {
        guard amplitude > 0 else { return floor }
        return max(floor, 20 * log10(amplitude))
    }
}
