import AppKit
import SwiftUI

// MARK: - Sizes for a surface the export does not draw

/// **The export draws no open dropdown.** Board 06 draws the model and the
/// input field shut, board 05 the term pill, board 07 the two month fields, and
/// none of them is drawn with its list down.
///
/// So the list is built out of parts that *are* drawn — the dialog's surface,
/// border, radius and shadow; the sidebar row's selected fill, radius and
/// padding; the accent rail the library marks the current course with — and the
/// four numbers below, which have nowhere else to come from. Each says what it
/// was derived from. When the owner draws the dropdown, they are what changes.
nonisolated extension RetainMetrics {

    /// The card's own padding, around the rows.
    ///
    /// The card is drawn at the dialog's 13 and a row at the sidebar row's 8;
    /// 13 − 8 is the inset that leaves the two corners concentric, which is the
    /// only value that does not read as a mistake at the top left of the list.
    static let dropdownCardPadding: CGFloat = 5

    /// Between the field and the card hanging off it.
    ///
    /// One point more than the 3 between two rows of one list: the field and
    /// the list are two surfaces rather than two rows, and the gap has to say
    /// so without the list drifting away from what opened it.
    static let dropdownAnchorGap: CGFloat = 4

    /// How tall the list may get before it scrolls inside itself.
    ///
    /// Eight rows: a row is the field's 13-point text in the settings sidebar
    /// row's `8px 10px`, so 32 points, plus the 3 between rows and the card's
    /// own padding — 8 × 32 + 7 × 3 + 2 × 5 = 287. Taken to 288 so the ninth
    /// row is unmistakably cut off rather than sitting flush with the edge,
    /// which is what tells the eye the list goes on.
    ///
    /// A term picker in its tenth year would otherwise be taller than the
    /// screen. The panel clamps this further to the room the screen actually
    /// leaves above or below the field.
    static let dropdownMaxHeight: CGFloat = 288

    /// How wide the list may get where the field is narrower than the longest
    /// option — a model identifier in the settings picker runs well past the
    /// field it is chosen in.
    ///
    /// The dialog's width, which is the widest transient surface the export
    /// draws apart from the popover. Past it the list would read as a window
    /// rather than as something hanging off a field.
    static var dropdownMaxWidth: CGFloat { dialogWidth }
}

// MARK: - Which row the keyboard is on

/// The highlighted row of an open dropdown, and what the arrow keys do to it.
///
/// A value rather than state inside the view, because this is the part of a
/// dropdown that can be wrong: the arrow keys running off either end, Return
/// choosing a row that is not there, an empty list highlighting row zero. All
/// three are testable in microseconds here and not at all inside an `NSPanel`.
nonisolated struct RetainDropdownHighlight: Equatable, Sendable {

    /// How many rows the list has.
    let count: Int

    /// The row the keyboard is on, or none.
    private(set) var index: Int?

    /// Starts on the row that is already chosen, where there is one. A picker
    /// opened on its fifth option and driven straight down should reach the
    /// sixth, not the first.
    init(count: Int, selected: Int? = nil) {
        self.count = max(0, count)
        self.index = Self.valid(selected, in: self.count)
    }

    /// The row Return would choose. `nil` where nothing is highlighted, which
    /// includes every empty list.
    var chosen: Int? { index }

    /// Down from nothing lands on the first row; down from the last stays
    /// there.
    ///
    /// No wrapping, in either direction. A list long enough to scroll would
    /// jump from its bottom to its top under the pointer, and a list short
    /// enough not to gains nothing from it.
    mutating func moveDown() {
        guard count > 0 else { return }
        guard let index else {
            self.index = 0
            return
        }
        self.index = min(index + 1, count - 1)
    }

    /// Up from nothing lands on the last row; up from the first stays there.
    mutating func moveUp() {
        guard count > 0 else { return }
        guard let index else {
            self.index = count - 1
            return
        }
        self.index = max(index - 1, 0)
    }

    /// Where the pointer puts it. The pointer and the keyboard share one
    /// highlight, so Return always chooses what the eye is on.
    mutating func move(to index: Int?) {
        self.index = Self.valid(index, in: count)
    }

    private static func valid(_ index: Int?, in count: Int) -> Int? {
        guard let index, index >= 0, index < count else { return nil }
        return index
    }
}

// MARK: - The list

/// The card an open picker draws: one row per option, on the dialog's surface.
///
/// Every value in it is drawn somewhere in the export, only not together — see
/// the metrics above for the four that are not.
struct RetainDropdownList: View {

    let titles: [String]

    /// The option the field currently holds.
    let selected: Int?

