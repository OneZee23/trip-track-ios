import SwiftUI
import MapKit

/// Мини-карта для карточки «Где была»: настоящая подложка MapKit с маршрутами
/// поверх, снятая в картинку.
///
/// Именно снимок (`MKMapSnapshotter`), а не живой `MKMapView`: карточка стоит
/// в прокручиваемом списке рядом с другими, и живая карта там платит за себя
/// каждым кадром прокрутки. Снимок делается один раз, а тап уводит на полный
/// экран, где карта уже настоящая и интерактивная.
///
/// До этого здесь был `LightRoutePreview` — маршруты на плоской заливке. На
/// макете это выглядело картой, а на устройстве оказалось двумя красными
/// закорючками в пустоте: без подложки не видно ни где это, ни какого размера.
struct VehicleMiniMap: View {
    let routes: [[CLLocationCoordinate2D]]

    @Environment(\.colorScheme) private var scheme
    @State private var image: UIImage?
    @State private var renderedFor: String = ""

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    c.cardAlt
                }
            }
            .task(id: key(geo.size)) { await render(size: geo.size) }
        }
    }

    /// Пересъёмка только когда меняется то, что видно: набор маршрутов и
    /// размер. Без ключа `.task` дёргался бы на каждую перерисовку списка.
    private func key(_ size: CGSize) -> String {
        "\(routes.count)-\(Int(size.width))x\(Int(size.height))-\(scheme == .dark)"
    }

    private func render(size: CGSize) async {
        guard size.width > 1, size.height > 1 else { return }
        let k = key(size)
        guard renderedFor != k else { return }
        let points = routes.flatMap { $0 }
        guard points.count >= 2 else { return }

        let options = MKMapSnapshotter.Options()
        options.region = Self.region(covering: points)
        options.size = size
        options.traitCollection = UITraitCollection(
            userInterfaceStyle: scheme == .dark ? .dark : .light)
        options.pointOfInterestFilter = .excludingAll
        // Подписи городов на 130 pt высоты превращаются в кашу, а карточка
        // отвечает на вопрос «где примерно», а не «как называется вон тот
        // посёлок» — для этого есть полноэкранная карта.
        options.showsBuildings = false

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }
        let drawn = Self.draw(routes: routes, on: snapshot, size: size)
        guard !Task.isCancelled else { return }
        renderedFor = k
        image = drawn
    }

    /// Общая рамка вокруг всех точек с запасом, чтобы маршрут не упирался в край.
    private static func region(covering points: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for p in points {
            minLat = min(minLat, p.latitude);  maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        // Минимум в 0.02° — иначе одна короткая поездка растягивается до
        // масштаба двора и карта перестаёт что-либо объяснять.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.02))
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func draw(routes: [[CLLocationCoordinate2D]],
                             on snapshot: MKMapSnapshotter.Snapshot,
                             size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            snapshot.image.draw(at: .zero)
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor(AppTheme.accent).cgColor)
            cg.setLineWidth(3)
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            for route in routes where route.count >= 2 {
                var first = true
                for coord in route {
                    let p = snapshot.point(for: coord)
                    if first { cg.move(to: p); first = false } else { cg.addLine(to: p) }
                }
                cg.strokePath()
            }
        }
    }
}
