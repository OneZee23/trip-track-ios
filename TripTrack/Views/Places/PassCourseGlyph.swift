import SwiftUI

/// Кружок с курсовой стрелкой — ОДИН на обе плашки экрана места.
///
/// До фикс-волны 0.7.0 их было два: в «Обычно занимает» — кружок 32 pt, в
/// строке проезда — голая стрелка в рамке 20 pt. Два разных ведущих элемента
/// сдвигали колонки текста двух карточек друг относительно друга, и одно и то
/// же «1 ч 19 мин» стояло в них на разном отступе — это и увидел владелец.
/// Поэтому размер, вставка и отступ до текста здесь, а не у экранов: разъехаться
/// им больше нечем.
///
/// Курс — `PlacePass.unknownCourse` (`-1`), когда ни у точки, ни у соседей его
/// не было: стрелка тогда врала бы направлением, и на её месте стоит точка.
struct PassCourseGlyph: View {
    let course: Double

    @Environment(\.colorScheme) private var scheme

    /// Обе плашки считают начало колонки текста от этого числа — 14 (внутренний
    /// отступ карточки) + 40 + 12 (зазор). Меняешь — меняется в обеих сразу.
    static let diameter: CGFloat = 40
    /// Зазор до текста, общий для обеих плашек.
    static let spacing: CGFloat = 12

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack {
            Circle().fill(AppTheme.accentBg)
            if course >= 0 {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .rotationEffect(.degrees(course))
            } else {
                Circle()
                    .fill(c.textTertiary)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        // Направление уже сказано словами в строке рядом («в сторону Джубги»),
        // а курс в градусах VoiceOver ничего не отвечает.
        .accessibilityHidden(true)
    }
}
