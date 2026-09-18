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
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                footer
            }
        }
        .padding(14)
        .frame(width: 460, height: 320, alignment: .topLeading)
        .onExitCommand { model.onClose() }
    }

    private var actionGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.selection.text)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(Action.grid) { action in
                    if case .changeTone = action {
                        Menu(action.title) {
                            ForEach(Tone.allCases) { tone in
                                Button(tone.title) { model.run(.changeTone(tone)) }
                            }
                        }
                        .menuStyle(.button)
                    } else {
                        Button(action.title) { model.run(action) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            Spacer()
        }
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
            }
            Spacer()
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
