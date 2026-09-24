import AppKit
import SwiftUI
import os

/// The "Replaced · Undo" toast shown for 4 s after a Replace (T1.5).
///
/// Board row 5: a 30 pt pill with a hairline countdown along its bottom edge, auto-dismissing at
/// 4 s and pausing while the pointer is over it.
@MainActor
enum UndoToast {
    private static let log = Logger(subsystem: "in.saswatsaubhagya.verbaine", category: "UndoToast")
    static let lifetime = Duration.seconds(4)

    private static var panel: NSPanel?

    static func show(near selection: Selection) {
        dismiss()

        let panel = PopoverPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The pill draws its own shadow inside the panel, so the window keeps none.
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { dismiss() }
        let hosting = NSHostingView(rootView: UndoToastView(undo: undo, dismiss: dismiss))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize == .zero ? NSSize(width: 180, height: 54) : hosting.fittingSize)
        panel.setFrameTopLeftPoint(PopoverController.topLeft(for: selection, size: panel.frame.size))

        // Key, like the popover it replaces: ⌘Z has to reach the toast, and the source app's own
        // ⌘Z would undo the paste anyway if the user aims there instead.
        panel.makeKeyAndOrderFront(nil)
        Self.panel = panel
    }

    static func dismiss() {
        panel?.close()
        panel = nil
    }

    private static func undo() {
        dismiss()
        Task {
            do {
                try await UndoBuffer.shared.undo()
            } catch {
                log.error("undo failed: \(String(describing: error))")
                PopoverController.show(error: UserFacingError(error))
            }
        }
    }
}

private struct UndoToastView: View {
    let undo: () -> Void
    let dismiss: () -> Void

    /// 1 → 0 over the toast's life. The countdown hairline reads it, and reaching 0 dismisses.
    @State private var remaining = 1.0
    @State private var isHovering = false

    private static let tick = Duration.milliseconds(50)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Space.s) {
                Text("Replaced")
                    .font(Tokens.Face.pane)
                    .foregroundStyle(Tokens.Ink.primary)
                Button(action: undo) {
                    HStack(spacing: Tokens.Space.xxs) {
                        Text("Undo").font(.system(size: 12, weight: .medium))
                        Text("⌘Z").font(Tokens.Face.keyHint)
                    }
                    .foregroundStyle(Tokens.Palette.accent)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("z")
            }
            .padding(.leading, Tokens.Space.m)
            .padding(.trailing, Tokens.Space.xs)
            .frame(height: Tokens.Size.toastHeight - 1)

            // Hairline countdown along the bottom edge.
            GeometryReader { geometry in
                Rectangle()
                    .fill(Tokens.Palette.accent)
                    .frame(width: geometry.size.width * remaining)
            }
            .frame(height: 1)
        }
        .fixedSize()
        .glassSurface(cornerRadius: Tokens.Size.toastHeight / 2)
        .onHover { isHovering = $0 }
        .task {
            let step = Self.tick / UndoToast.lifetime
            while !Task.isCancelled && remaining > 0 {
                try? await Task.sleep(for: Self.tick)
                // Hovering pauses the countdown, so a toast under the pointer stays put.
                guard !isHovering else { continue }
                remaining = max(0, remaining - step)
            }
            if remaining <= 0 { dismiss() }
        }
    }
}

private extension Duration {
    /// This duration as a fraction of another, for the countdown's per-tick step.
    static func / (lhs: Duration, rhs: Duration) -> Double {
        let seconds = { (d: Duration) in Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
        return seconds(lhs) / seconds(rhs)
    }
}
