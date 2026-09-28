import Combine
import CoreLocation
import Foundation

/// Дом и приватная зона: одна дверь на чтение и на правку (0.8.2).
///
/// Дом задаётся ТОЛЬКО руками — решение владельца 27 сентября. Вывод из
/// истории ночёвок у приложения есть (`JourneySuggester.home`), но он
/// отвечает на другой вопрос и регулярно показывает работу вместо двора; цена
/// ошибки здесь не досада, а обрезанный не тот кусок чужого трека.
///
/// Сам менеджер НЕ знает ни про очередь синка, ни про листы: он меняет
/// настройки и постит `.homePrivacyZoneChanged`, когда изменилось то, от чего
/// зависят УЖЕ ОТПРАВЛЕННЫЕ публичные треки. Кто на это уведомление подписан
/// — его дело.
@MainActor
final class HomeManager: ObservableObject {
    static let shared = HomeManager()

    @Published private(set) var settings: HomeSettings

    private init(settings: HomeSettings = .load()) {
        self.settings = settings
    }

    /// Поставить дом (или передвинуть уже стоящий).
    func place(at coordinate: CLLocationCoordinate2D) {
        var next = settings
        next.latitude = coordinate.latitude
        next.longitude = coordinate.longitude
        apply(next)
    }

    /// Убрать дом. Зона без точки не работает — `activeZone` станет пустым.
    func remove() {
        var next = settings
        next.latitude = nil
        next.longitude = nil
        apply(next)
    }

    func setRadius(_ radius: HomeSettings.Radius) {
        var next = settings
        next.radius = radius
        apply(next)
    }

    /// Косметика: метка на СВОЕЙ карте. Чужих глаз не касается вовсе, поэтому
    /// переотправку не заводит никогда.
    func setShowsOnMap(_ on: Bool) {
        var next = settings
        next.showsOnMap = on
        apply(next)
    }

    func setTrimsPublicTracks(_ on: Bool) {
        var next = settings
        next.trimsPublicTracks = on
        apply(next)
    }

    /// Сохранить и, если надо, позвать переотправку.
    ///
    /// **Правило симметричное: зона включена — публичные треки обрезаны, зона
    /// выключена — целые.** Одно правило в обе стороны, и человек может
    /// проверить его глазами в собственной ленте. Несимметричное («включение
    /// обрезает, выключение не возвращает») пришлось бы объяснять словами
    /// каждому и навсегда, а поездки остались бы обрезанными без способа это
    /// починить.
    ///
    /// Поэтому сравниваются не флаги, а САМА ЗОНА: изменилась та геометрия,
    /// по которой собирается пейлоад, — значит, отправленное перестало ей
    /// соответствовать.
    private func apply(_ next: HomeSettings) {
        let before = settings.activeZone
        settings = next
        next.save()
        NotificationCenter.default.post(name: .homeSettingsChanged, object: nil)
        guard zoneChanged(from: before, to: next.activeZone) else { return }
        NotificationCenter.default.post(name: .homePrivacyZoneChanged, object: nil)
    }

    /// Чистое сравнение зон — вынесено, чтобы его держал тест, а не
    /// внимательность: «зона та же» это три поля, и забыть одно легко.
    nonisolated static func zoneChanged(
        from before: (centre: CLLocationCoordinate2D, radius: Double)?,
        to after: (centre: CLLocationCoordinate2D, radius: Double)?
    ) -> Bool {
        switch (before, after) {
        case (nil, nil): return false
        case (nil, _), (_, nil): return true
        case let (old?, new?):
            return old.radius != new.radius
                || old.centre.latitude != new.centre.latitude
                || old.centre.longitude != new.centre.longitude
        }
    }

    private func zoneChanged(
        from before: (centre: CLLocationCoordinate2D, radius: Double)?,
        to after: (centre: CLLocationCoordinate2D, radius: Double)?
    ) -> Bool {
        Self.zoneChanged(from: before, to: after)
    }
}
