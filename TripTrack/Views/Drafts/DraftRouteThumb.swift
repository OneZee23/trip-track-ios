import SwiftUI
import CoreLocation

/// Миниатюра маршрута черновика: 56 × 56, радиус 12 (спека §3).
///
/// Рисует ТОТ ЖЕ `SharePosterRoute`, что миниатюра поездки на «Атласе», и это
/// не экономия: две разные нитки одного маршрута в одном приложении однажды
/// разойдутся по толщине и по вписыванию, а заметить это можно только глазами.
///
/// Точки берутся из ПРЕВЬЮ (`previewCoordinates`), а не из трека: у зрелой
/// библиотеки в треке десятки тысяч точек, и поднимать их ради квадрата в 56
/// точек нельзя — то же правило, по которому живут «Атлас» и подсказки мест.
struct DraftRouteThumb: View {
    let route: [CLLocationCoordinate2D]
    var size: CGFloat = 56

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(c.cardAlt)
            .overlay {
                if route.count > 1 {
                    GeometryReader { geo in
                        SharePosterRoute(
                            points: SharePosterView.project(route, in: geo.size, inset: 8),
                            lineWidth: 2
                        )
                    }
                } else {
                    // Трека нет вовсе — честный значок вместо пустого
                    // прямоугольника: пустота читалась бы «не загрузилось».
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: size * 0.32, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
