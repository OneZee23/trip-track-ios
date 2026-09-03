import Foundation

/// Справочник марок и моделей — тот самый «текстовый каталог», который в
/// отличие от рисунка машины безопасен юридически.
///
/// Трейд-дресс запрещает РИСОВАТЬ узнаваемую чужую модель (ITC признала
/// комбинацию элементов Jeep нарушенной в деле Roxor, 2020), но перечислять
/// марки и модели словами — то, чем живёт любой автомобильный маркетплейс.
/// Поэтому марка тут структурная, а силуэт остаётся нашим собственным
/// рисунком из `VehicleAvatar`.
///
/// Файл лежит в бандле, а не приходит с сервера: справочник нужен ровно в тот
/// момент, когда человек заводит машину, — то есть в том числе в гараже без
/// сети. 34 КБ за то, чтобы экран никогда не показал пустой список.
///
/// Ни один готовый открытый датасет не подошёл: у двух самых полных на
/// GitHub нет лицензии вовсе (значит, «все права защищены» по умолчанию), а
/// у третьего — США, 443 модели за 2024 год и ни одной Lada, УАЗа или Chery.
/// Для рынка, где половина гаража китайская, а вторая половина отечественная,
/// он бесполезен.
enum VehicleCatalog {

    struct Model: Decodable, Hashable {
        let name: String
        /// Силуэты из `VehicleAvatar.styles`. Первый — тот, что подставляется
        /// при выборе модели: назвал «Polo» — спрайт стал седаном сам.
        let bodies: [String]
        /// Народные имена модели: «Буханка» для УАЗ 3909, «Нива» для Niva Legend.
        /// По заводскому индексу такую машину не ищет никто.
        let aliases: [String]?
    }

    struct Make: Decodable, Hashable {
        let name: String
        let models: [Model]
        /// То, как марку НАБИРАЮТ, а не то, как она пишется на кузове: «тойота»,
        /// «уаз», «шкода». Имя в списке одно и латиницей — список читают на
        /// тринадцати языках, и «ГАЗ» в немецком интерфейсе нечитаем.
        let aliases: [String]?
    }

    private struct File: Decodable {
        let version: Int
        let makes: [Make]
    }

    /// Читается один раз и держится в памяти: 97 марок — это меньше, чем
    /// стоит повторный разбор JSON на каждое нажатие в поиске.
    static let makes: [Make] = load()

    private static func load() -> [Make] {
        guard let url = Bundle.main.url(forResource: "VehicleCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            // Пустой каталог — не поломка экрана: форма всегда оставляет
            // свободный ввод, и человек напечатает марку руками.
            return []
        }
        return file.makes
    }

    // MARK: - Выборка

    /// Марки, у которых есть хоть одна модель, подходящая этому типу
    /// транспорта. Показывать Toyota тому, кто только что сказал
    /// «велосипед», — это не свобода выбора, а список неправильных ответов
    /// (та же логика, что у `VehicleAvatar.styles(forType:)`).
    static func makes(forType type: String) -> [Make] {
        let allowed = Set(VehicleAvatar.styles(forType: type))
        return makes.compactMap { make in
            let models = make.models.filter { !allowed.isDisjoint(with: $0.bodies) }
            return models.isEmpty ? nil : Make(name: make.name, models: models, aliases: make.aliases)
        }
    }

    /// Поиск по подстроке — сразу и по марке, и по модели, чтобы «Solaris»
    /// нашёлся, когда человек не помнит, что это Hyundai.
    ///
    /// Ищет и по АЛИАСАМ, и без них не работает вовсе для рынка, ради которого
    /// каталог собран: имя в списке латиницей, а человек печатает «тойота»,
    /// «уаз», «шкода», «буханка». До алиасов «уаз», «лада», «ваз», «GAZ» и
    /// «Moskvich» давали ноль совпадений — а поиск здесь единственный способ
    /// добраться до марки в списке из девяноста семи.
    ///
    /// ЕДИНСТВЕННОЕ место в проекте, где регистр складывается БЕЗ языка, и это
    /// не оплошность. Домашнее правило («никогда не `lowercased()` без языка»)
    /// защищает КОПИЮ: турецкое «İ» ломает заголовок раздела. Здесь же
    /// сравниваются не фразы на языке интерфейса, а латинские имена собственные
    /// — и складывать их ПО языку как раз ломает поиск: под турецким
    /// `"INFINITI"` даёт «ınfınıtı», а `"Infiniti"` — «ınfiniti», и марка
    /// перестаёт находиться у себя же в каталоге. Это ловил тест, а не рассуждение.
    ///
    /// `folding` заодно снимает диакритику, и «Škoda» находит «Skoda»,
    /// «Citroën» — «Citroen»: пишут по-разному, машина одна.
    static func search(_ query: String, type: String) -> [Make] {
        let q = Self.fold(query)
        guard !q.isEmpty else { return makes(forType: type) }
        return makes(forType: type).compactMap { make in
            if matches(q, make.name, make.aliases) { return make }
            let hits = make.models.filter { matches(q, $0.name, $0.aliases) }
            return hits.isEmpty ? nil : Make(name: make.name, models: hits, aliases: make.aliases)
        }
    }

    /// Совпадение по имени ИЛИ по любому из народных имён.
    private static func matches(_ folded: String, _ name: String, _ aliases: [String]?) -> Bool {
        if fold(name).contains(folded) { return true }
        guard let aliases else { return false }
        return aliases.contains { fold($0).contains(folded) }
    }

    private static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Силуэт, который подставляется при выборе модели. Он всё равно
    /// проходит через `VehicleAvatar.resolveStyle(_:forType:)` — каталог
    /// предлагает, тип решает.
    static func defaultBody(for model: Model, type: String) -> String {
        let allowed = VehicleAvatar.styles(forType: type)
        return model.bodies.first(where: { allowed.contains($0) })
            ?? VehicleAvatar.defaultStyle(forType: type)
    }
}
