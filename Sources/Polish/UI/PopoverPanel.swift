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

    static func show(selection: Selection) {
        close()

        let model = PopoverModel(selection: selection)
        model.onClose = { close() }

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
        panel.contentView = NSHostingView(rootView: PopoverView(model: model))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 460, height: 320))
        panel.setFrameTopLeftPoint(origin(for: selection, size: panel.frame.size))
        panel.makeKeyAndOrderFront(nil)

        Self.panel = panel
    }

    static func close() {
        panel?.close()
        panel = nil
    }

    /// Top-left corner for the panel: just below the selection, or the mouse when the app does not
    /// report bounds. AX rects use a top-left screen origin, AppKit a bottom-left one.
    private static func origin(for selection: Selection, size: NSSize) -> NSPoint {
        guard let bounds = selection.bounds, let primary = NSScreen.screens.first else {
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
