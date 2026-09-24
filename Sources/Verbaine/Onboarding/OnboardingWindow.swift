import AppKit
import SwiftUI

/// Shows the onboarding window, at most one at a time.
///
/// A non-activating panel, like the popover: the Accessibility step's Test button has to read
/// the selection in the user's app, which only works while that app is still frontmost.
@MainActor
enum OnboardingWindow {
    private static var panel: NSPanel?

    /// Shows onboarding unless the user has already finished it. Called at launch.
    static func showIfNeeded() {
        guard !OnboardingFlag.isComplete() else { return }
        show()
    }

    static func show() {
        close()

        let model = OnboardingModel()
        model.onFinish = { close() }

        let panel = PopoverPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Verbaine"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: OnboardingView(model: model))
        panel.setContentSize(NSSize(width: Tokens.Size.onboarding.width, height: Tokens.Size.onboarding.height))
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        Self.panel = panel
    }

    static func close() {
        panel?.close()
        panel = nil
    }
}
