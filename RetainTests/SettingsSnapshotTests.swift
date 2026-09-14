import AppKit
import SwiftUI
import Testing

@testable import Retain

/// Renders board 06 and board 07 offscreen.
///
/// Two things this is for, and one it is not. It catches a pane that cannot lay
/// itself out at all — a constraint loop, a crash in a `Grid`, a view that draws
/// nothing — which is the failure a unit test over the logic cannot see. And
/// with `RETAIN_SNAPSHOT_DIR` set it writes the PNGs, which is how a render is
/// checked against `docs/design/screens/` by eye.
///
/// It is **not** a pixel comparison. There is no committed reference image and
/// no tolerance: a screenshot diff over a whole window fails on a font update
/// and tells nobody anything about the design.
@Suite("Settings and dialog rendering")
struct SettingsSnapshotTests {

    @Test("The settings window lays out at the size the board draws")
    func settingsWindowRenders() throws {
        let model = SettingsModel()
        let image = try render(SettingsView(model: model), size: RetainMetrics.detailWindowSize)
        try write(image, named: "06-settings")

        #expect(image.size.width == RetainMetrics.detailWindowSize.width)
        #expect(image.size.height == RetainMetrics.detailWindowSize.height)
    }

    @Test("Every dialog lays out at 430 wide")
    func dialogsRender() throws {
        for (name, view) in Self.dialogs {
            let image = try render(view, size: nil)
            try write(image, named: name)
            #expect(image.size.width == RetainMetrics.dialogWidth)
            #expect(image.size.height > 0)
        }
    }

    // MARK: - The four

    @MainActor
    static var dialogs: [(String, AnyView)] {
        [
            ("07-microphone", AnyView(MicrophonePermissionDialog(allow: {}, later: {}))),
            ("07-new-course", AnyView(NewCourseDialog(
                terms: [Term(id: 1, title: "Third year, winter", startsOn: .now, endsOn: .now)],
                draft: CourseDraft(name: "Computer networks", termID: 1),
                create: { _ in },
                cancel: {}
            ))),
            ("07-name-term", AnyView(NameTermDialog(
                terms: [],
                draft: TermDraft(title: "Third year, winter", startsOn: .now, endsOn: .now, isCurrent: true),
                save: { _ in },
                cancel: {}
            ))),
            ("07-no-connection", AnyView(LanguageModelUnreachableDialog(
                address: LMStudioEndpoint.defaultBaseAddress,
                retry: {},
                openSettings: {}
            ))),
        ]
    }

    // MARK: - Rendering

    /// An `NSHostingView` in a real window rather than `ImageRenderer`, because
    /// a `ScrollView` has no content until it has been laid out in a window and
    /// renders as an empty rectangle otherwise.
    private func render(_ view: some View, size: CGSize?) throws -> NSImage {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)

        let fitted = size ?? hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: fitted)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        let image = NSImage(size: fitted)
        image.addRepresentation(rep)
        return image
    }

    private func write(_ image: NSImage, named name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["RETAIN_SNAPSHOT_DIR"] else { return }
        guard let rep = image.representations.first as? NSBitmapImageRep,
              let data = rep.representation(using: .png, properties: [:]) else { return }

        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