    /// The row the keyboard or the pointer is on.
    let highlighted: Int?

    /// `nil` while the whole list fits. Once it does not, the height it has to
    /// fit in, and the rows scroll inside it.
    let height: CGFloat?

    /// At least as wide as the field it hangs off, so the two read as one
    /// control rather than as a card that happens to be near it.
    let minWidth: CGFloat

    let highlight: (Int?) -> Void
    let choose: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        card
            .frame(minWidth: minWidth, maxWidth: RetainMetrics.dropdownMaxWidth, alignment: .leading)
            .background(RetainPalette.surfaceWindow)
            .clipShape(RoundedRectangle(cornerRadius: RetainMetrics.radiusDialog))
            .overlay {
                RoundedRectangle(cornerRadius: RetainMetrics.radiusDialog)
                    .strokeBorder(RetainPalette.lineWindowBorder, lineWidth: RetainMetrics.borderWidth)
            }
            .shadow(
                color: RetainMetrics.dialogShadow.color,
                radius: RetainMetrics.dialogShadow.radius,
                y: RetainMetrics.dialogShadow.offsetY
            )
            // The window is larger than the card by the shadow's reach, or the
            // shadow is clipped at the window's edge. `RetainDropdownController`
            // takes the same inset off again when it places the panel.
            .padding(RetainMetrics.dialogShadow.extent)
    }

    // MARK: -

    /// A scroller only where one is needed.
    ///
    /// A `ScrollView` asked for its ideal height has none to give — it takes
    /// whatever it is offered — so a list that fits is laid out without one and
    /// the panel can size itself to the rows.
    @ViewBuilder
    private var card: some View {
        if let height {
            ScrollViewReader { proxy in
                ScrollView(.vertical) { rows }
                    .frame(height: height)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: highlighted) { _, row in
                        guard let row else { return }
                        withAnimation(RetainMotion.reveal(reduceMotion: reduceMotion)) {
                            proxy.scrollTo(row)
                        }
                    }
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: RetainMetrics.sidebarRowGap) {
            ForEach(titles.indices, id: \.self) { index in
                row(index)
            }
        }
        .padding(RetainMetrics.dropdownCardPadding)
    }

    private func row(_ index: Int) -> some View {
        Button {
            choose(index)
        } label: {
            HStack(spacing: RetainMetrics.librarySidebarRowGap) {
                mark(index)

                Text(verbatim: titles[index])
                    .retainStyle(RetainTypography.fieldText)
                    .foregroundStyle(index == selected ? RetainPalette.inkPrimary : RetainPalette.inkBody)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(RetainMetrics.sidebarRowSettings)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                index == highlighted ? RetainPalette.surfaceSelectedRow : .clear,
                in: RoundedRectangle(cornerRadius: RetainMetrics.radiusSidebarRow)
            )
        }
        // The style every other row in Retain answers the pointer with: no fill
        // at rest, the selected-row fill under the pointer, a step darker while
        // it is held.
        .buttonStyle(RetainSurfaceButtonStyle(resting: nil, cornerRadius: RetainMetrics.radiusSidebarRow))
        .onHover { isInside in
            // The pointer takes the highlight over from the keyboard rather
            // than drawing a second one beside it.
            if isInside { highlight(index) }
        }
        .accessibilityAddTraits(index == selected ? [.isSelected] : [])
        .id(index)
    }

    /// What says "this is the one the field holds".
    ///
    /// The accent rail the library draws down the left of the current course,
    /// at the size and radius it is drawn at — not a checkmark, because the
    /// export contains no checkmark and an SF Symbol would be the one glyph in
    /// Retain nobody chose. Every row reserves its width, so the titles line up
    /// whether or not anything is chosen.
    private func mark(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: RetainMetrics.radiusCourseColourRail)
            .fill(index == selected ? RetainPalette.accent : .clear)
            .frame(
                width: RetainMetrics.courseColourRail.width,
                height: RetainMetrics.courseColourRail.height
            )
            .accessibilityHidden(true)
    }
}

// MARK: - The window it is drawn in

/// A borderless panel holding one dropdown.
///
/// A window rather than an overlay for the reason `PopoverPanel` is one: a
/// SwiftUI overlay is clipped by whatever lays the field out, and a list opened
/// from the bottom row of a settings form, from a 38-point title bar or from a
/// 430-point sheet is taller than all three.
///
/// It is a **child window** of the window the field is in, so it travels with
/// that window and is ordered above it without having to know what level it
/// sits at.
@MainActor
final class RetainDropdownPanel: NSPanel {

