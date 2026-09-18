import AppKit
import SwiftUI

/// A panel that takes keyboard focus without activating Polish, so the source app stays frontmost
/// and its selection stays selected while the user reads the rewrite.
final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows one popover at a time, positioned under the selection.
@MainActor
enum PopoverController {
    private static var panel: PopoverPanel?

    static func show(selection: Selection, run action: Action? = nil) {
        close()

        let model = model(for: selection)
        if let action { model.run(action) }
        present(model, near: selection)
    }

    /// A per-action shortcut (T3.2): run the action and replace the selection with no popover at
    /// all, then let the undo toast confirm it. The popover only appears when the run cannot be
    /// silent — the selection is over budget, generation failed, or the paste-back did.
    static func runSilently(selection: Selection, action: Action) async {
        close()

        let model = model(for: selection)
        await model.loadEstimate()
        guard model.estimate?.allowsSilentRun(action) ?? true else {
            model.run(action)
            present(model, near: selection)
            return
        }

        model.run(action)
        await model.wait()
        guard case .result = model.phase else {
            present(model, near: selection)
            return
        }

        await model.replaceAndWait()
        // `onReplaced` showed the toast; anything else is a write-back failure worth a pane.
        if case .failed = model.phase { present(model, near: selection) }
    }

    private static func model(for selection: Selection) -> PopoverModel {
        let model = PopoverModel(selection: selection)
        model.onClose = { close() }
        model.onReplaced = {
            close()
            UndoToast.show(near: selection)
        }
        return model
    }

    private static func present(_ model: PopoverModel, near selection: Selection) {
        present(PopoverView(model: model), near: selection, fallbackSize: NSSize(width: 460, height: 320))
    }

    /// Shows a failure that happened before there was a popover — capture, or an undo that could
    /// not be pasted. Positioned at the mouse, because there is no selection to sit under.
    static func show(error: UserFacingError, near selection: Selection? = nil) {
        close()

        let pane = ErrorPane(
            error: error,
            perform: { remedy in
                switch remedy {
                case .accessibilitySettings:
                    AccessibilityPermission.openSettingsPane()
                case .intelligenceSettings:
                    SettingsPane.openAppleIntelligence()
                case .retry, .copyOriginal, .copyResult, .dismiss:
                    // Nothing to retry or copy out here: the action never started, or the text
                    // it would hand back is already where the user left it.
                    break
                }
                close()
            },
            onClose: close
        )
        .padding(14)
        .frame(width: 360)

        present(pane, near: selection, fallbackSize: NSSize(width: 360, height: 120))
    }

    private static func present(
        _ content: some View,
        near selection: Selection?,
        fallbackSize: NSSize
    ) {
        let panel = PopoverPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)
        panel.setContentSize(panel.contentView?.fittingSize ?? fallbackSize)
        panel.setFrameTopLeftPoint(topLeft(for: selection, size: panel.frame.size))
        panel.makeKeyAndOrderFront(nil)

        Self.panel = panel
    }

    static func close() {
        panel?.close()
        panel = nil
    }

    /// Top-left corner for a panel: just below the selection, or the mouse when the app does not
    /// report bounds. AX rects use a top-left screen origin, AppKit a bottom-left one.
    /// Shared with the undo toast, which appears where the popover was.
    static func topLeft(for selection: Selection?, size: NSSize) -> NSPoint {
        guard let bounds = selection?.bounds, let primary = NSScreen.screens.first else {
            let mouse = NSEvent.mouseLocation
            return NSPoint(x: mouse.x, y: mouse.y)
        }

        let point = NSPoint(x: bounds.minX, y: primary.frame.maxY - bounds.maxY - 8)
        return clamped(point, size: size)
    }

    /// Keeps the whole panel on the screen it lands on.
    private static func clamped(_ point: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let frame = screen.visibleFrame

        let x = min(max(point.x, frame.minX), frame.maxX - size.width)
        // `point` is the top-left corner, so the bottom edge is point.y − height.
        let y = min(max(point.y, frame.minY + size.height), frame.maxY)
        return NSPoint(x: x, y: y)
    }
}
