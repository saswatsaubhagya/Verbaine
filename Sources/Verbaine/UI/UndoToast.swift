import AppKit
import SwiftUI
import os

/// The "Replaced · Undo" toast shown for 4 s after a Replace (T1.5).
@MainActor
enum UndoToast {
    private static let log = Logger(subsystem: "com.saswat.polish", category: "UndoToast")
    private static let lifetime = Duration.seconds(4)

    private static var panel: NSPanel?
    private static var dismissal: Task<Void, Never>?

    static func show(near selection: Selection) {
        dismiss()

        let panel = PopoverPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: UndoToastView(undo: undo, dismiss: dismiss))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 160, height: 36))
        panel.setFrameTopLeftPoint(PopoverController.topLeft(for: selection, size: panel.frame.size))

        // Key, like the popover it replaces: ⌘Z has to reach the toast, and the source app's own
        // ⌘Z would undo the paste anyway if the user aims there instead.
        panel.makeKeyAndOrderFront(nil)
        Self.panel = panel

        dismissal = Task {
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    static func dismiss() {
        dismissal?.cancel()
        dismissal = nil
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

    var body: some View {
        HStack(spacing: 8) {
            Text("Replaced")
            Text("·").foregroundStyle(.secondary)
            Button("Undo", action: undo)
                .buttonStyle(.link)
                .keyboardShortcut("z")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .capsule)
        .onExitCommand(perform: dismiss)
    }
}
