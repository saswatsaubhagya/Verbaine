import AppKit
import SwiftUI

/// The board's token sheet (`docs/DESIGN.md` "Components", row 8 of the design board) expressed
/// once, so no view hard-codes a hex value or a point size.
///
/// Colours that differ between light and dark are `NSColor` dynamic providers rather than
/// `Color(light:dark:)` — SwiftUI has no such initialiser, and a dynamic `NSColor` resolves
/// against whatever appearance the view is drawn in, including a panel that opens over a
/// dark-mode app while the system is light.
enum Tokens {
    enum Radius {
        static let popover: CGFloat = 14
        static let window: CGFloat = 13
        static let tile: CGFloat = 10
        static let button: CGFloat = 8
        static let field: CGFloat = 7
        static let menuItem: CGFloat = 6
        static let diff: CGFloat = 3
    }

    /// Spacing scale: 4 6 8 9 12 14 16 20. Popover padding 12, window padding 24–32.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let sm: CGFloat = 9
        static let m: CGFloat = 12
        static let ml: CGFloat = 14
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let window: CGFloat = 24
        static let windowWide: CGFloat = 32
    }

    enum Size {
        static let popoverStep1: CGFloat = 320
        static let popoverResult: CGFloat = 560
        static let popoverMaxHeight: CGFloat = 400
        static let menu: CGFloat = 262
        static let onboarding = CGSize(width: 520, height: 420)
        static let settings = CGSize(width: 640, height: 430)

        /// Action tile: 94 × 62, icon 19 at stroke 1.7, gap 6 to the label.
        static let tile = CGSize(width: 94, height: 62)
        static let tileIcon: CGFloat = 19
        static let tileIconStroke: CGFloat = 1.7
        /// Toast: height 30, radius 15 (full pill), padding 0 6 0 12, gap 8.
        static let toastHeight: CGFloat = 30
        /// Progress row: full-bleed 2 px track.
        static let progressTrack: CGFloat = 2
    }

    enum Ink {
        static let primary = dynamic(light: .black.withAlphaComponent(0.85), dark: .white.withAlphaComponent(0.92))
        static let secondary = dynamic(light: .black.withAlphaComponent(0.55), dark: .white.withAlphaComponent(0.55))
        static let tertiary = dynamic(light: .black.withAlphaComponent(0.40), dark: .white.withAlphaComponent(0.42))
        static let quaternary = dynamic(light: .black.withAlphaComponent(0.34), dark: .white.withAlphaComponent(0.35))
        /// Unchanged words in the diff panes sit back at 45% so the highlights carry the eye.
        static let diffUnchanged = dynamic(light: .black.withAlphaComponent(0.45), dark: .white.withAlphaComponent(0.45))
    }

    enum Palette {
        static let accent = Color.accentColor
        static let ready = dynamic(light: hex(0x34C759), dark: hex(0x30D158))
        static let warning = Color(hex(0xFF9F0A))
        static let removed = dynamic(light: hex(0xFF453A), dark: hex(0xFF6961))

        static let hairline = dynamic(light: .black.withAlphaComponent(0.10), dark: .white.withAlphaComponent(0.12))
        /// Diff backgrounds. Added 20% light / 26% dark; removed sits on #FF453A 8% / 14%.
        static let addedFill = dynamic(light: hex(0x30D158).withAlphaComponent(0.20), dark: hex(0x30D158).withAlphaComponent(0.26))
        static let removedFill = dynamic(light: hex(0xFF453A).withAlphaComponent(0.08), dark: hex(0xFF453A).withAlphaComponent(0.14))
        /// Tile rest fill: white 55% light, white 8% dark over the glass behind it.
        static let tileRest = dynamic(light: .white.withAlphaComponent(0.55), dark: .white.withAlphaComponent(0.08))
        static let tileBorder = dynamic(light: .black.withAlphaComponent(0.07), dark: .white.withAlphaComponent(0.10))
        static let tileHover = dynamic(light: .black.withAlphaComponent(0.05), dark: .white.withAlphaComponent(0.07))
        static let progressTrack = dynamic(light: .black.withAlphaComponent(0.10), dark: .white.withAlphaComponent(0.14))
    }

    /// SF Pro at the board's sizes. `.system` is SF Pro on macOS; Display vs Text is chosen by
    /// the optical-size axis at 20 pt, which is why the 22 pt headline needs no special face.
    enum Face {
        static let headline = Font.system(size: 22, weight: .semibold)
        static let windowTitle = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13)
        static let menuItem = Font.system(size: 12.5)
        static let pane = Font.system(size: 12)
        static let paneSemibold = Font.system(size: 12, weight: .semibold)
        static let tileLabel = Font.system(size: 11, weight: .medium)
        static let footerMeta = Font.system(size: 10.5)
        static let paneHeader = Font.system(size: 9.5, weight: .medium)
        /// Keyboard hints and recorded shortcuts.
        static let keyHint = Font.system(size: 10, design: .monospaced)
        static let keyHintLarge = Font.system(size: 12, design: .monospaced)
    }

    /// Pane headers are 9.5 uppercase at +6% tracking.
    static let paneHeaderTracking: CGFloat = 9.5 * 0.06

    private static func hex(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension Text {
    /// A pane header: 9.5 uppercase, +6% tracking, tertiary ink.
    func paneHeaderStyle() -> some View {
        textCase(.uppercase)
            .font(Tokens.Face.paneHeader)
            .tracking(Tokens.paneHeaderTracking)
            .foregroundStyle(Tokens.Ink.tertiary)
    }
}
