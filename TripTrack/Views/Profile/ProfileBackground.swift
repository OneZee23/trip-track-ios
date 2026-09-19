import SwiftUI

/// Picker-able profile background. Rendered 100% client-side from these
/// deterministic definitions — backend only stores the string identifier so
/// we can add / tune colors without a migration.
enum ProfileBackground: String, CaseIterable, Identifiable {
    case none      = ""
    case sunset    = "sunset"
    case ocean     = "ocean"
    case forest    = "forest"
    case mountain  = "mountain"
    case midnight  = "midnight"
    case dawn      = "dawn"
    case copper    = "copper"
    case slate     = "slate"
    case aurora    = "aurora"
    case sand      = "sand"

    // MARK: - «Плюс» (0.8.0)
    //
    // Восемь премиум-фонов. `rawValue` менять нельзя никогда: строка лежит в
    // `UserSettingsEntity.profileBackground`, в `ProfileUpdateRequest` и в
    // `SocialProfile` — то есть это контракт и с сервером, и со вторым
    // телефоном. Рисуются они ровно так же, как бесплатные одиннадцать:
    // клиентом, по этим определениям, чтобы добавить фон можно было без
    // миграции и без выкладки сервера.

    case plusNebula  = "plus_nebula"
    case plusLava    = "plus_lava"
    case plusGlacier = "plus_glacier"
    case plusNeon    = "plus_neon"
    case plusCarbon  = "plus_carbon"
    case plusGold    = "plus_gold"
    case plusTropic  = "plus_tropic"
    case plusStorm   = "plus_storm"

    var id: String { rawValue }

    /// Платный ли это фон. Единственный источник ответа — здесь, у самого
    /// варианта: список «что платное» рядом со списком «что есть» разошёлся бы
    /// на первом же добавленном фоне.
    var isPlus: Bool {
        switch self {
        case .plusNebula, .plusLava, .plusGlacier, .plusNeon,
             .plusCarbon, .plusGold, .plusTropic, .plusStorm:
            return true
        default:
            return false
        }
    }

    /// Что РИСОВАТЬ, когда «Плюс» кончился.
    ///
    /// Одна дверь на все места показа — герой «Я», «Мой профиль», чужой
    /// профиль. Выбор в базе при этом НЕ стирается (спека §2, «когда Плюс
    /// кончился»): человек продлил подписку — фон вернулся сам. Если бы
    /// правило жило в каждом месте показа отдельно, одно из трёх однажды
    /// показало бы платный фон бесплатно — ровно так же, как единицы
    /// расходились до `Measure`.
    func effective(isPlus: Bool) -> ProfileBackground {
        (self.isPlus && !isPlus) ? .none : self
    }

    /// То же правило, но от сырой строки: чужой профиль и настройки держат
    /// именно её, а не разобранный вариант.
    ///
    /// Незнакомая строка (фон из будущей версии) читается как `.none` — через
    /// `from(_:)`, то есть чужой профиль не падает и не остаётся пустым
    /// прямоугольником непонятного цвета.
    static func effective(id raw: String?, isPlus: Bool) -> ProfileBackground {
        from(raw).effective(isPlus: isPlus)
    }

    var displayName: String {
        switch self {
        case .none:     return "Default"
        case .sunset:   return "Sunset"
        case .ocean:    return "Ocean"
        case .forest:   return "Forest"
        case .mountain: return "Mountain"
        case .midnight: return "Midnight"
        case .dawn:     return "Dawn"
        case .copper:   return "Copper"
        case .slate:    return "Slate"
        case .aurora:   return "Aurora"
        case .sand:     return "Sand"
        case .plusNebula:  return "Nebula"
        case .plusLava:    return "Lava"
        case .plusGlacier: return "Glacier"
        case .plusNeon:    return "Neon"
        case .plusCarbon:  return "Carbon"
        case .plusGold:    return "Gold"
        case .plusTropic:  return "Tropic"
        case .plusStorm:   return "Storm"
        }
    }

