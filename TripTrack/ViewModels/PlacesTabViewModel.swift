import Foundation
import Combine

/// Список вкладки «Места»: считается на загрузке и по `.placesChanged`,
/// а не в `body` — `passes(for:)` ходит в CoreData на каждое место.
///
/// Вторая половина экрана — подсказки «Похоже, вы здесь бываете»
/// (`PlaceSuggestions`). Их счёт разбирает превью ВСЕЙ библиотеки, поэтому
/// идёт вне главного актёра и с задержкой: сверка мест постит `.placesChanged`
/// на каждой поездке с изменениями, и без склейки первый запуск после
/// обновления пересчитывал бы подсказки сотню раз подряд.
@MainActor
final class PlacesTabViewModel: ObservableObject {
    @Published private(set) var items: [PlaceListItem] = []
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    /// Последние поездки — секция «Отметить в поездке» у новичка (S3).
    /// Отметку ставят В ПОЕЗДКЕ, и пока мест нет, дорога туда — единственное
    /// действие, которое вообще есть на этой вкладке кроме подсказки.
    @Published private(set) var recentTrips: [Trip] = []
    /// «Дача · вчера · на 7 мин быстрее обычного» — одна строка над списком,
    /// ответ вкладки на «зачем сюда возвращаться» (спека §3.6). Правило
    /// целиком живёт в `PlaceLastPass`; здесь только выбор места и гашение.
    @Published private(set) var lastPass: PlaceLastPass.Reading?

    /// Сколько поездок показывать в «Отметить в поездке». Три — это «недавно»;
    /// дальше это уже лента, а она на своей вкладке.
    static let recentTripsShown = 3
    private let manager: PlaceManager
    private let repository: TripRepository
    private var cancellables = Set<AnyCancellable>()
    private var suggestionTask: Task<Void, Never>?

    /// Окно склейки заказов на пересчёт подсказок. Не `let` — тест не должен
    /// ждать треть секунды на каждую проверку.
    var suggestionDebounce: TimeInterval = 0.3

    init(manager: PlaceManager = .shared, repository: TripRepository = CoreDataTripRepository()) {
        self.manager = manager
        self.repository = repository
        // Одна подписка: все пути, что меняют места (rename/delete/adoptName/
        // reconcile/process), постят `.placesChanged` сами — вторая, на
        // `$places`, значила бы два reload() на одну и ту же правку.
        NotificationCenter.default.publisher(for: .placesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        // Подсказки живут не только местами: новая поездка добавляет конец
        // маршрута, а пул привозит поездки со второго телефона — ни то, ни
        // другое `.placesChanged` не постит.
        for name in [Notification.Name.tripRecordingEnded, .syncPullCompleted] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshSuggestions() }
                .store(in: &cancellables)
        }
        // Без этого первый кадр вкладки рисует пустую сцену «Мест пока нет»,
        // которую тут же сменяет список: `items` иначе заполняется только
        // асинхронно, по подписке.
        reload()
    }

    /// Что уже показано и погашено: строка живёт до следующей сохранённой
    /// поездки ИЛИ до открытия этого места, что раньше. Второе — действие
    /// человека, и пережить переключение вкладки оно обязано: вью-модель
    /// `ContentView` пересоздаёт на каждом переходе.
    private static let seenKey = "places.lastPassSeen"

    func reload() {
        let places = manager.places
        var passesByPlace: [UUID: [PlacePass]] = [:]
        items = PlaceListItem.sorted(places.map { place in
            let passes = manager.passes(for: place.id)
            passesByPlace[place.id] = passes
            return PlaceListItem.build(place: place, passes: passes)
        })
        lastPass = freshestReading(passesByPlace)
        // Поднимаются только когда их будут показывать: у человека с сотней
        // мест эта секция не рисуется, и выборка ему ни к чему.
        recentTrips = items.isEmpty ? repository.fetchTrips(limit: Self.recentTripsShown, offset: 0) : []
        refreshSuggestions()
    }

    /// Самый свежий проезд по всем местам — и только если он ещё не погашен.
    ///
    /// Место выбирается по ВРЕМЕНИ проезда, а не по числу проездов: вопрос
    /// строки «что было в последней поездке», и ответ на него один.
    private func freshestReading(_ passes: [UUID: [PlacePass]]) -> PlaceLastPass.Reading? {
        let readings = passes.compactMap { PlaceLastPass.reading(placeId: $0.key, passes: $0.value) }
        guard let best = readings.max(by: { $0.at < $1.at }) else { return nil }
        return Self.seenKeyValue(best) == UserDefaults.standard.string(forKey: Self.seenKey)
            ? nil : best
    }

    /// Ключ гашения — место И ВРЕМЯ проезда: следующая поездка через то же
    /// место даёт другое время, и строка появляется снова сама.
    private static func seenKeyValue(_ reading: PlaceLastPass.Reading) -> String {
        "\(reading.placeId.uuidString)|\(Int(reading.at.timeIntervalSince1970))"
    }

    /// Человек открыл это место — сравнение он увидел, и строка гаснет.
    func markLastPassSeen() {
        guard let reading = lastPass else { return }
        UserDefaults.standard.set(Self.seenKeyValue(reading), forKey: Self.seenKey)
        lastPass = nil
    }

    /// Человек согласился: подсказка становится местом тем же путём, что
    /// отметка (`PlaceManager.createPlace` — шестой вход). Из списка она
    /// уходит сразу, не дожидаясь `.placesChanged`: кнопка обязана ответить
    /// в момент нажатия, а бэкфилл истории идёт секунды.
    func save(_ suggestion: PlaceSuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
        manager.createPlace(cell: suggestion.cell, coordinate: suggestion.coordinate, name: suggestion.name)
    }

    /// Последняя своя поездка — куда ведёт «Открыть последнюю поездку» с
    /// карточки «Как появляются места». Превью уже отсортированы по дате.
    var lastTripId: UUID? { repository.tripPreviews(needingPlaceMatch: false).first?.id }

    /// Заказ на пересчёт. Выборка превью тоже внутри задачи, ПОСЛЕ паузы:
    /// она читает `viewContext`, и сто заказов подряд — это сто выборок с
    /// блобами на главном потоке.
    private func refreshSuggestions() {
        suggestionTask?.cancel()
        let debounce = suggestionDebounce
        suggestionTask = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            let previews = self.repository.tripPreviews(needingPlaceMatch: false)
            // Надгробия — отметки, чьё место удалили: предлагать их заново
            // значит воскрешать то, от чего человек отказался.
            let taken = Set(self.manager.places.map(\.id)).union(self.repository.checkpointPlaceIds())
            let found = await PlaceSuggestions.buildDetached(previews: previews, taken: taken)
            guard !Task.isCancelled else { return }
            self.suggestions = found.map { suggestion in
                var named = suggestion
                // Только кэш геокодера: своего запроса подсказка не делает —
                // пять сетевых кругов на открытие вкладки. Нет имени — нет и
                // координаты в строке, экран скажет «Точка на карте».
                let cached = self.repository.cachedGeocode(for: suggestion.coordinate)
                named.name = [cached?.locality, cached?.region]
                    .compactMap { $0 }
                    .first { !$0.isEmpty }
                return named
            }
        }
    }
}
