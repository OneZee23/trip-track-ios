import UIKit

extension UIApplication {
    /// Безопасные отступы окна — не через layout, а спросом у UIKit.
    ///
    /// Числа нужны там, где их некому разложить: они уезжают в `MKMapView`,
    /// который безопасную зону игнорирует, и в шапку экрана, которая нарочно
    /// стоит под статус-баром (`.ignoresSafeArea(.container, edges: .top)`).
    /// `GeometryReader` в этих местах вернул бы нули.
    ///
    /// Одной функцией на всё приложение, потому что копий этого обхода было
    /// ТРИ — экран поездки, полная карта, экран путешествия, — и каждая
    /// сама выбирала, у какой сцены и какого окна спросить. Значение по
    /// умолчанию оставлено вызывающему: у экрана с шапкой оно одно (59), у
    /// полноэкранной карты другое (47), и общая «правильная» цифра тут
    /// соврала бы обоим.
    ///
    /// nil — окна ещё нет (первый кадр, сцена в фоне).
    static var tt_safeAreaInsets: UIEdgeInsets? {
        tt_keyWindow?.safeAreaInsets
    }

    /// Высота окна — для тех, кому нужно расстояние до ФИЗИЧЕСКОГО низа
    /// экрана, а не до края безопасной зоны (см. `measuredBottomOverlay`).
    static var tt_windowHeight: CGFloat? {
        tt_keyWindow?.bounds.height
    }

    private static var tt_keyWindow: UIWindow? {
        shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first
    }
}