    /// Two-stop linear gradient definition. Start top-leading → bottom-trailing.
    var gradient: [Color] {
        switch self {
        case .none:
            return []
        case .sunset:
            return [Color(red: 0.98, green: 0.55, blue: 0.24),
                    Color(red: 0.95, green: 0.31, blue: 0.46),
                    Color(red: 0.56, green: 0.22, blue: 0.54)]
        case .ocean:
            return [Color(red: 0.25, green: 0.55, blue: 0.85),
                    Color(red: 0.14, green: 0.37, blue: 0.67),
                    Color(red: 0.08, green: 0.22, blue: 0.46)]
        case .forest:
            return [Color(red: 0.32, green: 0.59, blue: 0.36),
                    Color(red: 0.19, green: 0.42, blue: 0.28),
                    Color(red: 0.10, green: 0.25, blue: 0.18)]
        case .mountain:
            return [Color(red: 0.55, green: 0.62, blue: 0.70),
                    Color(red: 0.32, green: 0.42, blue: 0.52),
                    Color(red: 0.16, green: 0.22, blue: 0.30)]
        case .midnight:
            return [Color(red: 0.18, green: 0.15, blue: 0.38),
                    Color(red: 0.09, green: 0.08, blue: 0.22),
                    Color(red: 0.03, green: 0.02, blue: 0.08)]
        case .dawn:
            return [Color(red: 0.99, green: 0.85, blue: 0.62),
                    Color(red: 0.98, green: 0.65, blue: 0.48),
                    Color(red: 0.76, green: 0.42, blue: 0.47)]
        case .copper:
            return [Color(red: 0.72, green: 0.44, blue: 0.28),
                    Color(red: 0.48, green: 0.27, blue: 0.17),
                    Color(red: 0.26, green: 0.13, blue: 0.08)]
        case .slate:
            return [Color(red: 0.42, green: 0.47, blue: 0.52),
                    Color(red: 0.27, green: 0.31, blue: 0.36),
                    Color(red: 0.14, green: 0.16, blue: 0.20)]
        case .aurora:
            return [Color(red: 0.24, green: 0.85, blue: 0.66),
                    Color(red: 0.32, green: 0.44, blue: 0.82),
                    Color(red: 0.56, green: 0.28, blue: 0.74)]
        case .sand:
            return [Color(red: 0.95, green: 0.86, blue: 0.70),
                    Color(red: 0.84, green: 0.70, blue: 0.49),
                    Color(red: 0.55, green: 0.40, blue: 0.24)]
        case .plusNebula:
            return [Color(red: 0.11, green: 0.07, blue: 0.24),
                    Color(red: 0.36, green: 0.14, blue: 0.53),
                    Color(red: 0.12, green: 0.32, blue: 0.62)]
        case .plusLava:
            return [Color(red: 0.88, green: 0.36, blue: 0.13),
                    Color(red: 0.55, green: 0.13, blue: 0.10),
                    Color(red: 0.16, green: 0.05, blue: 0.06)]
        case .plusGlacier:
            return [Color(red: 0.76, green: 0.91, blue: 0.95),
                    Color(red: 0.42, green: 0.68, blue: 0.84),
                    Color(red: 0.16, green: 0.34, blue: 0.54)]
        case .plusNeon:
            return [Color(red: 0.08, green: 0.06, blue: 0.16),
                    Color(red: 0.16, green: 0.86, blue: 0.78),
                    Color(red: 0.55, green: 0.24, blue: 0.92)]
        case .plusCarbon:
            return [Color(red: 0.16, green: 0.17, blue: 0.20),
                    Color(red: 0.09, green: 0.10, blue: 0.12),
                    Color(red: 0.04, green: 0.04, blue: 0.05)]
        case .plusGold:
            return [Color(red: 0.99, green: 0.87, blue: 0.53),
                    Color(red: 0.78, green: 0.57, blue: 0.18),
                    Color(red: 0.34, green: 0.22, blue: 0.06)]
        case .plusTropic:
            return [Color(red: 0.16, green: 0.72, blue: 0.62),
                    Color(red: 0.13, green: 0.50, blue: 0.47),
                    Color(red: 0.96, green: 0.76, blue: 0.35)]
        case .plusStorm:
            return [Color(red: 0.15, green: 0.18, blue: 0.24),
                    Color(red: 0.28, green: 0.34, blue: 0.42),
                    Color(red: 0.08, green: 0.10, blue: 0.13)]
        }
    }

