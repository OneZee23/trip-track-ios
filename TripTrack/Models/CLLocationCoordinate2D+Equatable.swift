import CoreLocation

/// SDK не даёт `CLLocationCoordinate2D` сравнение из коробки, а без него
/// `JourneyAggregate` и `Item` не синтезируют `Equatable` (нужен тестам и
/// экрану путешествия для сравнения снапшотов).
///
/// Своим файлом, а не приложением к `JourneyAggregate`: соответствие ЧУЖОГО
/// типа чужому протоколу видно всему таргету, и искать его внутри модели
/// путешествия никто не станет — а вторая такая же попытка не соберётся.
/// `public` не убрать: тип чужой и публичный, значит и соответствие выходит
/// публичным, а свидетель требования обязан быть не уже него — компилятор
/// отвечает «method '==' must be declared public». В таргете приложения это
/// ничего не открывает наружу: модуль всё равно никто не импортирует.
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
