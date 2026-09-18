import SwiftUI

/// The first-launch window: three steps, each with one thing to understand or grant.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.step.title)
                .font(.title2.weight(.semibold))

            Group {
                switch model.step {
                case .welcome: welcome
                case .intelligence: intelligence
                case .accessibility: accessibility
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .padding(20)
        .frame(width: 460, height: 320)
        // The two permissions are granted in System Settings, which tells us nothing when it
        // happens, so poll while the window is open.
        .task(id: model.step) {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select text in any app — Slack, Mail, Chrome, Notes — and press ⌃⌥P.")
            Text("Polish offers to fix the grammar, shorten it, change its tone or summarise it, then puts the result back where the text was.")
            Text("Everything runs on this Mac. No network, no account, nothing leaves the device.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var intelligence: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Polish writes with Apple's on-device model, so Apple Intelligence has to be on.")
                .font(.callout)

            status(ok: model.availability == .ready, text: availabilityText)

            if model.availability == .intelligenceDisabled {
                Button("Open Apple Intelligence settings") { SettingsPane.openAppleIntelligence() }
            }
        }
    }

    private var availabilityText: String {
        switch model.availability {
        case .ready: "Apple Intelligence is on and the model is ready."
        case .intelligenceDisabled: "Apple Intelligence is off. Turn it on in System Settings — this window updates on its own."
        case .modelDownloading: "Apple Intelligence is still downloading its model. This window updates when it finishes."
        case .unsupportedDevice: "This Mac cannot run Apple Intelligence, so Polish cannot rewrite text."
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading the text you select in other apps needs Accessibility permission.")
                .font(.callout)

            status(
                ok: model.isTrusted,
                text: model.isTrusted
                    ? "Accessibility is granted."
                    : "Not granted yet. Add Polish under Privacy & Security → Accessibility."
            )

            HStack {
                if !model.isTrusted {
                    Button("Open Accessibility settings") {
                        AccessibilityPermission.requestTrust()
                        AccessibilityPermission.openSettingsPane()
                    }
                }
                Button("Test it") { Task { await model.runTest() } }
                    .disabled(!model.isTrusted)
            }

            if let test = model.test {
                switch test {
                case .captured(let text):
                    status(ok: true, text: "Read: “\(text.prefix(80))”")
                case .failed(let message):
                    status(ok: false, text: message)
                }
            } else if model.isTrusted {
                Text("Select some text in another app, then click Test it — this window stays out of the way.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func status(ok: Bool, text: String) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(ok ? Color.green : Color.secondary)
            .font(.callout)
    }

    private var footer: some View {
        HStack {
            Text("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if model.step.previous != nil {
                Button("Back") { model.back() }
            }
            Button(model.step.next == nil ? "Finish" : "Continue") { model.advance() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinue)
        }
    }
}
