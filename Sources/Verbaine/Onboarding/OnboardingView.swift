import SwiftUI

/// The first-launch window: three steps, each with one thing to understand or grant.
///
/// Board row 7 — 520 × 420, a 22 pt headline over one paragraph, the step's own content, and a
/// footer carrying "Step n of 3" against Back / Continue.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text(model.step.title)
                    .font(Tokens.Face.headline)
                    .foregroundStyle(Tokens.Ink.primary)
                Text(subtitle)
                    .font(Tokens.Face.body)
                    .foregroundStyle(Tokens.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
        .padding(Tokens.Space.windowWide)
        .frame(width: Tokens.Size.onboarding.width, height: Tokens.Size.onboarding.height)
        // The two permissions are granted in System Settings, which tells us nothing when it
        // happens, so poll while the window is open.
        .task(id: model.step) {
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var subtitle: String {
        switch model.step {
        case .welcome:
            "Select text anywhere on your Mac, and Verbaine rewrites it in place."
        case .intelligence:
            "Verbaine runs on Apple's Foundation Models, built into macOS. The model is downloaded once and then runs entirely on this Mac."
        case .accessibility:
            "Verbaine needs Accessibility permission to read your selection and type the replacement back. It reads only the text you select, only when you invoke it."
        }
    }

    // MARK: - Steps

    /// The three-beat explanation of the hero flow, drawn as numbered cards.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            HStack(spacing: Tokens.Space.m) {
                card(number: 1, title: "Select", symbol: "text.cursor")
                card(number: 2, title: "Pick an action", symbol: "wand.and.sparkles")
                card(number: 3, title: "Replaced", symbol: "checkmark.circle")
            }
            privacyLine("Nothing leaves your Mac. No account, no network.")
        }
    }

    private func card(number: Int, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("\(number)")
                .font(Tokens.Face.keyHintLarge)
                .foregroundStyle(Tokens.Palette.accent)
            Image(systemName: symbol)
                .font(.system(size: Tokens.Size.tileIcon))
                .foregroundStyle(Tokens.Ink.primary)
            Text(title)
                .font(Tokens.Face.tileLabel)
                .foregroundStyle(Tokens.Ink.secondary)
        }
        .padding(Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Tokens.Palette.tileRest, in: .rect(cornerRadius: Tokens.Radius.tile))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.tile)
                .strokeBorder(Tokens.Palette.tileBorder, lineWidth: 1)
        }
    }

    private var intelligence: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            status(ok: model.availability == .ready, text: availabilityText)

            HStack(spacing: Tokens.Space.s) {
                if model.availability != .ready {
                    Button("Open System Settings") { SettingsPane.openAppleIntelligence() }
                }
                Button("Check again") { model.refresh() }
            }

            privacyLine("Your text is never sent anywhere.")
        }
    }

    private var availabilityText: String {
        switch model.availability {
        case .ready: "Apple Intelligence is on and the on-device model is ready."
        case .intelligenceDisabled: "Apple Intelligence is off. Turn it on in System Settings — this window updates on its own."
        case .modelDownloading: "Apple Intelligence is still downloading its model. This window updates when it finishes."
        case .unsupportedDevice: "This Mac cannot run Apple Intelligence, so Verbaine cannot rewrite text."
        // Onboarding only ever reads the on-device provider's availability, which `init(_:)`
        // never maps to this case — unreachable in practice, kept only for exhaustiveness.
        case .remoteNotConfigured: "This Mac cannot run Apple Intelligence, so Verbaine cannot rewrite text."
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            status(
                ok: model.isTrusted,
                text: model.isTrusted
                    ? "Accessibility granted."
                    : "Not granted yet. Add Verbaine under Privacy & Security → Accessibility."
            )

            HStack(spacing: Tokens.Space.s) {
                if !model.isTrusted {
                    Button("Open System Settings") {
                        AccessibilityPermission.requestTrust()
                        AccessibilityPermission.openSettingsPane()
                    }
                }
                Button("Test on this text") { Task { await model.runTest() } }
                    .disabled(!model.isTrusted)
            }

            if let test = model.test {
                switch test {
                case .captured(let text):
                    status(ok: true, text: "Worked — read “\(text.prefix(80))”")
                case .failed(let message):
                    status(ok: false, text: message)
                }
            } else if model.isTrusted {
                Text("Select some text in another app, then click Test on this text — this window stays out of the way.")
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pieces

    private func status(ok: Bool, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? Tokens.Palette.ready : Tokens.Palette.warning)
            Text(text)
                .font(Tokens.Face.body)
                .foregroundStyle(Tokens.Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Palette.tileRest, in: .rect(cornerRadius: Tokens.Radius.button))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.button)
                .strokeBorder(Tokens.Palette.tileBorder, lineWidth: 1)
        }
    }

    private func privacyLine(_ text: String) -> some View {
        Label(text, systemImage: "lock")
            .font(Tokens.Face.footerMeta)
            .foregroundStyle(Tokens.Ink.tertiary)
    }

    private var footer: some View {
        VStack(spacing: Tokens.Space.m) {
            Divider().overlay(Tokens.Palette.hairline)
            HStack {
                Text("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(Tokens.Face.footerMeta)
                    .foregroundStyle(Tokens.Ink.tertiary)
                    .monospacedDigit()
                Spacer()
                if model.step.previous != nil {
                    Button("Back") { model.back() }
                }
                Button(model.step.next == nil ? "Start using Verbaine" : "Continue") { model.advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            }
        }
    }
}
