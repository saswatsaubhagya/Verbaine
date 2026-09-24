import AppKit
import SwiftUI

/// A panel that takes keyboard focus without activating Verbaine, so the source app stays frontmost
/// and its selection stays selected while the user reads the rewrite.
final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Esc. AppKit turns it into `cancelOperation:` on the responder chain, and SwiftUI's
    /// `onExitCommand` only picks that up when one of its own elements has focus — the popover's
    /// plain-style tiles never do, so the key ends here at the window instead.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// AppKit keeps a window clear of the menu bar but not of the Dock, and a borderless panel is
    /// positioned by its origin, which skips the constraint entirely. Every resize runs through
    /// here, so the popover can never grow down behind the Dock.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = (screen ?? self.screen ?? NSScreen.main)?.visibleFrame else {
            return frameRect
        }
        var rect = frameRect
        rect.size.width = min(rect.width, visible.width)
        rect.size.height = min(rect.height, visible.height)
        rect.origin.x = min(max(rect.minX, visible.minX), visible.maxX - rect.width)
        rect.origin.y = min(max(rect.minY, visible.minY), visible.maxY - rect.height)
        return rect
    }
}

/// Shows one popover at a time, positioned under the selection.
@MainActor
enum PopoverController {
    private static var panel: PopoverPanel?
    /// Where the panel's top-left was put. The panel grows downward as the popover moves from the
    /// 320 pt action step to the 560 pt result, and AppKit resizes from the bottom-left, so every
    /// size change re-pins to this point.
    private static var anchor: NSPoint?
    private static var resizeObserver: (any NSObjectProtocol)?

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
        present(
            PopoverView(model: model).glassSurface(cornerRadius: Tokens.Radius.popover),
            near: selection,
            fallbackSize: NSSize(width: Tokens.Size.popoverStep1, height: 240),
            onCancel: { model.escape() }
        )
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
                case .modelSettings:
                    SettingsPane.openVerbaineSettings()
                case .retry, .copyOriginal, .copyResult, .dismiss:
                    // Nothing to retry or copy out here: the action never started, or the text
                    // it would hand back is already where the user left it.
                    break
                }
                close()
            },
            onClose: close
        )
        .padding(Tokens.Space.m)
        .frame(width: Tokens.Size.popoverStep1)
        .glassSurface(cornerRadius: Tokens.Radius.popover)

        present(
            pane,
            near: selection,
            fallbackSize: NSSize(width: Tokens.Size.popoverStep1, height: 140),
            onCancel: { close() }
        )
    }

    private static func present(
        _ content: some View,
        near selection: Selection?,
        fallbackSize: NSSize,
        onCancel: @escaping () -> Void
    ) {
        let panel = PopoverPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass surface draws its own shadow; a window shadow on a transparent panel would
        // trace the square frame instead of the 14 pt corner.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = onCancel

        let hosting = NSHostingView(rootView: content)
        // The view decides the size at each step; the panel follows it.
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize == .zero ? fallbackSize : hosting.fittingSize)

        let point = topLeft(for: selection, size: panel.frame.size)
        panel.setFrameTopLeftPoint(point)
        anchor = point
        panel.makeKeyAndOrderFront(nil)

        Self.panel = panel
        observeResize(of: panel)
    }

    /// Keeps the top-left corner still while the popover grows from step 1 to the result.
    private static func observeResize(of window: NSWindow) {
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                guard let panel, let anchor else { return }
                panel.setFrameTopLeftPoint(clamped(anchor, size: panel.frame.size))
            }
        }
    }

    static func close() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        anchor = nil
        panel?.close()
        panel = nil
    }

    /// Top-left corner for a panel: 8 px below the selection, flipped above it when the screen
    /// edge is within 400 px below (the popover's maximum height), or the mouse when the app does
    /// not report bounds. AX rects use a top-left screen origin, AppKit a bottom-left one.
    /// Shared with the undo toast, which appears where the popover was.
    static func topLeft(for selection: Selection?, size: NSSize) -> NSPoint {
        guard let bounds = selection?.bounds, let primary = NSScreen.screens.first else {
            let mouse = NSEvent.mouseLocation
            return NSPoint(x: mouse.x, y: mouse.y)
        }

        let gap = Tokens.Space.s
        // Flip to sit above the selection when there is not room for a full-height popover below.
        let below = NSPoint(x: bounds.minX, y: primary.frame.maxY - bounds.maxY - gap)
        let screen = screen(containing: below)
        let roomBelow = below.y - screen.visibleFrame.minY
        guard roomBelow < Tokens.Size.popoverMaxHeight else { return clamped(below, size: size) }

        let above = NSPoint(x: bounds.minX, y: primary.frame.maxY - bounds.minY + gap + size.height)
        return clamped(above, size: size)
    }

    /// Keeps the whole panel on the screen it lands on.
    private static func clamped(_ point: NSPoint, size: NSSize) -> NSPoint {
        let frame = screen(containing: point).visibleFrame

        let x = min(max(point.x, frame.minX), frame.maxX - size.width)
        // `point` is the top-left corner, so the bottom edge is point.y − height.
        let y = min(max(point.y, frame.minY + size.height), frame.maxY)
        return NSPoint(x: x, y: y)
    }

    private static func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first { $0.visibleFrame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

extension View {
    /// The board's glass surface: a blurred fill, a hairline edge and a soft drop shadow, clipped
    /// to the given radius. Used by the popover, the undo toast and the onboarding window.
    func glassSurface(cornerRadius: CGFloat, shadow: Bool = true) -> some View {
        background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Tokens.Palette.hairline, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(shadow ? 0.20 : 0), radius: 12, x: 0, y: 8)
        // The shadow needs room outside the surface, or the panel clips it.
        .padding(shadow ? Tokens.Space.m : 0)
    }
}
