import AppKit
import Testing
@testable import Verbaine

/// Esc reaches the panel as `cancelOperation:`, not as a SwiftUI `onExitCommand` — that only fires
/// when a SwiftUI element has focus, and the popover's plain-style tiles never take it.
@MainActor
struct EscapeTests {
    @Test func panelForwardsCancelOperation() {
        let panel = PopoverPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        var cancelled = 0
        panel.onCancel = { cancelled += 1 }
        panel.cancelOperation(nil)
        #expect(cancelled == 1)
    }

    @Test func escapeClosesToneRowBeforePopover() {
        let model = PopoverModel(selection: Selection(text: "hello", bounds: nil, appBundleID: nil, element: nil, source: .clipboard))
        var closed = 0
        model.onClose = { closed += 1 }

        model.isPickingTone = true
        model.escape()
        #expect(!model.isPickingTone)
        #expect(closed == 0)

        model.escape()
        #expect(closed == 1)
    }
}
