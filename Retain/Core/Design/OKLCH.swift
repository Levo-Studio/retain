import CoreGraphics
import Foundation
import SwiftUI

/// A colour written the way the design export writes it.
///
/// `docs/design/` mixes two spellings — `#0e1013` and `oklch(.78 .13 165)` —
/// and the README is explicit that **both are literal values, not
/// approximations of each other**. An `oklch()` therefore cannot be replaced by
/// the hex a browser happens to paint for it and copied in by eye; it has to be
/// converted, and the conversion has to be the real one.
///
/// The maths below is the reference transform from the CSS Color 4
/// specification, in the same order a browser runs it: polar Oklch to
/// rectangular Oklab, Oklab to the cone response LMS, LMS to linear sRGB, and
/// linear sRGB through the sRGB transfer function. The matrices are Björn
/// Ottosson's, quoted to the digits CSS Color 4 publishes them at.
///
/// Out-of-gamut values are clipped per channel. Every colour the export uses is
/// inside sRGB — the clip is there so a future value that is not cannot produce
/// a silently wrong channel somewhere far from here.
nonisolated struct OKLCH: Sendable, Equatable, Hashable {

    /// Perceptual lightness, 0…1. The export writes it as `.78`, not `78%`.
    let lightness: Double

    /// Chroma. Unbounded in principle, around 0…0.4 for sRGB.
    let chroma: Double

    /// Hue angle in degrees.
    let hue: Double

    let alpha: Double

    init(_ lightness: Double, _ chroma: Double, _ hue: Double, alpha: Double = 1) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
        self.alpha = alpha
    }

    // MARK: - Conversion

    /// The colour in sRGB, each channel 0…1, gamma-encoded — the numbers a hex
    /// triple holds.
    var sRGB: (red: Double, green: Double, blue: Double) {
        let radians = hue * .pi / 180
        let a = chroma * cos(radians)
        let b = chroma * sin(radians)

        // Oklab to the cube roots of the LMS cone responses.
        let lRoot = lightness + 0.3963377774 * a + 0.2158037573 * b
        let mRoot = lightness - 0.1055613458 * a - 0.0638541728 * b
        let sRoot = lightness - 0.0894841775 * a - 1.2914855480 * b

        let l = lRoot * lRoot * lRoot
        let m = mRoot * mRoot * mRoot
        let s = sRoot * sRoot * sRoot

        let linearRed = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let linearGreen = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let linearBlue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

        return (
            Self.gammaEncoded(linearRed),
            Self.gammaEncoded(linearGreen),
            Self.gammaEncoded(linearBlue)
        )
    }

    /// The sRGB transfer function, applied to a signed value so that a negative
    /// channel comes back negative and is visibly out of gamut rather than
    /// folded back into range.
    private static func gammaEncoded(_ channel: Double) -> Double {
        let magnitude = abs(channel)
        let sign: Double = channel < 0 ? -1 : 1
        if magnitude <= 0.0031308 {
            return sign * magnitude * 12.92
        }
        return sign * (1.055 * pow(magnitude, 1 / 2.4) - 0.055)
    }

    /// The eight-bit hex triple a browser would show in its inspector. Useful
    /// for checking a value against the export by eye; the app never rounds to
    /// it.
    var hexDescription: String { RetainColor(self).hexDescription }
}

// MARK: - The one colour type the design layer builds on

/// A resolved sRGB colour, kept as numbers so it can be compared, hashed and
/// asserted about. `RetainPalette` is built out of these and hands out `Color`.
nonisolated struct RetainColor: Sendable, Equatable, Hashable {

    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    /// `#rrggbb` as the export writes it: `RetainColor(hex: 0x0e1013)`.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    init(_ oklch: OKLCH) {
        let (red, green, blue) = oklch.sRGB
        self.init(red: red, green: green, blue: blue, alpha: oklch.alpha)
    }

    /// The same colour at a different opacity, for the one place the export
    /// writes `rgba(11,15,13,.72)`.
    func opacity(_ alpha: Double) -> RetainColor {
        RetainColor(red: red, green: green, blue: blue, alpha: self.alpha * alpha)
    }

    /// The eight-bit triple a browser would paint. The app never rounds to it;
    /// it is here so a value can be checked against the export's own renders.
    var hexDescription: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
