import SwiftUI

/// One failure, shown the same way wherever it happens: the sentence, its one remedy, and Close.
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
        VStack(alignment: .leading, spacing: 14) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Close", action: onClose)
                if let title = error.remedy.title {
                    Button(title) { perform(error.remedy) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onExitCommand(perform: onClose)
    }
}
