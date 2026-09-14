import SwiftUI

/// Строка плеча: миниатюра 56×44, заголовок, подпись, любой trailing.
/// Общая для листа сборки (галочка) и листа публикации («сейчас приватная»).
///
/// Вынесено из `JourneyComposerSheet.row`/`.thumbnail` (0.6.8) — Button,
/// нажатие, рамка и высота опорной строки остаются в композере, здесь только
/// содержимое лейбла.
///
/// Отклонение от брифа: добавлен необязательный `caption` (третья строка —
/// «Эта поездка» у опорной поездки в листе сборки, `nil` у листа публикации,
/// который её не знает). В исходнике композера все три строки жили в ОДНОМ
/// `VStack`, и именно это давало опорной строке её лишние 6 пунктов высоты
/// (`anchorRowHeight`, посчитанная под три строки текста). Вынести подпись
/// НАРУЖУ, под весь `HStack`, изменило бы вертикальное центрирование
/// галочки относительно текста — а требование задачи «вид без изменений»
/// проверяется снимком экрана, а не на глаз.
struct JourneyLegRow<Trailing: View>: View {
    let trip: Trip
    let subtitle: String
    let language: LanguageManager.Language
    /// «Эта поездка» у опорной поездки листа сборки. `nil` — третья строка
    /// не рисуется (лист публикации).
    var caption: String? = nil
    var captionColor: Color = AppTheme.accent
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    static var thumbWidth: CGFloat { 56 }
    static var thumbHeight: CGFloat { 44 }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(spacing: 12) {
            thumbnail(c)
            VStack(alignment: .leading, spacing: 2) {
                Text(JourneyFormat.tripTitle(trip, language: language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10.5, weight: .heavy))
                        .foregroundStyle(captionColor)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }

    /// Меньше двух точек — `MapSnapshotPreview` возвращается ДО того, как
    /// успевает признать себя неудачей, и мерцает вечно: целая колонка такого
    /// читается как экран, который всё ещё грузится. Заглушка уменьшена до
    /// миниатюры, как на плитках «Моих».
    @ViewBuilder
    private func thumbnail(_ c: AppTheme.Colors) -> some View {
        let coords = trip.previewCoordinates
        Group {
            if coords.count > 1 {
                MapSnapshotPreview(
                    coordinates: coords,
                    tripId: trip.id,
                    height: Self.thumbHeight,
                    width: Self.thumbWidth
                )
            } else {
                ZStack {
                    Rectangle().fill(c.card)
                    Image(systemName: "map.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
            }
        }
        .frame(width: Self.thumbWidth, height: Self.thumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
