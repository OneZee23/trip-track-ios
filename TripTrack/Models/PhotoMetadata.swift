import Foundation
import ImageIO
import Photos
import UIKit

/// Что кадр знает о себе сам: когда снят и где.
///
/// Спросить об этом можно ровно один раз — в момент добавления.
/// `PhotoStorageService.savePhoto` пересжимает снимок в свой JPEG, и файл в
/// Documents уже не помнит ни времени съёмки, ни координаты; восстановить их
/// потом неоткуда. А без них `TripPhotoPlacement` не ставит кадр на карту
/// вовсе, и `TripCheckpointPhotos` не привязывает его к отметке — то есть
/// «фото на карте» и лента «Моменты» молча не работают.
///
/// Читателя два, потому что снимок приходит двумя дверями. Разбор при этом
/// ОДИН, здесь: разъехавшись, две двери дали бы один и тот же кадр в двух
/// разных местах карты.
///
/// - **Байты кадра** (`read(fromImageData:)`) — системный `PhotosPicker`
///   (экран финиша). Разрешения на библиотеку он не просит, и просить нельзя:
///   человек выбрал конкретный кадр, приложение получило его файл, а EXIF
///   лежит в этом файле. `PHAsset` тут недоступен вдвойне —
///   `PhotosPickerItem.itemIdentifier` пуст, пока пикер не собран с явным
///   `photoLibrary:`, а спросить по нему библиотеку значило бы затребовать
///   доступ ко ВСЕЙ галерее ради того, что и так лежит в байтах. Плата
///   приватностью за уже полученные данные — не сделка.
/// - **`PHAsset`** (`read(from:)`) — свой пикер `TripPhotoPicker`, который
///   библиотеку и так читает и у которого координата есть даже там, где кадр
///   её не несёт (Photos помнит место отдельно от файла).
///
/// Геометки в кадре может не быть — их выключают, а мессенджер срезает их
/// всегда. Это не тупик: со временем съёмки место считается по треку
/// (`TripPhotoPlacement`, источник `.track`), и ради этого случая в 0.6.5
/// делалась плотность точек.
enum PhotoMetadata {

    /// Ровно те три поля, которые умеет хранить `TripPhoto`.
    struct Fields: Equatable {
        var capturedAt: Date?
        var latitude: Double?
        var longitude: Double?

        /// Кадр не сказал о себе ничего. Отдельное имя — чтобы «ничего не
        /// нашли» нельзя было спутать с «не спрашивали».
        static let none = Fields(capturedAt: nil, latitude: nil, longitude: nil)

        var isEmpty: Bool { self == .none }
    }

    // MARK: - Байты кадра

    /// Метаданные из самих байтов снимка.
    ///
    /// Ничего не додумывает: нет тега — нет значения. Догадка тут стоила бы
    /// дороже пустоты, потому что кадр, поставленный по чужому времени,
    /// уезжает на сотню километров от места съёмки, и человеку не за что
    /// зацепиться, чтобы понять, что карта врёт.
    static func read(fromImageData data: Data) -> Fields {
        // Свойства, а не пиксели: декодировать кадр незачем.
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return .none }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let coordinate = coordinate(gps: gps)

        return Fields(
            capturedAt: capturedAt(exif: exif),
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude)
    }

    // MARK: - Библиотека фотографий

    /// Метаданные из библиотеки — там же, где взят сам кадр.
    static func read(from asset: PHAsset) -> Fields {
        Fields(
            capturedAt: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude)
    }

    // MARK: - Время съёмки

    /// Спрашиваются только «когда снято» и «когда оцифровано» — и ни в коем
    /// случае не `TIFF/DateTime`: там время последней ПРАВКИ файла, которое у
    /// кадра, прошедшего через редактор, отличается от съёмки на дни. Это та
    /// же ошибка, из-за которой на карту не ставятся снимки до 0.6.5, только
    /// въехавшая бы в новые.
    private static func capturedAt(exif: [CFString: Any]) -> Date? {
        let stamp = (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifDateTimeDigitized] as? String)
        guard let stamp, !stamp.hasPrefix("0000") else { return nil }

        // EXIF пишет местное время камеры без зоны. Смещение есть отдельным
        // тегом далеко не всегда: без него берём зону телефона — человек
        // добавляет снимок к поездке, которую только что проехал, и это
        // единственная зона, о которой вообще что-то известно.
        let offset = (exif[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            ?? (exif[kCGImagePropertyExifOffsetTimeDigitized] as? String)
        if let offset, let zoned = Self.zonedStamp.date(from: stamp + offset) {
            return zoned
        }
        return Self.localStamp.date(from: stamp)
    }

    private static let stampFormat = "yyyy:MM:dd HH:mm:ss"

    /// Без `timeZone` — форматтер берёт системную, то есть ту, по которой
    /// человек сейчас едет.
    private static let localStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = stampFormat
        return f
    }()

    private static let zonedStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = stampFormat + "XXXXX"
        return f
    }()

    // MARK: - Координата

    /// EXIF хранит широту и долготу положительными, а полушарие — отдельной
    /// буквой. Забыть про букву значит увезти южное в северное.
    private static func coordinate(gps: [CFString: Any]) -> (latitude: Double, longitude: Double)? {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double,
              lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180
        else { return nil }

        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        let signedLat = (latRef == "S" || latRef == "s") ? -lat : lat
        let signedLon = (lonRef == "W" || lonRef == "w") ? -lon : lon

        // Ровный ноль в обеих координатах — не место в Гвинейском заливе, а
        // незаполненное поле: так пишут кодировщики, которые завели словарь
        // GPS и ничего в него не положили.
        guard signedLat != 0 || signedLon != 0 else { return nil }
        return (signedLat, signedLon)
    }
}

/// Снимок вместе с тем, что о нём известно на момент выбора.
///
/// Живёт рядом с `PhotoMetadata` нарочно: тип существует ровно затем, чтобы
/// донести метаданные от пикера до `TripManager.addPhoto` — дальше их уже
/// негде взять.
struct PickedPhoto: Equatable {
    let image: UIImage
    let meta: PhotoMetadata.Fields
}
