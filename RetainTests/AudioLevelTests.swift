import Foundation
import Testing

@testable import Retain

@Suite("Audio level")
struct AudioLevelTests {

    @Test("Digital silence reads as the floor, not as negative infinity")
    func silenceIsFloored() {
        let level = AudioLevel.measure([Float](repeating: 0, count: 512))
        #expect(level.peak == AudioLevel.floor)
        #expect(level.rms == AudioLevel.floor)
        #expect(level.isSilent)
        #expect(level.barFraction == 0)
    }

    @Test("An empty window reads as silence rather than dividing by zero")
    func emptyWindowIsSilent() {
        #expect(AudioLevel.measure([]) == .silent)
    }

    @Test("Full scale is 0 dBFS")
    func fullScaleIsZero() {
        let level = AudioLevel.measure([1, -1, 1, -1])
        #expect(abs(level.peak) < 0.001)
        #expect(abs(level.rms) < 0.001)
        #expect(level.isClipping)
        #expect(level.barFraction == 1)
    }

    @Test("Half amplitude is about −6 dBFS")
    func halfAmplitudeIsMinusSix() {
        let level = AudioLevel.measure([0.5, -0.5, 0.5, -0.5])
        #expect(abs(level.peak - -6.0206) < 0.01)
    }

    @Test("Peak follows the loudest sample, RMS follows the whole window")
    func peakAndRMSDiffer() {
        // One loud sample in an otherwise quiet window: the peak has to see it
        // and the average must not be dragged up to meet it, or the meter
        // jumps to full on a single cough.
        var samples = [Float](repeating: 0.001, count: 1000)
        samples[500] = 1.0

        let level = AudioLevel.measure(samples)
        #expect(abs(level.peak) < 0.001, "peak should be full scale")
        #expect(level.rms < -25, "one sample in a thousand must not fill the bar")
        #expect(level.peak > level.rms)
    }

    @Test("A negative sample counts by its magnitude")
    func peakUsesMagnitude() {
        #expect(AudioLevel.measure([-1, 0, 0, 0]).peak == AudioLevel.measure([1, 0, 0, 0]).peak)
    }

    @Test("A quiet room is silent, a voice is not")
    func silenceThresholdSitsUnderSpeech() {
        // The two cases the recording screen's "Silence · MacBook Pro
        // Microphone" has to tell apart. −65 dBFS is a quiet room's noise
        // floor; −25 dBFS is somebody talking at a normal distance.
        let room = AudioLevel.measure([Float](repeating: pow(10, -65 / 20), count: 256))
        let voice = AudioLevel.measure([Float](repeating: pow(10, -25 / 20), count: 256))

        #expect(room.isSilent)
        #expect(!voice.isSilent)
    }

    @Test("Clipping is reported only at the very top of the scale")
    func clippingIsNarrow() {
        #expect(AudioLevel.measure([1.0]).isClipping)
        #expect(!AudioLevel.measure([0.9]).isClipping)
    }

    @Test("The bar never leaves 0…1, whatever it is handed")
    func barStaysInRange() {
        for amplitude in [Float(0), 0.0001, 0.01, 0.5, 1.0] {
            let fraction = AudioLevel.measure([amplitude]).barFraction
            #expect(fraction >= 0 && fraction <= 1, "amplitude \(amplitude) gave \(fraction)")
        }
    }

    @Test("Louder always means a fuller bar")
    func barIsMonotonic() {
        let amplitudes: [Float] = [0.001, 0.01, 0.05, 0.2, 0.6, 1.0]
        let fractions = amplitudes.map { AudioLevel.measure([$0]).barFraction }
        #expect(fractions == fractions.sorted())
    }
}
