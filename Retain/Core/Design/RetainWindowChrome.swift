import SwiftUI

// MARK: - The window itself

/// The `.win` box every board is drawn inside: the body colour, the border, the
/// 11px corner and the shadow under it.
struct RetainWindowFrame<Content: View>: View {

    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(RetainPalette.surfaceWindow)
            .clipShape(RoundedRectangle(cornerRadius: RetainMetrics.radiusWindow, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: RetainMetrics.radiusWindow, style: .continuous)
                    .strokeBorder(RetainPalette.lineWindowBorder, lineWidth: 1)
            }
            .shadow(
                color: RetainMetrics.windowShadow.color,
                radius: RetainMetrics.windowShadow.radius,
                y: RetainMetrics.windowShadow.offsetY
            )
    }
}

// MARK: - Traffic lights

/// The three 10px circles at the leading end of every title bar.
///
/// The export draws them flat and grey — they are a picture of a window, not
/// the system's own buttons. A real window puts `NSWindow`'s buttons in the
/// same place; this is what stands in for them wherever the board is drawn
/// without one, and what keeps the title bar's spacing honest either way.
struct RetainTrafficLights: View {

    var body: some View {
        HStack(spacing: RetainMetrics.titleBarGap) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(RetainPalette.lineTrafficLight)
                    .frame(width: RetainMetrics.trafficLightDiameter, height: RetainMetrics.trafficLightDiameter)
            }
        }
    }
}

// MARK: - The bar

/// `.tb` — 38 points tall, the window's own title in the middle of it, and
/// whatever the board puts at the trailing end.
struct RetainTitleBar<Trailing: View>: View {

    let title: String

    @ViewBuilder var trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            RetainTrafficLights()

            Text(verbatim: title)
                .retainStyle(RetainTypography.titleBarSubtitle)
                .foregroundStyle(RetainPalette.inkDim)
                .padding(.leading, RetainMetrics.titleBarGap + RetainMetrics.titleBarTitleGap)
                .lineLimit(1)

            Spacer(minLength: RetainMetrics.titleBarTitleGap)

            HStack(spacing: RetainMetrics.titleBarTrailingGap) { trailing }
        }
        .padding(RetainMetrics.titleBarPadding)
        .frame(height: RetainMetrics.titleBarHeight)
        .background(RetainPalette.surfaceTitleBar)
        .overlay(alignment: .bottom) { RetainDivider() }
    }
}

extension RetainTitleBar where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Rules

/// The hairline under a title bar, a meta strip or a tab bar, and down the edge
/// of a rail. One point, `#24282e`.
struct RetainDivider: View {

    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(RetainPalette.lineDivider)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .horizontal ? 1 : nil
            )
    }
}

// MARK: - A surface that answers the pointer

/// The one button style in Retain.
///
/// The export draws no hover, no pressed state and no focus ring — see
/// `RetainInteraction`, which derives all three from the two hover colours the
/// design does give. This is where that derivation reaches a control, so a row
/// in the library, a chapter in the rail and the Export button all answer the
/// pointer the same way instead of three times differently.
struct RetainSurfaceButtonStyle: ButtonStyle {

    /// The fill at rest. `nil` for a control the export draws with no fill of
    /// its own — a table row, a chapter — which still has to light up under the
    /// pointer to read as something that can be clicked.
    var resting: RetainColor?

    var cornerRadius: CGFloat = 0
    var border: Color?

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, resting: resting, cornerRadius: cornerRadius, border: border)
    }

    private struct Surface: View {

        let configuration: Configuration
        let resting: RetainColor?
        let cornerRadius: CGFloat
        let border: Color?

        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        }

        var body: some View {
            configuration.label
                .background { shape.fill(fill) }
                .overlay {
                    if let border { shape.strokeBorder(border, lineWidth: 1) }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : RetainInteraction.disabledOpacity)
                .onHover { isHovering = $0 && isEnabled }
        }

        private var fill: Color {
            let base = resting ?? RetainPalette.selectedRowSwatch

            if configuration.isPressed { return RetainInteraction.pressed(base).color }
            if isHovering { return resting.map { RetainInteraction.hovered($0).color } ?? base.color }
            return resting?.color ?? .clear
        }
    }
}

// MARK: - Columns that are not equal

/// A row of columns with `fr` weights, as CSS grid writes them — the meta
/// strip's `1.6fr 1fr 1fr`.
///
/// `HStack` with `maxWidth: .infinity` divides a row evenly and there is no
/// modifier for an uneven division, so the proportion the export draws needs a
/// layout of its own rather than a fudged frame width.
struct RetainWeightedColumns: Layout {

    let weights: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
        let heights = widths(in: width, subviews: subviews).enumerated().map { index, columnWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: proposal.height)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        for (index, columnWidth) in widths(in: bounds.width, subviews: subviews).enumerated() {
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: columnWidth, height: bounds.height)
            )
            x += columnWidth
        }
    }

    private func widths(in total: CGFloat, subviews: Subviews) -> [CGFloat] {
        let used = Array(weights.prefix(subviews.count))
        let sum = used.reduce(0, +)
        guard sum > 0 else { return Array(repeating: total / CGFloat(max(1, subviews.count)), count: subviews.count) }
        return used.map { total * $0 / sum }
    }
}

/// A row of columns where some have a width and one does not — the library
/// table's `1fr 120px 96px 84px`.
///
/// `nil` is the `1fr`: it takes whatever the fixed columns leave. Using a
/// layout rather than a frame on each cell is what keeps the header row and the
/// body rows on the same column edges, since both are built from this and
/// neither can drift.
struct RetainFixedColumns: Layout {

    /// One entry per column. `nil` takes the remaining width.
    let columns: [CGFloat?]
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 0
        let heights = widths(in: total, count: subviews.count).enumerated().map { index, width in
            subviews[index].sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        }
        return CGSize(width: total, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (index, width) in widths(in: bounds.width, count: subviews.count).enumerated() {
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func widths(in total: CGFloat, count: Int) -> [CGFloat] {
        let used = Array(columns.prefix(count))
        let gaps = spacing * CGFloat(max(0, count - 1))
        let fixed = used.compactMap { $0 }.reduce(0, +)
        let flexibleCount = used.filter { $0 == nil }.count
        let remaining = max(0, total - gaps - fixed)
        let each = flexibleCount > 0 ? remaining / CGFloat(flexibleCount) : 0
        return used.map { $0 ?? each }
    }
}
