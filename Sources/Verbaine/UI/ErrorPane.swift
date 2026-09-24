import SwiftUI

/// One failure, shown the same way wherever it happens: a heading, the sentence under it, its one
/// remedy, and a way out (board row 4).
///
/// Used inside the popover when an action fails and on its own when capture fails before there
/// is a popover to fail in.
struct ErrorPane: View {
    let error: UserFacingError
    /// Runs the remedy the error asks for. The caller owns the meaning of each case — the same
    /// `Retry` means "run the action again" in the popover and nothing at all standalone.
    let perform: (UserFacingError.Remedy) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Tokens.Palette.warning)
                Text(error.title)
                    .font(Tokens.Face.paneSemibold)
                    .foregroundStyle(Tokens.Ink.primary)
            }

            Text(error.message)
                .font(Tokens.Face.pane)
                .foregroundStyle(Tokens.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Tokens.Space.s) {
                KeyHint(key: "esc")
                Spacer()
                Button(error.remedy.dismissTitle, action: onClose)
                if let title = error.remedy.title {
                    Button(title) { perform(error.remedy) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, Tokens.Space.xxs)
        }
    }
}
