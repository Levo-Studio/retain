import SwiftUI

// MARK: - What the meter is showing

/// The three ways the export draws the bar meter.
///
/// Not three colour schemes so much as three answers to "is anything being
/// recorded right now": the accent ramp means yes, the flat grey means the
/// microphone is open and the room is quiet, and the darker flat grey means the
/// recording is paused and the bars are history rather than signal.
nonisolated enum RetainMeterAppearance: Sendable, Equatable, CaseIterable {
    /// Board 01's title bar and board 02's running state.
    case live
    /// Board 02's ready state — "Silence · MacBook Pro Microphone".
    case idle
    /// Board 02's paused state.
    case paused
}

// MARK: - The history behind it

/// The last `capacity` level readings, oldest first.
///
/// A value type rather than state inside the view, so the thing the meter is a
/// picture of can be tested without drawing anything. It is deliberately not a
/// buffer of audio: the level arrives already measured, roughly ten times a
/// second, and what the meter needs is the shape of the last couple of seconds
/// of it.
nonisolated struct RetainLevelHistory: Sendable, Equatable {

    private(set) var fractions: [Double]

    let capacity: Int

    /// Starts flat, which is what an empty meter looks like before the
    /// microphone has said anything.
    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.fractions = Array(repeating: 0, count: self.capacity)
    }

    /// Pushes one reading in at the newest end and drops the oldest.
    mutating func record(_ fraction: Double) {
        fractions.removeFirst()
        fractions.append(min(1, max(0, fraction)))
    }

    /// The newest reading, which is the one the bar at the right shows.
    var newest: Double { fractions.last ?? 0 }
}

// MARK: - The meter

/// The bar meter the export draws in three places: the recording window's title
/// bar, the popover's running and paused headers, and the popover's ready state.
///
/// **How a live level becomes bar heights is not drawn.** The export is a still
/// picture of a meter, with each bar's height written out as a literal, so the
/// geometry is exact and the rule behind it is not in the file. What is here is
/// the narrowest rule that reproduces every bar the export draws: the bars are a
/// rolling history of the measured level, newest at the right, and the colour of
/// a bar depends on how far it is from the middle of the coloured group rather
/// than on how tall it is.
///
/// One bar of the export disagrees with that by one step — the last bar of the
/// title-bar meter is `accent4` where the matching bar of the popover meter is
/// `accent3`. The popover's reading is the one taken, because it is the meter
/// drawn with seventeen bars and therefore the one that shows the ramp.
struct RetainLevelMeter: View {

    /// The level as the recorder last measured it. `nil` while nothing is being
    /// recorded, which leaves the meter flat.
    var level: AudioLevel?

    var barCount: Int
    var height: CGFloat
    var appearance: RetainMeterAppearance

    @State private var history: RetainLevelHistory

    init(
        level: AudioLevel?,
        barCount: Int,
        height: CGFloat,
        appearance: RetainMeterAppearance
    ) {
        self.level = level
        self.barCount = barCount
        self.height = height
        self.appearance = appearance
        _history = State(initialValue: RetainLevelHistory(capacity: barCount))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: RetainMetrics.waveformBarGap) {
            ForEach(Array(history.fractions.enumerated()), id: \.offset) { index, fraction in
                RoundedRectangle(cornerRadius: RetainMetrics.radiusWaveformBar)
                    .fill(Self.colour(atIndex: index, of: barCount, appearance: appearance))
                    .frame(
                        width: RetainMetrics.waveformBarWidth,
                        height: Self.barHeight(for: fraction, in: height)
                    )
            }
        }
        .frame(height: height, alignment: .bottom)
        .onChange(of: level) { _, new in
            history.record(Double(new?.barFraction ?? 0))
        }
        .accessibilityHidden(true)
    }

    // MARK: - The rule

    /// How many bars at the newest end carry the accent ramp.
    ///
    /// Five, in both meters the export colours: the title bar colours all five
    /// of its bars, and the popover colours the last five of seventeen.
    static let colouredBarCount = 5

    /// A bar is never shorter than it is wide.
    ///
    /// **Not a drawn value.** A rounded rect of zero height disappears
    /// altogether, and a meter that empties out reads as a microphone that has
    /// stopped working rather than as a room that has gone quiet. One bar width
    /// is the smallest mark that still reads as a bar.
    static var minimumBarHeight: CGFloat { RetainMetrics.waveformBarWidth }

    static func barHeight(for fraction: Double, in height: CGFloat) -> CGFloat {
        max(minimumBarHeight, height * min(1, max(0, fraction)))
    }

    /// The ramp, from the middle of the coloured group outwards.
    static let ramp: [Color] = [
        RetainPalette.accent,
        RetainPalette.accentStep2,
        RetainPalette.accentStep3,
        RetainPalette.accentStep4,
    ]

    static func colour(atIndex index: Int, of count: Int, appearance: RetainMeterAppearance) -> Color {
        switch appearance {
        case .paused:
            return RetainPalette.waveformBarPaused
        case .idle:
            return RetainPalette.waveformBarIdle
        case .live:
            break
        }

        let firstColoured = max(0, count - colouredBarCount)
        guard index >= firstColoured else {
            // The one bar in front of the coloured group is a step lighter than
            // the rest of the history, which is what stops the ramp beginning
            // abruptly against flat grey.
            return index == firstColoured - 1
                ? RetainPalette.waveformBarRecent
                : RetainPalette.waveformBarIdle
        }

        let centre = firstColoured + (count - firstColoured - 1) / 2
        return ramp[min(ramp.count - 1, abs(index - centre))]
    }
}
