import AppKit
import SwiftUI

/// The window board 02 is drawn in.
///
/// An `NSPanel` rather than `MenuBarExtra`'s own window, for the reason the
/// locked decisions give: a `MenuBarExtra` cannot be opened programmatically
/// and therefore cannot have a hotkey.
///
/// `.nonactivatingPanel` with `canBecomeKey` overridden is the combination that
/// matters. Without the style mask, opening the popover pulls Retain in front
/// of whatever the user is reading in the middle of a lecture; without the
/// override, the annotation composer cannot be typed into, because a panel that
/// never becomes key never has a first responder.
@MainActor
final class PopoverPanel: NSPanel {

    init(content: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        isFloatingPanel = true
        // Above ordinary windows and below the menu itself, which is where a
        // menu-bar popover belongs — it must not be covered by the window it
        // was opened over.
        level = .statusBar
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The export draws the popover's own shadow, and the view carries it.
        // A second one from AppKit would sit under the transparent margin the
        // view leaves for it and draw a rectangle around nothing.
        hasShadow = false
        isMovable = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = content
        setContentSize(content.fittingSize)
    }

    override var canBecomeKey: Bool { true }

    /// Escape closes it, the way every transient window on this platform does.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    // MARK: - Placing it

    /// Puts the panel under a status item, clamped to the screen it is on.
    ///
    /// The card is inset inside the window by the shadow's reach, so the edge
    /// the user sees is not the window's edge: the inset is taken off again
    /// here, or the popover would hang visibly low and to the left of the item
    /// it belongs to.
    func present(under button: NSStatusBarButton) {
        guard let itemWindow = button.window else { return }

        let inset = RetainMetrics.popoverShadow.extent
        let anchor = itemWindow.convertPoint(toScreen: NSPoint(x: button.bounds.midX, y: 0))
        let size = contentView?.fittingSize ?? frame.size

        var origin = NSPoint(
            x: anchor.x - size.width / 2,
            y: anchor.y - size.height + inset
        )

        if let visible = itemWindow.screen?.visibleFrame {
            origin.x = min(max(visible.minX - inset, origin.x), visible.maxX - size.width + inset)
        }

        setContentSize(size)
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
    }
}
