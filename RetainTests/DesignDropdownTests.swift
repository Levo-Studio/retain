import AppKit
import SwiftUI
import Testing

@testable import Retain

/// The picker's list is drawn in an `NSPanel`, which a test cannot open. What a
/// test can do is everything that decides *which* row is chosen — the arrow
/// keys, Return, and a list with nothing in it — which is where a dropdown goes
/// wrong.
@Suite("Design dropdown")
struct DesignDropdownTests {

    // MARK: - Where it starts

    @Test("It opens on the row the field already holds")
    func opensOnTheSelection() {
        let highlight = RetainDropdownHighlight(count: 5, selected: 3)
        #expect(highlight.index == 3)
        #expect(highlight.chosen == 3)
    }

    @Test("With nothing chosen it opens on no row at all")
    func opensOnNothing() {
        let highlight = RetainDropdownHighlight(count: 5)
        #expect(highlight.index == nil)
        #expect(highlight.chosen == nil)
    }

    /// The course field is bound by id and the input picker by UID, and both
    /// can hold a value that is no longer in the list — a course deleted in the
    /// library, a headset unplugged. Highlighting row zero for it would make
    /// Return choose something the user never pointed at.
    @Test("A selection outside the list highlights nothing")
    func selectionOutsideTheList() {
        #expect(RetainDropdownHighlight(count: 3, selected: 7).index == nil)
        #expect(RetainDropdownHighlight(count: 3, selected: -1).index == nil)
    }

    // MARK: - The arrow keys

    @Test("Down from nothing lands on the first row, up on the last")
    func arrowsFromNothing() {
        var down = RetainDropdownHighlight(count: 4)
        down.moveDown()
        #expect(down.index == 0)

        var up = RetainDropdownHighlight(count: 4)
        up.moveUp()
        #expect(up.index == 3)
    }

    @Test("Down walks the list one row at a time")
    func downWalks() {
        var highlight = RetainDropdownHighlight(count: 3, selected: 0)
        highlight.moveDown()
        #expect(highlight.index == 1)
        highlight.moveDown()
        #expect(highlight.index == 2)
    }

    @Test("Neither end wraps")
    func endsHold() {
        var bottom = RetainDropdownHighlight(count: 3, selected: 2)
        bottom.moveDown()
        bottom.moveDown()
        #expect(bottom.index == 2)

        var top = RetainDropdownHighlight(count: 3, selected: 0)
        top.moveUp()
        top.moveUp()
        #expect(top.index == 0)
    }

    @Test("A term picker twenty half-years long is still walked one row at a time")
    func longList() {
        var highlight = RetainDropdownHighlight(count: 20, selected: 19)
        for _ in 0..<19 { highlight.moveUp() }
        #expect(highlight.index == 0)
    }

    // MARK: - The pointer

    @Test("The pointer moves the same highlight the keyboard does")
    func pointerTakesOver() {
        var highlight = RetainDropdownHighlight(count: 4, selected: 0)
        highlight.moveDown()
        highlight.move(to: 3)
        #expect(highlight.chosen == 3)

        // Off the end of the list is nothing, not the nearest row: the pointer
        // leaving the list must not leave Return pointing somewhere.
        highlight.move(to: 9)
        #expect(highlight.chosen == nil)
    }

    // MARK: - An empty list

    /// The settings model picker with LM Studio unreachable, the input picker
    /// with no microphone, the course field in a term with no courses. All
    /// three are disabled, and none of them may choose anything if it is
    /// reached anyway.
    @Test("An empty list highlights nothing and chooses nothing")
    func emptyList() {
        var highlight = RetainDropdownHighlight(count: 0, selected: 0)
        #expect(highlight.index == nil)

        highlight.moveDown()
        #expect(highlight.index == nil)

        highlight.moveUp()
        #expect(highlight.index == nil)

        highlight.move(to: 0)
        #expect(highlight.chosen == nil)
    }

    @Test("A negative count is an empty list rather than a crash")
    func negativeCount() {
        var highlight = RetainDropdownHighlight(count: -4)
        highlight.moveDown()
        #expect(highlight.count == 0)
        #expect(highlight.chosen == nil)
    }

    // MARK: - The values the list is drawn with

