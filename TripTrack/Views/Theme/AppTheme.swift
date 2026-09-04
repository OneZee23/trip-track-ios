import SwiftUI
import UIKit

// MARK: - Design Tokens

enum AppTheme {
    // MARK: - Accent — warm orange, road-trip feel
    static let accent = Color(red: 194/255, green: 69/255, blue: 43/255)       // #C2452B — terracotta
    static let accentBg = accent.opacity(0.08)

    static let green = Color(red: 46/255, green: 174/255, blue: 80/255)        // earthy green
    static let greenBg = green.opacity(0.08)
    static let blue = Color(red: 56/255, green: 132/255, blue: 224/255)        // sky blue
    static let blueBg = blue.opacity(0.08)
    static let red = Color(red: 220/255, green: 60/255, blue: 50/255)          // soft red
    static let yellow = Color(red: 245/255, green: 190/255, blue: 30/255)      // warm amber
    static let purple = Color(red: 160/255, green: 90/255, blue: 210/255)
    static let teal = Color(red: 80/255, green: 190/255, blue: 210/255)
    static let orange = accent

    // Gold — Me-tab LVL pill (0.6.0). Bg is adaptive: warm cream in light,
    // translucent gold in dark.
    /// The ground the vehicle sprites stand on. One value in both themes.
    ///
    /// Brand navy, and it took a wrong turn to get here. Measured on contrast
    /// alone a light plate wins: the sprites' 1 px outline reads at 9.5:1
    /// against it, where navy puts the same outline at 1.04:1. So the plate was
    /// light for a while — and every car on it looked bleached, because outline
    /// contrast is not what makes a painted body read. Saturated paint needs a
    /// dark ground to hold its colour, and the black car is carried by its
    /// glass, wheels and highlights rather than by its panels.
    ///
    /// Rendered side by side there was nothing to argue about. Keeping the
    /// measurement here because it is right about what it measures, and wrong
    /// about what to do.
    static let spritePlateTop = Color(red: 0x29/255, green: 0x36/255, blue: 0x4F/255)
    static let spritePlateBottom = Color(red: 0x16/255, green: 0x1B/255, blue: 0x2C/255)

    /// The gradient as a single fill, for callers that just want a colour.
    static let spritePlate = Color(red: 0x1F/255, green: 0x27/255, blue: 0x3D/255)

    static let gold = Color(red: 206/255, green: 154/255, blue: 46/255)
    static let goldBg = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 206/255, green: 154/255, blue: 46/255, alpha: 0.16)
            : UIColor(red: 247/255, green: 239/255, blue: 222/255, alpha: 1)
    })

    // Dim accent variants
    static let accentDim = accent.opacity(0.15)
    static let redDim = red.opacity(0.12)
    static let blueDim = blue.opacity(0.12)
    static let greenDim = green.opacity(0.12)
    static let orangeDim = accent.opacity(0.12)

    // MARK: - Adaptive text/surface colors

    static let textPrimary = Color(UIColor { tc in
        let isDark = tc.userInterfaceStyle == .dark
        return isDark ? UIColor.white.withAlphaComponent(0.92) : UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1)
    })
    static let textSecondary = Color(UIColor { tc in
        let isDark = tc.userInterfaceStyle == .dark
        return isDark ? UIColor.white.withAlphaComponent(0.55) : UIColor(red: 100/255, green: 100/255, blue: 110/255, alpha: 1)
    })
    static let textTertiary = Color(UIColor { tc in
        let isDark = tc.userInterfaceStyle == .dark
        return isDark ? UIColor.white.withAlphaComponent(0.28) : UIColor(red: 155/255, green: 155/255, blue: 165/255, alpha: 1)
    })
    static let border = Color(UIColor { tc in
        let isDark = tc.userInterfaceStyle == .dark
        return isDark ? UIColor.white.withAlphaComponent(0.08) : UIColor(red: 0, green: 0, blue: 0, alpha: 0.05)
    })
    static let borderBright = Color(UIColor { tc in
        let isDark = tc.userInterfaceStyle == .dark
        return isDark ? UIColor.white.withAlphaComponent(0.14) : UIColor(red: 0, green: 0, blue: 0, alpha: 0.08)
    })
    static let surface = Color(UIColor { tc in
        if tc.userInterfaceStyle == .dark {
            return UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
        } else {
            return UIColor(red: 248/255, green: 246/255, blue: 242/255, alpha: 1) // warm cream
        }
    })
    static let surfaceElevated = Color(UIColor { tc in
        if tc.userInterfaceStyle == .dark {
            return UIColor(red: 40/255, green: 40/255, blue: 42/255, alpha: 1)
        } else {
            return UIColor.white
        }
    })

    // MARK: - Adaptive color resolver

    struct Colors {
        let scheme: ColorScheme

        var bg: Color {
            scheme == .dark
                ? Color(red: 18/255, green: 18/255, blue: 20/255)
                : Color(red: 248/255, green: 246/255, blue: 242/255) // warm cream background
        }
        var card: Color {
            scheme == .dark
                ? Color(red: 30/255, green: 30/255, blue: 32/255)
                : Color.white
        }
        var cardAlt: Color {
            scheme == .dark
                ? Color(red: 42/255, green: 42/255, blue: 44/255)
                : Color(red: 244/255, green: 242/255, blue: 238/255) // warm light
        }
        var text: Color {
            scheme == .dark
                ? Color.white.opacity(0.92)
                : Color(red: 30/255, green: 30/255, blue: 35/255)
        }
        var textSecondary: Color {
            scheme == .dark
                ? Color.white.opacity(0.55)
                : Color(red: 100/255, green: 100/255, blue: 110/255)
        }
        var textTertiary: Color {
            scheme == .dark
                ? Color.white.opacity(0.28)
                : Color(red: 155/255, green: 155/255, blue: 165/255)
        }
        var border: Color {
            scheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.05)
        }
        var borderBright: Color {
            scheme == .dark
                ? Color.white.opacity(0.14)
                : Color.black.opacity(0.08)
        }
        var glass: Color {
            scheme == .dark
                ? Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.72)
                : Color.white.opacity(0.82)
        }
        var glassBorder: Color {
            scheme == .dark
                ? Color.white.opacity(0.16)
                : Color.black.opacity(0.06)
        }
    }

    static func colors(for scheme: ColorScheme) -> Colors {
        Colors(scheme: scheme)
    }
}