    /// Узор поверх градиента — только у тех премиум-фонов, которым он идёт.
    ///
    /// Рисуется `Canvas`, а не картинкой: узор обязан выглядеть одинаково на
    /// плитке 88 pt в пикере и на баннере во всю ширину, а растр на такой
    /// растяжке мылится. Фигуры считаются от размера холста, поэтому и на
    /// плитке, и на баннере узор один и тот же по плотности.
    var pattern: Pattern {
        switch self {
        case .plusStorm:  return .contours
        case .plusCarbon: return .grid
        case .plusNebula: return .stars
        default:      return .none
        }
    }

    enum Pattern { case none, contours, grid, stars }

    @ViewBuilder
    func view() -> some View {
        let colors = gradient
        if colors.isEmpty {
            Color.clear
        } else {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay { ProfileBackgroundPattern(pattern: pattern) }
        }
    }

    static func from(_ raw: String?) -> ProfileBackground {
        guard let raw, !raw.isEmpty else { return .none }
        return ProfileBackground(rawValue: raw) ?? .none
    }
}

/// Узор поверх градиента. Вынесен отдельным типом, а не собран в `view()`:
/// `Canvas` внутри `@ViewBuilder` с `switch` заставлял бы SwiftUI выводить тип
/// на каждое обращение к фону, а мест показа у него четыре.
struct ProfileBackgroundPattern: View {
    let pattern: ProfileBackground.Pattern

    var body: some View {
        switch pattern {
        case .none:
            Color.clear
        case .contours:
            Canvas { context, size in
                // Горизонтали — как на топографической карте: восемь синусоид
                // с нарастающим сдвигом фазы.
                for line in 0..<8 {
                    var path = Path()
                    let base = size.height * (CGFloat(line) + 0.6) / 8.5
                    let amp = size.height * 0.055
                    let phase = CGFloat(line) * 0.8
                    path.move(to: CGPoint(x: 0, y: base))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let y = base + sin(x / max(size.width, 1) * 6.2 + phase) * amp
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 4
                    }
                    context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
        case .grid:
            Canvas { context, size in
                // Сетка меридианов и параллелей — атлас.
                let step = max(size.width, size.height) / 9
                var path = Path()
                var x: CGFloat = step
                while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = step
                while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                context.stroke(path, with: .color(.white.opacity(0.13)), lineWidth: 0.8)
            }
            .allowsHitTesting(false)
        case .stars:
            Canvas { context, size in
                // Звёзды на фиксированной сетке со сдвигом: случайных чисел
                // здесь нет нарочно — узор обязан быть одним и тем же на
                // плитке пикера и на баннере, иначе выбранное не совпадает с
                // показанным.
                for row in 0..<6 {
                    for column in 0..<9 {
                        let jitter = CGFloat((row * 7 + column * 3) % 5) / 5
                        let x = (CGFloat(column) + 0.3 + jitter * 0.5) * size.width / 9
                        let y = (CGFloat(row) + 0.3 + jitter * 0.4) * size.height / 6
                        let r = 0.7 + jitter * 1.1
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(.white.opacity(0.35 - jitter * 0.15)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Banner helper

/// Rounded rectangle banner. Used at the top of own/public profile and as a
/// thin strip behind the avatar. Height is caller-controlled.
struct ProfileBackgroundBanner: View {
    let background: ProfileBackground
    var height: CGFloat = 140

    var body: some View {
        Group {
            if background == .none {
                Color.clear
            } else {
                background.view()
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0
            )
        )
    }
}

// MARK: - Preview tile used in picker grids

struct ProfileBackgroundTile: View {
    let background: ProfileBackground
    let isSelected: Bool
    var size: CGFloat = 64

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.cardAlt)
            if background != .none {
                background.view()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Image(systemName: "slash.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? AppTheme.accent : Color.clear, lineWidth: 2.5)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, AppTheme.accent)
                    .padding(4)
            }
        }
    }
}
