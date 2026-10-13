import MapKit
import SwiftUI
import UIKit

/// Метка дома. Одна на две карты: «Атлас» и экран настройки дома.
///
/// Своим классом, а не через `PlacePinView`: булавка места отвечает на «сюда
/// я езжу», а дом — на «отсюда я езжу», и путать их нельзя ни глазом, ни
/// кодом. Размеры булавок мест в 0.8.2 заморожены решением владельца, и лезть
/// в них ради дома тем более незачем.
final class HomeAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

/// Диск с домиком: заливка акцентом, белая обводка и тень — чтобы читался и
/// на светлой бумаге «Атласа», и на тёмной мгле «Ночи», и на обычной карте
/// экрана настройки.
final class HomePinView: MKAnnotationView {
    static let reuseID = "HomePin"

    private static let size: CGFloat = 28

    private let disc = UIView()
    private let glyph = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        centerOffset = .zero
        collisionMode = .circle
        // Дом побеждает всё: он один на карте, и прятать его под подписью
        // региона или под булавкой места незачем.
        displayPriority = .required
        canShowCallout = false
        // Метка НАЗЫВАЕТСЯ вслух и находится тестом: без имени она для
        // VoiceOver безымянная кнопка, а для сторожа — ничто.
        isAccessibilityElement = true
        accessibilityIdentifier = "home_pin"

        disc.frame = bounds
        disc.layer.cornerRadius = Self.size / 2
        disc.backgroundColor = UIColor(AtlasTheme.accent)
        disc.layer.borderColor = UIColor.white.cgColor
        disc.layer.borderWidth = 2
        disc.layer.shadowColor = UIColor.black.cgColor
        disc.layer.shadowOpacity = 0.18
        disc.layer.shadowRadius = 3
        disc.layer.shadowOffset = CGSize(width: 0, height: 1.5)
        disc.isUserInteractionEnabled = false
        addSubview(disc)

        glyph.image = UIImage(systemName: "house.fill",
                              withConfiguration: UIImage.SymbolConfiguration(
                                pointSize: 13, weight: .semibold))
        glyph.tintColor = .white
        glyph.contentMode = .center
        glyph.frame = bounds
        disc.addSubview(glyph)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