// MARK: - Glass Background Modifier

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 20
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let c = AppTheme.colors(for: scheme)
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(c.border, lineWidth: 1)
            )
    }
}

// MARK: - Surface Card Modifier

struct SurfaceCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let c = AppTheme.colors(for: scheme)
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(c.card)
                    .shadow(
                        color: scheme == .dark ? .clear : .black.opacity(0.03),
                        radius: 2,
                        y: 1
                    )
            }
    }
}

// MARK: - Glass Pill Modifier

struct GlassPill: ViewModifier {
    var isActive: Bool = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let c = AppTheme.colors(for: scheme)
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? .white : c.textSecondary)
            .background(
                isActive ? AppTheme.accent : c.card,
                in: Capsule()
            )
    }
}

// MARK: - Pressable Card Style

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Карточка, у которой долгий тап что-то открывает.
///
/// Обычный `PressableCardStyle` отрабатывает мгновенно и на глаз неотличим от
/// простого нажатия: человек не понимает, что палец надо ЗАДЕРЖАТЬ, и просто
/// не находит меню. Здесь сжатие идёт полсекунды — примерно столько же, сколько
/// система ждёт до контекстного меню, — поэтому карточка на глазах «поддаётся»,
/// пока держишь, и становится ясно, что произойдёт, если не отпускать.
struct HoldableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.945 : 1.0)
            .animation(.easeOut(duration: configuration.isPressed ? 0.5 : 0.18),
                       value: configuration.isPressed)
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 300)
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - Haptics

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGen = UISelectionFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func action() { medium.impactOccurred() }
    static func success() { notification.notificationOccurred(.success) }
    static func error() { notification.notificationOccurred(.error) }
    static func selection() { selectionGen.selectionChanged() }

    /// Reaction lands — a crisp, sharp click (rigid reads as "snapped on").
    static func reactionOn() { rigid.impactOccurred(intensity: 0.95) }
    /// Reaction taken back — a duller, quieter thud at lower intensity, so
    /// undoing never feels like casting another vote.
    static func reactionOff() { soft.impactOccurred(intensity: 0.65) }
}

// MARK: - View Extensions

extension View {
    func glassBackground(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    func surfaceCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(SurfaceCard(cornerRadius: cornerRadius))
    }

    func glassPill(isActive: Bool = false) -> some View {
        modifier(GlassPill(isActive: isActive))
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
