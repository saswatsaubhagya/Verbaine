import AppKit

/// A copy of the pasteboard's contents, deep enough to survive `clearContents()`.
///
/// Both capture paths borrow the clipboard — ⌘C to read a selection (T0.4), ⌘V to write a
/// rewrite back (T0.5) — so both have to hand it back exactly as they found it, including on
/// every failure path.
///
/// `NSPasteboardItem`s belonging to the pasteboard are invalidated when it is cleared, so
/// every type's data is copied into fresh items up front.
struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    /// Puts the snapshot back. An empty snapshot still clears, so our copy never lingers.
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
