import SwiftUI

/// The popover's two steps: pick an action, then read the result next to the original.
///
/// Laid out to the design board (rows 1–3): 320 pt wide on step 1, 560 pt once there is a result,
/// panes capped at 400 pt and scrolling internally. Number keys 1–6 pick an action, and Change
/// tone opens a sub-row in place where 1–4 pick the tone.
struct PopoverView: View {
    @Bindable var model: PopoverModel
    /// Read once when the popover opens; Settings is not open at the same time.
    @State private var customActions = Preferences.customActions()
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            switch model.phase {
            case .actions:
                actionStep
            case .running, .result:
                resultStep
            case .failed(let error):
                ErrorPane(error: error, perform: apply, onClose: model.onClose)
            }
        }
        .padding(Tokens.Space.m)
        .frame(width: isResult ? Tokens.Size.popoverResult : Tokens.Size.popoverStep1, alignment: .topLeading)
        .frame(maxHeight: Tokens.Size.popoverMaxHeight, alignment: .topLeading)
        .task { await model.loadEstimate() }
    }

    private var isResult: Bool {
        switch model.phase {
        case .actions: false
        case .failed: false
        case .running, .result: true
        }
    }

    /// What each remedy means once there is a popover: retry the action, or fall back to the
    /// clipboard. Settings remedies close the popover — the user has to leave anyway.
    private func apply(_ remedy: UserFacingError.Remedy) {
        switch remedy {
        case .retry:
            model.retry()
        case .copyOriginal:
            model.copyOriginal()
        case .copyResult:
            model.copy()
        case .accessibilitySettings:
            AccessibilityPermission.openSettingsPane()
            model.onClose()
        case .intelligenceSettings:
            SettingsPane.openAppleIntelligence()
            model.onClose()
        case .modelSettings:
            SettingsPane.openVerbaineSettings()
            model.onClose()
        case .dismiss:
            model.onClose()
        }
    }

    // MARK: - Step 1 · pick an action

    private var actionStep: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            titleBar

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(Tokens.Size.tile.width), spacing: Tokens.Space.s), count: 3),
                alignment: .leading,
                spacing: Tokens.Space.s
            ) {
                ForEach(Array(Action.grid.enumerated()), id: \.element.id) { index, action in
                    ActionTile(
                        title: action.title,
                        symbol: action.symbol,
                        key: index + 1,
                        isSelected: model.isPickingTone && isToneAction(action),
                        run: { pick(action) }
                    )
                    .disabled(!enabled(action))
                    .keyboardShortcut(shortcut(index + 1), modifiers: model.isPickingTone ? [.command] : [])
                }
            }

            if model.isPickingTone { toneRow }

            if !customActions.isEmpty { customRow }

            if Inference.current.isRemote {
                Label("via \(Inference.current.displayName) · cloud", systemImage: "cloud")
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Ink.tertiary)
            }

            footerMeta
        }
    }

    private var titleBar: some View {
        HStack {
            Text("Verbaine")
                .font(Tokens.Face.paneSemibold)
                .foregroundStyle(Tokens.Ink.primary)
            Spacer()
            KeyHint(key: "esc")
        }
    }

    /// Change tone expands in place; the keys remap to 1–4 while it is open (board row 1, dark).
    private var toneRow: some View {
        HStack(spacing: Tokens.Space.xs) {
            ForEach(Array(tones.enumerated()), id: \.element.id) { index, tone in
                Button(tone.title) { model.run(.changeTone(tone)) }
                    .buttonStyle(.plain)
                    .font(Tokens.Face.tileLabel)
                    .foregroundStyle(Tokens.Palette.accent)
                    .padding(.horizontal, Tokens.Space.s)
                    .padding(.vertical, Tokens.Space.xs)
                    .background(Tokens.Palette.accent.opacity(0.13), in: .capsule)
                    .keyboardShortcut(shortcut(index + 1), modifiers: [])
            }
        }
        .transition(.opacity)
    }

    /// The app's preset tone first (T3.3), the rest after it.
    private var tones: [Tone] {
        Preferences.tones(forBundleID: model.selection.appBundleID)
    }

    private var customRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Yours").paneHeaderStyle()
            HStack(spacing: Tokens.Space.xs) {
                ForEach(customActions.map(Action.custom)) { action in
                    Button(action.title) { model.run(action) }
                        .buttonStyle(.plain)
                        .font(Tokens.Face.tileLabel)
                        .foregroundStyle(Tokens.Ink.primary)
                        .padding(.horizontal, Tokens.Space.s)
                        .padding(.vertical, Tokens.Space.xs)
                        .background(Tokens.Palette.tileRest, in: .capsule)
                        .overlay { Capsule().strokeBorder(Tokens.Palette.tileBorder, lineWidth: 1) }
                        .disabled(!enabled(action))
                }
            }
        }
    }

    private var footerMeta: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxs) {
            Divider().overlay(Tokens.Palette.hairline)
            HStack {
                Text(sizeLine)
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Ink.tertiary)
                    .monospacedDigit()
                Spacer()
                Text(model.isPickingTone ? "1–4 tone · esc back" : "1–6 pick · esc close")
                    .font(Tokens.Face.keyHint)
                    .foregroundStyle(Tokens.Ink.quaternary)
            }
            if let warning = model.estimate?.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Palette.warning)
            }
        }
    }

    /// "142 words · fits in one pass", or the part count once it takes more than one.
    private var sizeLine: String {
        let words = model.selection.text.wordCount
        guard let estimate = model.estimate else { return "\(words) words" }
        return estimate.isLong
            ? "\(words) words · long text, \(estimate.parts) parts"
            : "\(words) words · fits in one pass"
    }

    private func pick(_ action: Action) {
        if isToneAction(action) {
            model.isPickingTone.toggle()
        } else {
            model.run(action)
        }
    }

    private func isToneAction(_ action: Action) -> Bool {
        if case .changeTone = action { return true }
        return false
    }

    private func shortcut(_ number: Int) -> KeyEquivalent {
        KeyEquivalent(Character("\(number)"))
    }

    /// Past 12,000 tokens the grid offers only what stays useful at that length (PRD row 3).
    private func enabled(_ action: Action) -> Bool {
        model.estimate?.isEnabled(action) ?? true
    }

    // MARK: - Step 2 · the result

    private var resultStep: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            resultHeader
            if isRunning { progressRow }
            resultPanes
            footer
        }
    }

    private var resultHeader: some View {
        HStack(spacing: Tokens.Space.s) {
            Text(model.action?.title ?? "Result")
                .font(Tokens.Face.paneSemibold)
                .foregroundStyle(Tokens.Ink.primary)

            Text(Inference.current.isRemote ? "\(Inference.current.displayName) · cloud" : "On-device")
                .font(Tokens.Face.keyHint)
                .foregroundStyle(Tokens.Palette.accent)
                .padding(.horizontal, Tokens.Space.xs)
                .padding(.vertical, 1)
                .background(Tokens.Palette.accent.opacity(0.13), in: .capsule)

            Spacer()

            // Switching tone re-runs against the original without reopening the popover.
            if case .changeTone(let current) = model.action {
                HStack(spacing: Tokens.Space.xxs) {
                    ForEach(tones) { tone in
                        Button(tone.title) { model.run(.changeTone(tone)) }
                            .buttonStyle(.plain)
                            .font(Tokens.Face.keyHint)
                            .foregroundStyle(tone == current ? Tokens.Palette.accent : Tokens.Ink.secondary)
                            .padding(.horizontal, Tokens.Space.xs)
                            .padding(.vertical, 1)
                            .background(
                                tone == current ? Tokens.Palette.accent.opacity(0.13) : .clear,
                                in: .capsule
                            )
                    }
                }
            }
        }
    }

    /// Full-bleed 2 px track that advances one step per completed part (board row 3).
    private var progressRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            if let progress = model.progress {
                HStack {
                    Text("Part \(progress.part) of \(progress.total)")
                        .font(Tokens.Face.footerMeta)
                        .foregroundStyle(Tokens.Ink.tertiary)
                        .monospacedDigit()
                    Spacer()
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Tokens.Palette.progressTrack)
                        Rectangle()
                            .fill(Tokens.Palette.accent)
                            .frame(width: geometry.size.width * fraction(of: progress))
                    }
                }
                .frame(height: Tokens.Size.progressTrack)
            } else {
                // Single-pass: no part count to advance, so the track stays indeterminate.
                ProgressView().controlSize(.small)
            }
        }
    }

    private func fraction(of progress: PartProgress) -> Double {
        guard progress.total > 0 else { return 0 }
        return Double(progress.part) / Double(progress.total)
    }

    private var resultPanes: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            pane(title: "Original") {
                Text(highlighted(kinds: [.same, .removed], marking: .removed))
            }
            pane(title: "Result") {
                if case .running = model.phase {
                    Text(model.output).foregroundStyle(Tokens.Ink.primary)
                } else {
                    Text(highlighted(kinds: [.same, .inserted], marking: .inserted))
                }
            }
        }
        .frame(maxHeight: Tokens.Size.popoverMaxHeight)
    }

    private func pane<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(title).paneHeaderStyle()
            ScrollView {
                content()
                    .font(Tokens.Face.pane)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Renders the diff for one pane: `kinds` is what that side of the diff contains, `marking`
    /// is the kind that gets the highlight. Unchanged words sit back at 45% ink.
    private func highlighted(kinds: Set<DiffEngine.Kind>, marking: DiffEngine.Kind) -> AttributedString {
        var result = AttributedString()
        for segment in model.diff where kinds.contains(segment.kind) {
            var piece = AttributedString(segment.text)
            if segment.kind == marking {
                piece.foregroundColor = marking == .removed ? Tokens.Palette.removed : Tokens.Ink.primary
                piece.backgroundColor = marking == .removed ? Tokens.Palette.removedFill : Tokens.Palette.addedFill
                if marking == .removed { piece.strikethroughStyle = .single }
            } else {
                piece.foregroundColor = Tokens.Ink.diffUnchanged
            }
            result.append(piece)
        }
        return result
    }

    private var footer: some View {
        VStack(spacing: Tokens.Space.s) {
            Divider().overlay(Tokens.Palette.hairline)
            HStack(spacing: Tokens.Space.s) {
                Text(footerCounts)
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Ink.tertiary)
                    .monospacedDigit()

                Spacer()

                if isRunning {
                    Button("Cancel") { model.cancel() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Retry") { model.retry() }
                        .disabled(model.action == nil)
                    // Replace and Copy stay hidden until the last part lands.
                    labelledButton("Copy", hint: "⌘C") { model.copy() }
                        .keyboardShortcut(defaultButton == .copy ? KeyboardShortcut.defaultAction : KeyboardShortcut("c"))
                        .disabled(model.output.isEmpty)
                    labelledButton("Replace", hint: "⏎") { model.replace() }
                        .keyboardShortcut(defaultButton == .replace ? KeyboardShortcut.defaultAction : KeyboardShortcut("r"))
                        .disabled(model.output.isEmpty)
                }
            }
        }
    }

    private func labelledButton(_ title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.xxs) {
                Text(title)
                Text(hint).font(Tokens.Face.keyHint).foregroundStyle(.secondary)
            }
        }
    }

    /// "142 → 38 words" once there is a result; the part count while one is still running.
    private var footerCounts: String {
        let original = model.selection.text.wordCount
        if isRunning {
            guard let progress = model.progress else { return "\(original) words" }
            return "Long text · \(progress.total) parts"
        }
        return "\(original) → \(model.output.wordCount) words"
    }

    private var defaultButton: CustomAction.DefaultButton {
        model.action?.defaultButton ?? .replace
    }

    private var isRunning: Bool {
        if case .running = model.phase { return true }
        return false
    }
}

extension DiffEngine.Kind: Hashable {}

extension String {
    /// Whitespace-separated word count, for the popover's "142 → 38 words" line.
    var wordCount: Int {
        split(whereSeparator: \.isWhitespace).count
    }
}
