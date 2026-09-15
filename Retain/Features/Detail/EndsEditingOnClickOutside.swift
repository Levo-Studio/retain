import AppKit
import SwiftUI

/// Ends an edit when the pointer goes somewhere else.
///
/// **A text field does not lose focus just because somebody clicked away from
/// it.** AppKit only moves first responder when the click lands on something
/// that takes it, and most of a window takes nothing — the notes, the tab bar,
/// the empty half of the meta strip. So a field left open by clicking into the
/// transcript stayed open, still editable, still holding a draft nobody
/// intended to keep.
///
/// A local mouse monitor rather than a first-responder override, for the same
/// reason `RetainDropdown` uses one: the field is SwiftUI and the responder
/// chain under it belongs to the hosting view, so anything built on that chain
/// is a guess about somebody else's view. The monitor sees the event first, is
/// installed only while an edit is open, and **never swallows it** — clicking
/// away from a field should also do whatever was clicked on.
private struct EndsEditingOnClickOutside: ViewModifier {

    let isEditing: Bool
    let end: () -> Void

    /// Where the field is on screen, so a click inside it is left alone.
    @State private var fieldFrame: CGRect = .zero
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { @Sendable proxy in
                proxy.frame(in: .global)
            } action: { frame in
                fieldFrame = frame
            }
            .onChange(of: isEditing) { _, isOpen in
                isOpen ? watch() : stop()
            }
            .onDisappear(perform: stop)
    }

    private func watch() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { event in
            guard let window = event.window else { return event }

            // The field's frame is in SwiftUI's global space, which is the
            // window's content view flipped; the event's is AppKit's, whose
            // origin is the bottom left. Comparing them without turning one
            // into the other would end an edit whenever somebody clicked the
            // same distance from the *other* end of the window.
            let height = window.contentView?.bounds.height ?? window.frame.height
            let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)

            if !fieldFrame.contains(point) { end() }
            return event
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {

    /// Ends an edit when the next click lands anywhere but this view.
    func endsEditingOnClickOutside(isEditing: Bool, end: @escaping () -> Void) -> some View {
        modifier(EndsEditingOnClickOutside(isEditing: isEditing, end: end))
    }
}
