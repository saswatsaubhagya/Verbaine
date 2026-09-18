import os

/// Remembers the last Replace for 60 s so the toast (T1.5) can take it back.
///
/// Holds the original and the result too, not just the selection: the messages in T1.6 and any
/// logging want to say *what* was replaced, and the entry is the only place that survives the
/// popover closing.
@MainActor
final class UndoBuffer {
    static let shared = UndoBuffer()

    /// How long an undo stays offered. The toast disappears after 4 s, but the entry outlives it
    /// so a later ⌘Z path can still find it.
    static let lifetime = Duration.seconds(60)

    struct Entry {
        let original: String
        let result: String
        let selection: Selection
        let recordedAt: ContinuousClock.Instant
    }

    private static let log = Logger(subsystem: "com.saswat.polish", category: "UndoBuffer")

    private var entry: Entry?

    /// One slot on purpose: only the most recent Replace is undoable, matching the single toast.
    func record(
        original: String,
        result: String,
        selection: Selection,
        at now: ContinuousClock.Instant = .now
    ) {
        entry = Entry(original: original, result: result, selection: selection, recordedAt: now)
    }

    /// Hands back the pending undo and clears the slot. `nil` once `lifetime` has passed, so a
    /// stale entry can never paste into text the user has moved on from.
    func take(at now: ContinuousClock.Instant = .now) -> Entry? {
        guard let pending = entry else { return nil }
        entry = nil
        guard now - pending.recordedAt < Self.lifetime else { return nil }
        return pending
    }

    /// Runs the undo, if one is still pending.
    func undo() async throws(WriteBackError) {
        guard let pending = take() else {
            Self.log.debug("undo requested with nothing pending")
            return
        }
        try await WriteBackService.undoReplace(selection: pending.selection)
    }
}
