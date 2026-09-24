import SwiftUI

/// One 94 × 62 tile in the popover's action grid: glyph, label, and the number key that runs it.
///
/// States come from the board's component sheet — rest, hover, selected, pressed, focus.
/// "Selected" is the tile whose sub-row is open (Change tone), not a persistent selection.
struct ActionTile: View {
    let title: String
    let symbol: String
    /// 1–6; `nil` for a tile past the sixth, which has no key.
    let key: Int?
    var isSelected = false
    let run: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: run) {
            VStack(spacing: Tokens.Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: Tokens.Size.tileIcon * 0.72, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: Tokens.Size.tileIcon)
                Text(title)
                    .font(Tokens.Face.tileLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Tokens.Palette.accent : Tokens.Ink.primary)
            .padding(.top, Tokens.Space.sm)
            .padding(.horizontal, Tokens.Space.sm)
            .padding(.bottom, Tokens.Space.s)
            .frame(width: Tokens.Size.tile.width, height: Tokens.Size.tile.height)
            .background(fill, in: .rect(cornerRadius: Tokens.Radius.tile))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.tile)
                    .strokeBorder(border, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect(cornerRadius: Tokens.Radius.tile))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(key.map { "\(title) — press \($0)" } ?? title)
    }

    private var fill: Color {
        if isSelected { return Tokens.Palette.accent.opacity(0.13) }
        if isHovering && isEnabled { return Tokens.Palette.tileHover }
        return Tokens.Palette.tileRest
    }

    private var border: Color {
        isSelected ? Tokens.Palette.accent.opacity(0.30) : Tokens.Palette.tileBorder
    }
}

/// A key hint rendered the way the board draws one: SF Mono on a faint hairline chip.
struct KeyHint: View {
    let key: String

    var body: some View {
        Text(key)
            .font(Tokens.Face.keyHint)
            .foregroundStyle(Tokens.Ink.tertiary)
            .padding(.horizontal, Tokens.Space.xxs)
            .padding(.vertical, 1)
            .background(Tokens.Palette.tileHover, in: .rect(cornerRadius: Tokens.Radius.menuItem - 2))
    }
}