    init(content: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The card carries the export's own shadow; a second one from AppKit
        // would land under the transparent margin left for it and draw a
        // rectangle around nothing.
        hasShadow = false
        isMovable = false
        // No opening animation: a list that fades in is a list whose first row
        // cannot be clicked yet.
        animationBehavior = .none
        // The two month fields of the name-term dialog are inside a sheet, and
        // a panel that stops working while one is up is a dropdown that cannot
        // be opened there.
        worksWhenModal = true
        collectionBehavior = [.transient, .fullScreenAuxiliary]

        contentView = content
    }

    /// Key, so the rows can be clicked and read by VoiceOver. The window the
    /// field is in gives up key for as long as the list is open, which is why
    /// anything that closes on resigning key has to allow for its own children.
    override var canBecomeKey: Bool { true }
}

// MARK: - Opening one

/// Owns the panel for one picker field: opens it under the field, keeps it in
/// step, and takes the keyboard and the pointer while it is up.
///
/// Not a view. A dropdown outlives several SwiftUI body passes and has to be
/// torn down exactly once, which is a lifetime an `NSViewRepresentable`
/// coordinator has and a view does not.
@MainActor
final class RetainDropdownController {

    /// What the list shows. Set on every update of the field that owns it.
    var titles: [String] = []
    var selected: Int?

    /// A row was picked. The field takes the option and shuts the list.
    var choose: (Int) -> Void = { _ in }

    /// The list shut itself — Escape, a click outside it, a row chosen — and
    /// the field has to know, so that its own state follows.
    var close: () -> Void = {}

    private var panel: RetainDropdownPanel?
    private var host: NSHostingView<RetainDropdownList>?
    private var highlight = RetainDropdownHighlight(count: 0)
    private var width: CGFloat = 0
    private var height: CGFloat?

    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var resignObserver: (any NSObjectProtocol)?

    var isOpen: Bool { panel?.isVisible == true }

    deinit {
        MainActor.assumeIsolated { tearDown() }
    }

    // MARK: - Opening and closing

    func open(under anchor: NSView) {
        guard !isOpen else {
            refresh()
            return
        }
        // An empty list has nothing to open. Every picker in Retain is disabled
        // while its options are empty, so this is the second line of defence
        // rather than the first.
        guard !titles.isEmpty, let parent = anchor.window else { return }

        highlight = RetainDropdownHighlight(count: titles.count, selected: selected)
        height = nil

        let host = NSHostingView(rootView: list())
        self.host = host

        let panel = RetainDropdownPanel(content: host)
        self.panel = panel

        place(panel, host: host, under: anchor, in: parent)

        parent.addChildWindow(panel, ordered: .above)
        panel.makeKey()

        watch(panel)
    }

    /// Shuts the list without telling the field — for the field's own way out,
    /// which already knows.
    func dismiss() {
        guard panel != nil else { return }
        tearDown()
    }

    /// Shuts the list and tells the field: every other way out.
    private func shut() {
        guard panel != nil else { return }
        tearDown()
        close()
    }

    private func tearDown() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        mouseMonitor = nil
        resignObserver = nil

        if let panel {
            // Cleared first: ordering the panel out makes it resign key, and
            // the observer for that must not find a panel to shut a second
            // time.
            self.panel = nil
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        host = nil
    }

    // MARK: - Placing it

    /// Sizes the panel to the rows and puts it under the field — or over it,
    /// where the field sits close enough to the bottom of the screen that a
    /// list under it would be a list nobody can read.
    private func place(
        _ panel: RetainDropdownPanel,
        host: NSHostingView<RetainDropdownList>,
        under anchor: NSView,
        in parent: NSWindow
    ) {
        let inset = RetainMetrics.dialogShadow.extent
        let gap = RetainMetrics.dropdownAnchorGap

        let field = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = (parent.screen ?? NSScreen.main)?.visibleFrame ?? field

        // The width the field wants, and the height the whole list would take
        // if nothing stopped it. Both come back with the shadow's margin in
        // them, because the view carries it.
        width = max(field.width, 0)
        host.rootView = list()
        let natural = host.fittingSize
        let cardWidth = natural.width - 2 * inset
        let wanted = natural.height - 2 * inset

        let below = field.minY - visible.minY - gap
        let above = visible.maxY - field.maxY - gap
        let opensBelow = below >= min(wanted, RetainMetrics.dropdownMaxHeight) || below >= above

        let cardHeight = min(wanted, RetainMetrics.dropdownMaxHeight, max(opensBelow ? below : above, 0))
        if cardHeight < wanted {
            height = cardHeight
            host.rootView = list()
        }

        var origin = CGPoint(
            x: field.minX,
            y: opensBelow ? field.minY - gap - cardHeight : field.maxY + gap
        )
        origin.x = min(max(visible.minX, origin.x), max(visible.maxX - cardWidth, visible.minX))

        panel.level = parent.level
        panel.setContentSize(CGSize(width: cardWidth + 2 * inset, height: cardHeight + 2 * inset))
        panel.setFrameOrigin(CGPoint(x: origin.x - inset, y: origin.y - inset))
    }

