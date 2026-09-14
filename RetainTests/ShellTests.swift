import Testing
import AppKit

@testable import Retain

/// Phase 1 has one thing worth asserting, and it is not the status item: it is
/// that the power hint survived into the built bundle. It is a plain string in
/// Info.plist with nothing to catch a typo or a stray edit, and it is the
/// difference between a wakeup every 32 ms and every 256 ms for a whole school
/// day. See the comment above the key in Retain/Info.plist.
@Suite("Bundle")
struct BundleTests {

    @Test("The audio power hint is in the built bundle")
    func powerHintIsPresent() throws {
        let bundle = Bundle(for: RetainApp.self)
        let hint = bundle.object(forInfoDictionaryKey: "AudioHardwarePowerHint") as? String
        #expect(hint == "Favor Saving Power")
    }

    @Test("Retain is not an agent — it has a Dock tile")
    func isNotAnAgent() throws {
        // LSUIElement hides an app from the Dock and from ⌘-Tab. Retain has
        // four windows; it does not want that.
        let bundle = Bundle(for: RetainApp.self)
        #expect(bundle.object(forInfoDictionaryKey: "LSUIElement") == nil)
    }
}
