import Foundation
import CoreLocation

/// Отметка на маршруте: «вот здесь мы были, и вот сколько это заняло».
///
/// Появилась из простого желания за рулём: едешь из Краснодара в Геленджик и
/// хочешь знать, сколько времени до моря, — не до конца поездки, а до КОНКРЕТНОГО
/// места на ней. Поставить такую отметку можно двумя способами: кнопкой на
/// Live Activity прямо на ходу или пальцем по маршруту, когда поездка уже
/// записана. Получается одно и то же — потому это одна сущность, а не две.
///
/// Отвечать на «сколько до этой точки» стало можно только с 0.6.5: до неё точки
/// трека лежали в пяти метрах, а на медленном ходу в трёх с половиной секундах
/// друг от друга, и ответ был бы приблизительным.
///
/// **`placeId` в 0.6.5 всегда пуст, и это задел, а не забытое поле.** Отметка
/// принадлежит одной поездке; следующим шагом та же точка станет МЕСТОМ, которое
/// узнаётся на каждой поездке мимо, и тогда «сколько до моря» превратится в
/// историю: 2:14, 2:31, 2:08. Место потребует своей сущности и узнавания на
/// чужом треке — но не потребует второй миграции и переделки отметок.
struct TripCheckpoint: Identifiable, Codable, Equatable {
    let id: UUID
    /// Момент, которому соответствует отметка: нажатие кнопки на ходу либо
    /// время ближайшей точки трека, если её ставили пальцем по карте.
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Метры от старта поездки по треку — не по прямой.
    var distanceFromStart: Double
    /// Секунды от старта поездки.
    var elapsedFromStart: TimeInterval
    /// Имя от человека: «море», «заправка», «пост ДПС». Пустое — законно:
    /// на ходу подписывать некогда, а отметка нужна сразу.
    var name: String?
    /// Обложка — снимок, который человек выбрал лицом отметки. Пусто —
    /// обложкой становится первый прикреплённый, иначе ближайший по времени.
    var photoId: UUID?
    /// Снимки, прикреплённые к отметке рукой, в порядке прикрепления. Кадры,
    /// которые попали к отметке по времени или месту, здесь НЕ хранятся —
    /// они выводятся (`TripCheckpointPhotos`), и старые поездки получают их
    /// бесплатно. Предела по числу нет: карта и лента показывают обложку и
    /// «+N», редактор — полку с прокруткой.
    var photoIds: [UUID] = []
    /// Задел под «место» (см. доккомент типа). В 0.6.5 всегда `nil`.
    var placeId: UUID?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceKm: Double { distanceFromStart / 1000 }

    init(
        id: UUID = UUID(),
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        distanceFromStart: Double,
        elapsedFromStart: TimeInterval,
        name: String? = nil,
        photoId: UUID? = nil,
        photoIds: [UUID] = [],
        placeId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.distanceFromStart = distanceFromStart
        self.elapsedFromStart = elapsedFromStart
        self.name = name
        self.photoId = photoId
        self.photoIds = photoIds
        self.placeId = placeId
    }
}