    /// The card inside the panel, in screen coordinates. The panel is larger by
    /// the shadow's reach, and a click in that margin is a click outside the
    /// list.
    ///
    /// Also what a test asks where the list ended up, since the panel itself
    /// says nothing about where its card sits inside it.
    var cardFrame: CGRect {
        guard let panel else { return .zero }
        let inset = RetainMetrics.dialogShadow.extent
        return panel.frame.insetBy(dx: inset, dy: inset)
    }

    // MARK: - Keeping it in step

    private func refresh() {
        guard let host else { return }
        if highlight.count != titles.count {
            highlight = RetainDropdownHighlight(count: titles.count, selected: selected)
        }
        host.rootView = list()
    }

    private func list() -> RetainDropdownList {
        RetainDropdownList(
            titles: titles,
            selected: selected,
            highlighted: highlight.index,
            height: height,
            minWidth: width,
            highlight: { [weak self] row in
                guard let self else { return }
                highlight.move(to: row)
                refresh()
            },
            choose: { [weak self] row in
                guard let self else { return }
                tearDown()
                choose(row)
            }
        )
    }

    // MARK: - The keyboard and the pointer

    /// Takes the keys the list answers to, and the click that closes it.
    ///
    /// Monitors rather than a first responder: the rows are SwiftUI and the
    /// panel's responder chain is whatever the hosting view decided, so a
    /// `keyDown` override is a guess about somebody else's view. A local
    /// monitor sees the event before any of that, and only while the list is
    /// open — it is installed here and removed in `tearDown`.
    private func watch(_ panel: RetainDropdownPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, isOpen else { return event }
            return handle(event)
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, isOpen else { return event }
            guard !cardFrame.contains(NSEvent.mouseLocation) else { return event }
            // Swallowed, the way an open menu swallows the click that dismisses
            // it — and it is also what makes a second click on the field close
            // the list rather than close and immediately reopen it.
            shut()
            return nil
        }

        // A click in another application, or anything else that takes the
        // keyboard away. The list is transient and goes with it.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shut() }
        }
    }

    /// Returns the event where the list does not want it, and `nil` where it
    /// has been answered.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.charactersIgnoringModifiers == Self.escape {
            shut()
            return nil
        }

        switch event.specialKey {
        case .downArrow:
            highlight.moveDown()
            refresh()
            return nil
        case .upArrow:
            highlight.moveUp()
            refresh()
            return nil
        case .carriageReturn, .enter, .newline:
            guard let row = highlight.chosen else {
                shut()
                return nil
            }
            tearDown()
            choose(row)
            return nil
        default:
            return event
        }
    }

    /// Escape is not one of `NSEvent.SpecialKey`, and its key code is a number
    /// that means nothing on its own.
    private static let escape = "\u{1b}"
}

// MARK: - The field's end of it

/// Sits behind a picker field, and is what its dropdown hangs from.
///
/// An `NSViewRepresentable` because the panel has to be positioned against a
/// real view in a real window, which is the one thing a SwiftUI view cannot
/// describe.
struct RetainDropdownAnchor: NSViewRepresentable {

    let isOpen: Bool
    let titles: [String]
    let selected: Int?
    let choose: (Int) -> Void
    let close: () -> Void

    func makeCoordinator() -> RetainDropdownController { RetainDropdownController() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let controller = context.coordinator
        controller.titles = titles
        controller.selected = selected
        controller.choose = choose
        controller.close = close

        // Out of the layout pass. Ordering a window in while SwiftUI is still
        // placing the view it hangs off re-enters layout, and the field has no
        // frame to be placed under yet.
        //
        // A `Task { @MainActor in }` rather than a hop through the main queue:
        // a closure written here is inferred `@MainActor`, and handing one of
        // those to a `@Sendable` parameter compiles a runtime isolation check
        // rather than rejecting it. See `DrainTimer` for where that trapped.
        Task { @MainActor in
            if isOpen {
                controller.open(under: nsView)
            } else {
                controller.dismiss()
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: RetainDropdownController) {
        coordinator.dismiss()
    }
}