    /// The four numbers the export does not draw. They are derived from ones it
    /// does, and the derivation is the test: a card padding that is not the
    /// difference between the two radii draws two corners that do not match.
    @Test("The card's padding leaves the row's corner concentric with the card's")
    func cardPadding() {
        #expect(RetainMetrics.dropdownCardPadding
                == RetainMetrics.radiusDialog - RetainMetrics.radiusSidebarRow)
    }

    @Test("The list is never wider than a dialog")
    func maxWidth() {
        #expect(RetainMetrics.dropdownMaxWidth == RetainMetrics.dialogWidth)
    }

    @Test("The cap is the eight rows it was derived from")
    func maxHeight() {
        // A row is the field's 13-point text — a 16-point line box — inside the
        // settings sidebar row's vertical padding.
        let row = 16 + RetainMetrics.sidebarRowSettings.top + RetainMetrics.sidebarRowSettings.bottom
        let eight = row * 8
            + RetainMetrics.sidebarRowGap * 7
            + RetainMetrics.dropdownCardPadding * 2

        // Within a point: the constant is taken up to 288 so that the ninth row
        // is cut rather than flush.
        #expect(RetainMetrics.dropdownMaxHeight >= eight)
        #expect(RetainMetrics.dropdownMaxHeight - eight <= 1)
    }

    @Test("The list hangs off the field rather than sitting on it")
    func anchorGap() {
        #expect(RetainMetrics.dropdownAnchorGap > RetainMetrics.sidebarRowGap)
        #expect(RetainMetrics.dropdownAnchorGap < RetainMetrics.titleBarGap)
    }

    // MARK: - The panel it is drawn in

    /// Placement is arithmetic over the field's frame and the screen's, and it
    /// is the arithmetic that decides whether the list is under the field or
    /// somewhere near it. Cheap to assert, and invisible in a screenshot.
    @Test("The list opens under the field, at least as wide as it is")
    func opensUnderTheField() throws {
        let (window, anchor) = try fieldInAWindow()
        defer { window.orderOut(nil) }

        let controller = RetainDropdownController()
        controller.titles = ["Third year, winter", "Third year, summer", "Fourth year, winter"]
        controller.selected = 1
        controller.open(under: anchor)
        defer { controller.dismiss() }

        #expect(controller.isOpen)

        let field = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let card = controller.cardFrame

        #expect(abs(card.maxY - (field.minY - RetainMetrics.dropdownAnchorGap)) < 1)
        #expect(abs(card.minX - field.minX) < 1)
        #expect(card.width >= field.width)
        #expect(card.height > 0)
    }

    /// The reason the cap exists: a term picker that has run for ten years.
    @Test("Twenty half-years are capped rather than running off the screen")
    func longListIsCapped() throws {
        let (window, anchor) = try fieldInAWindow()
        defer { window.orderOut(nil) }

        let controller = RetainDropdownController()
        controller.titles = (1...20).map { "Half-year \($0)" }
        controller.open(under: anchor)
        defer { controller.dismiss() }

        #expect(controller.isOpen)
        #expect(controller.cardFrame.height <= RetainMetrics.dropdownMaxHeight)
        #expect(controller.cardFrame.height > 0)
    }

    @Test("A field with nothing to offer opens nothing")
    func emptyListDoesNotOpen() throws {
        let (window, anchor) = try fieldInAWindow()
        defer { window.orderOut(nil) }

        let controller = RetainDropdownController()
        controller.titles = []
        controller.open(under: anchor)

        #expect(!controller.isOpen)
    }

    // MARK: - Rendering it

    /// Lays the card out the way `SettingsSnapshotTests` lays the boards out:
    /// to catch a list that cannot lay itself out at all, and to write the PNG
    /// the owner checks by eye when `RETAIN_SNAPSHOT_DIR` is set.
    @Test("The open list lays out and draws")
    func listRenders() throws {
        let list = RetainDropdownList(
            titles: ["Third year, winter", "Third year, summer", "Fourth year, winter"],
            selected: 0,
            highlighted: 2,
            height: nil,
            minWidth: 220,
            highlight: { _ in },
            choose: { _ in }
        )

        let hosting = NSHostingView(rootView: list)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        // The card plus the margin the shadow needs on every side.
        let margin = RetainMetrics.dialogShadow.extent * 2
        #expect(hosting.frame.width >= 220 + margin)
        #expect(hosting.frame.height > margin)

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let directory = ProcessInfo.processInfo.environment["RETAIN_SNAPSHOT_DIR"],
              let data = rep.representation(using: .png, properties: [:]) else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("dropdown.png"))
    }

    // MARK: -

    /// A 200-point field in a window in the middle of the screen, which is the
    /// one place a dropdown has room both under it and over it.
    private func fieldInAWindow() throws -> (NSWindow, NSView) {
        let visible = try #require(NSScreen.main).visibleFrame
        let window = NSWindow(
            contentRect: NSRect(x: visible.midX - 150, y: visible.midY, width: 300, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let anchor = NSView(frame: NSRect(x: 20, y: 60, width: 200, height: 24))
        window.contentView?.addSubview(anchor)
        window.orderFront(nil)
        return (window, anchor)
    }
}
