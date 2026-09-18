import SwiftUI

/// The popover's two steps: pick an action, then read the result next to the original.
struct PopoverView: View {
    @Bindable var model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.phase {
            case .actions:
                actionGrid
            case .running, .result:
                resultPanes
                footer
            case .failed(let error):
                ErrorPane(error: error, perform: apply, onClose: model.onClose)
            }
        }
        .padding(14)
        .frame(width: 460, height: 320, alignment: .topLeading)
        .onExitCommand { model.onClose() }
        .task { await model.loadEstimate() }
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
        case .dismiss:
            model.onClose()
        }
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.selection.text)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.secondary)

            if let estimate = model.estimate {
                Text(estimate.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let warning = estimate.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(Action.grid) { action in
                    if case .changeTone = action {
                        Menu(action.title) {
                            // The app's preset tone first (T3.3), the rest after it.
                            ForEach(Preferences.tones(forBundleID: model.selection.appBundleID)) { tone in
                                Button(tone.title) { model.run(.changeTone(tone)) }
                            }
                        }
                        .menuStyle(.button)
                        .disabled(!enabled(action))
                    } else {
                        Button(action.title) { model.run(action) }
                            .frame(maxWidth: .infinity)
                            .disabled(!enabled(action))
                    }
                }
            }
            Spacer()
        }
    }

    /// Past 12,000 tokens the grid offers only what stays useful at that length (PRD row 3).
    private func enabled(_ action: Action) -> Bool {
        model.estimate?.isEnabled(action) ?? true
    }

    private var resultPanes: some View {
        HStack(alignment: .top, spacing: 10) {
            pane(title: "Original") {
                Text(highlighted(kinds: [.same, .removed], marking: .removed))
            }
            pane(title: model.action?.title ?? "Result") {
                if case .running = model.phase {
                    Text(model.output)
                } else {
                    Text(highlighted(kinds: [.same, .inserted], marking: .inserted))
                }
            }
        }
    }

    private func pane<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                content()
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Renders the diff for one pane: `kinds` is what that side of the diff contains, `marking`
    /// is the kind that gets the highlight.
    private func highlighted(kinds: Set<DiffEngine.Kind>, marking: DiffEngine.Kind) -> AttributedString {
        var result = AttributedString()
        for segment in model.diff where kinds.contains(segment.kind) {
            var piece = AttributedString(segment.text)
            if segment.kind == marking {
                piece.backgroundColor = marking == .removed ? .red.opacity(0.22) : .green.opacity(0.22)
                if marking == .removed { piece.strikethroughStyle = .single }
            }
            result.append(piece)
        }
        return result
    }

    private var footer: some View {
        HStack {
            if case .running = model.phase {
                ProgressView().controlSize(.small)
                if let progress = model.progress {
                    Text("Part \(progress.part) of \(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer()
            if isRunning {
                Button("Cancel") { model.cancel() }
            }
            Button("Retry") { model.retry() }
                .disabled(model.action == nil)
            Button("Copy") { model.copy() }
                .keyboardShortcut("c")
                .disabled(model.output.isEmpty)
            Button("Replace") { model.replace() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.output.isEmpty || isRunning)
        }
    }

    private var isRunning: Bool {
        if case .running = model.phase { return true }
        return false
    }
}

extension DiffEngine.Kind: Hashable {}
