import SwiftUI

// MARK: - Payload

/// What a raised hint needs to draw itself, published upward by the «?» that
/// raised it.
///
/// Carries its own `dismiss` because the state lives in the button (one row,
/// one hint) while the drawing happens at the sheet's root — see
/// `settingsHintLayer()` for why the two are separated.
struct SettingsHintPayload {
    let id: UUID
    let text: String
    let anchor: Anchor<CGRect>
    let dismiss: () -> Void
}

private struct SettingsHintKey: PreferenceKey {
    static let defaultValue: SettingsHintPayload? = nil
    static func reduce(value: inout SettingsHintPayload?, nextValue: () -> SettingsHintPayload?) {
        // Last writer wins: only one hint is ever open, and a second tap on a
        // different «?» closes the first through its own state.
        if let next = nextValue() { value = next }
    }
}

// MARK: - The «?»

/// The «?» that follows a settings label (Figma 1729:120) and the bubble it
/// raises (1741:266).
///
/// Self-contained on purpose: the caller hands over one finished, already
/// localized sentence and nothing else. A row earns a hint by gaining one
/// view — not by growing a piece of sheet-level state that every other row
/// then has to route around.
struct SettingsHintButton: View {
    /// Already localized. See the type doc.
    let text: String

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var isShowing = false
    /// Identity for the preference, stable across redraws.
    @State private var id = UUID()

    /// Canon draws the disc at 16 on a 360pt artboard (1729:121). 18 is that
    /// same circle at the width of the phones this actually ships to — the
    /// artboard note in `NavCircleIcon` covers why the numbers differ.
    private static let diameter: CGFloat = 18
    /// HIG floor. Grown with padding below and then taken back out of layout,
    /// so a 44pt target costs the row no width and the label keeps sitting
    /// right next to the disc.
    private static let hitTarget: CGFloat = 44

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        Button {
            Haptics.tap()
            isShowing.toggle()
        } label: {
            // `verbatim` — the glyph IS the control, not copy: it reads the
            // same in both languages and must never be routed through
            // AppStrings as a translatable string.
            Text(verbatim: "?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isShowing ? Color.white : c.textTertiary)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Circle().fill(isShowing ? AppTheme.accent : c.cardAlt))
                .animation(.easeOut(duration: 0.15), value: isShowing)
                .padding((Self.hitTarget - Self.diameter) / 2)
                .contentShape(Circle())
                .padding(-(Self.hitTarget - Self.diameter) / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.settingsHintTitle(l))
        .accessibilityIdentifier("settings_hint")
        // Publish WHERE this disc is, and let the sheet root draw the bubble.
        //
        // Not a `.popover`: UIKit sizes one from its content's preferred size,
        // and SwiftUI hands it the Text's IDEAL layout — one very long line. The
        // bubble came out a single line tall while the sentence wrapped to three
        // and spilled out of both ends of it, and constraining the width inside
        // did not help because the measurement happens before that layout.
        //
        // Not an in-tree overlay either: this row sits in a card, and the cards
        // after it paint later, so a bubble drawn here is covered by the next
        // group down.
        //
        // An anchor published to the root solves both at once — the bubble is
        // laid out by ordinary SwiftUI (so it simply fits its text) and drawn
        // above everything (so nothing covers or clips it).
        .anchorPreference(key: SettingsHintKey.self, value: .bounds) { anchor in
            guard isShowing else { return nil }
            return SettingsHintPayload(
                id: id,
                text: text,
                anchor: anchor,
                dismiss: { isShowing = false }
            )
        }
    }
}

// MARK: - The bubble, drawn at the root

extension View {
    /// Draws whichever hint is open, above this whole subtree.
    ///
    /// Apply once, at the root of the settings sheet.
    func settingsHintLayer() -> some View {
        overlayPreferenceValue(SettingsHintKey.self) { payload in
            GeometryReader { proxy in
                if let payload {
                    SettingsHintBubble(payload: payload, discFrame: proxy[payload.anchor])
                }
            }
        }
    }
}

/// Canon 1741:266: the sentence on a card with a small arrow pointing at the
/// disc that raised it. No heading, no button — a tap anywhere puts it away.
private struct SettingsHintBubble: View {
    let payload: SettingsHintPayload
    let discFrame: CGRect

    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    /// Canon's 248 on a 360pt artboard.
    private static let width: CGFloat = 248
    private static let arrow = CGSize(width: 16, height: 8)
    /// Never closer than this to a screen edge.
    private static let margin: CGFloat = 12
    /// Between the arrow's tip and the disc.
    private static let gap: CGFloat = 4

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        GeometryReader { proxy in
            // ALWAYS below the disc, arrow pointing up at it.
            //
            // Placing it above needs the card's own height, and measuring that
            // from inside this overlay did not settle: the height arrived after
            // the position had been computed with zero, so the card was laid out
            // as if it had no height at all — drawn over the row it belonged to,
            // with its arrow pointing down into the row below. Rather than fight
            // a layout feedback loop for a placement nobody asked for, the
            // bubble hangs below, which needs no measurement and never covers
            // the «?» you just pressed. Every row that carries a hint sits in
            // the sheet's first group, so there is always room beneath it.
            let y = discFrame.maxY + Self.gap
            let x = min(
                max(discFrame.midX - Self.width / 2, Self.margin),
                max(Self.margin, proxy.size.width - Self.width - Self.margin)
            )

            ZStack(alignment: .topLeading) {
                // Catches the tap that closes it. Invisible: a hint is not a
                // modal, and dimming the screen for one sentence would weigh
                // more than the sentence does.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                VStack(spacing: 0) {
                    arrowShape(c: c, cardX: x)

                    Text(payload.text)
                        .font(.system(size: 13))
                        // Hint bodies run two to four lines; default leading
                        // packs them into a block the eye slides off.
                        .lineSpacing(3)
                        .foregroundStyle(c.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: Self.width - 28, alignment: .leading)
                        .padding(14)
                        .background(c.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 16, y: 4)
                }
                .frame(width: Self.width)
                .offset(x: x, y: y)
                .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.16)) { appeared = true } }
    }

    /// The arrow tracks the DISC, not the card: near a screen edge the card is
    /// clamped away from the «?» it belongs to, and an arrow centred on the card
    /// would then point at nothing.
    private func arrowShape(c: AppTheme.Colors, cardX: CGFloat) -> some View {
        let inset = min(
            max(discFrame.midX - cardX - Self.arrow.width / 2, 14),
            Self.width - Self.arrow.width - 14
        )
        return Triangle()
            .fill(c.card)
            .frame(width: Self.arrow.width, height: Self.arrow.height)
            .frame(width: Self.width, alignment: .leading)
            .offset(x: inset)
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.12)) { appeared = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            payload.dismiss()
        }
    }
}

/// Points up at the disc the bubble belongs to.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
