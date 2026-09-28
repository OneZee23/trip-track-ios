import XCTest
@testable import TripTrack

/// Сторож самого главного правила приватной зоны: **режется то, что уходит с
/// телефона, и больше НИГДЕ**.
///
/// Своя поездка на своём телефоне остаётся целой всегда — это история
/// человека, и прятать её от него самого не от кого. Обрезка живёт на ОДНОЙ
/// границе, в сборке `TripSyncPayload`; позови её в `body`, в «Атласе», в
/// экспорте GPX или в сборке слоя открытого — и человек перестанет видеть
/// собственный двор на собственной карте, а заметит это не сборка и не тест, а
/// он сам, через месяц, когда локального полного трека уже нигде не будет.
///
/// Проверить это поведением нельзя: экран, который напишут в следующей волне и
/// который спросит `PrivacyZone.trim` прямо при отрисовке, соберётся и пройдёт
/// весь набор. Поймать такое можно только там, где оно случается — в тексте
/// файла. Инструмент тот же, что у `UnitsDisciplineTests` и
/// `NoLiveSecretPromptsTests` (`UnitGuard`): корень от `#filePath`, комментарии
/// сняты, allowlist парами «путь + ПРИЧИНА».
///
/// Полей у класса нет намеренно — сторожу нечего хранить между тестами.
final class PrivacyZoneDisciplineTests: XCTestCase {

    /// Ищется имя С ТОЧКОЙ, а не голое.
    ///
    /// `Notification.Name.homePrivacyZoneChanged` СОДЕРЖИТ «PrivacyZone»
    /// подстрокой, и голый токен краснел бы на каждом, кто просто слушает
    /// смену зоны, — то есть на законной половине механизма. Резать умеют
    /// ровно три функции, и все три зовутся через точку.
    private static let tokens = ["PrivacyZone."]

    /// Места, где имя обрезки — норма, а не нарушение.
    ///
    /// `allowedPaths`, а не `allowlist`: сам файл обрезки проверять на
    /// «а нужна ли ещё эта строка» бессмысленно — он и есть предмет.
    private static let allowedPaths: [(path: String, reason: String)] = [
        ("TripTrack/Models/PrivacyZone.swift",
         "Сама обрезка.")
    ]

    /// Прощённые файлы — каждый с причиной словами.
    ///
    /// Строка здесь обязана быть ВИДИМЫМ РЕШЕНИЕМ в диффе: добавленный путь
    /// ревьюер пролистает, путь с причиной — нет. Не пишется причина — значит
    /// места в списке нет, и резать оттуда нельзя.
    private static let allowlist: [(path: String, reason: String)] = [
        ("TripTrack/Models/Sync/TripSyncPayload.swift",
         "ГРАНИЦА ОТПРАВКИ — единственное место, где трек режется. Оба носителя "
         + "геометрии (`trackPoints` и `previewPolyline`) уходят отсюда, и обрезаны "
         + "они здесь же, в `wireTrack`/`wirePreview`. Числа поездки считаются ВЫШЕ, "
         + "по полному треку: они про саму поездку, а не про то, что видно чужим.")
    ]

    private static let scannedDirs = ["TripTrack", "TripTrackShared", "TripTrackLiveActivity"]

    // MARK: Чтение исходников

    private struct Violation {
        let path: String
        let line: Int
        let token: String
        let text: String
    }

    private static let sourceRoot = UnitGuard.repoRoot()

    private static let sourcesExist = FileManager.default.fileExists(
        atPath: sourceRoot.appendingPathComponent("TripTrack").path)

    private static let files: [UnitGuard.SourceFile] =
        sourcesExist ? UnitGuard.read(dirs: scannedDirs, root: sourceRoot) : []

    /// Упоминания БЕЗ учёта allowlist — прощение идёт отдельным шагом, чтобы
    /// вторым тестом можно было спросить «а нужна ли ещё эта строка».
    private static let rawMentions: [Violation] = files.flatMap { file -> [Violation] in
        guard !inAllowedDir(file.path) else { return [] }
        return scan(file, tokens: tokens)
    }

    private static func scan(_ file: UnitGuard.SourceFile, tokens: [String]) -> [Violation] {
        var out: [Violation] = []
        for (index, line) in file.code.enumerated() {
            for token in tokens where line.contains(token) {
                out.append(Violation(path: file.path, line: index + 1, token: token,
                                     text: line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
    }

    private static func inAllowedDir(_ path: String) -> Bool {
        allowedPaths.contains { path == $0.path || path.hasPrefix($0.path + "/") }
    }

    private static func allowed(_ path: String) -> Bool {
        allowlist.contains { path == $0.path }
    }

    private func requireSources() throws {
        guard Self.sourcesExist else {
            throw XCTSkip(
                "Исходников рядом с тестом нет (\(Self.sourceRoot.path)) — сторожу нечего читать")
        }
    }

    // MARK: Собственно проверка

    func testTrimmingLivesOnlyAtTheSendBoundary() throws {
        try requireSources()
        let found = Self.rawMentions.filter { !Self.allowed($0.path) }

        for violation in found.prefix(25) {
            XCTFail("""

                \(violation.path):\(violation.line) — «\(violation.token)» вне сборки пейлоада.
                  строка: \(violation.text.prefix(160))
                  режется только то, что УХОДИТ С ТЕЛЕФОНА. Своя поездка на своём \
                телефоне остаётся целой всегда: обрежь её на показе — и человек \
                перестанет видеть собственный двор, а полного трека взять уже будет \
                неоткуда. Появилась новая законная дверь на сервер — впиши файл в \
                `allowlist` в `PrivacyZoneDisciplineTests` ВМЕСТЕ С ПРИЧИНОЙ.
                """)
        }
        XCTAssertTrue(found.isEmpty, "Мест, режущих трек мимо границы отправки: \(found.count)")
    }

    /// Граница отправки обязана СУЩЕСТВОВАТЬ. Без этой проверки сторож остался
    /// бы зелёным и на дне, где обрезку просто выкинули: ноль упоминаний — это
    /// и «никто не нарушает», и «никто не режет».
    func testTheSendBoundaryStillTrims() throws {
        try requireSources()
        let payload = Self.files.first { $0.path == "TripTrack/Models/Sync/TripSyncPayload.swift" }
        let lines = try XCTUnwrap(payload, "пейлоад не прочитался — сторож смотрит не туда").code
        XCTAssertTrue(lines.contains { $0.contains("PrivacyZone.trim(points:") },
                      "трек больше не режется на отправке")
        XCTAssertTrue(lines.contains { $0.contains("PrivacyZone.trim(coordinates:") },
                      "превью больше не режется на отправке — карточка в чужой ленте рисует именно его")
    }

    /// Allowlist не имеет права заплывать жиром: файл однажды почистят, а
    /// строка останется — и дыра будет ровно там, где её никто не ищет.
    func testEveryAllowlistLineIsStillNeeded() throws {
        try requireSources()
        let mentioning = Set(Self.rawMentions.map(\.path))
        for entry in Self.allowlist {
            XCTAssertTrue(mentioning.contains(entry.path), """

                `\(entry.path)` больше не режет трек — удали строку из `allowlist` \
                в `PrivacyZoneDisciplineTests`.
                  причина, которая там записана: \(entry.reason)
                """)
        }
    }

    // MARK: Сам сторож под сторожем

    /// Тест, который проверяет ТЕСТ: на подброшенных строках он обязан
    /// сработать, а на законном слушателе зоны — промолчать. Без этого сторож
    /// — самый опасный вид зелёного: читает файлы, ничего не находит и
    /// выглядит работающим, даже если смотрит не туда.
    func testTheGuardCatchesPlantedLinesAndSparesTheListener() {
        let planted = """
            struct RouteMapView: UIViewRepresentable {
                func makeUIView(context: Context) -> MKMapView {
                    // двор бы не показывать
                    let shown = PrivacyZone.trim(points: trip.trackPoints, centre: c, radius: r)
                    map.addOverlay(MKPolyline(coordinates: shown, count: shown.count))
                }
            }
            """
        let (code, _) = UnitGuard.strip(planted)
        XCTAssertTrue(code.contains { line in Self.tokens.contains { line.contains($0) } },
                      "сторож не увидел обрезку на показе")
        // А комментарий про двор нарушением НЕ является: объяснение словами —
        // это документ, а не вызов.
        XCTAssertFalse(code.joined().contains("двор бы не показывать"), "комментарии не сняты")

        let listener = """
            NotificationCenter.default.publisher(for: .homePrivacyZoneChanged)
                .sink { _ in self.resendPublishedTrips() }
            """
        let (listenerCode, _) = UnitGuard.strip(listener)
        XCTAssertFalse(listenerCode.contains { line in Self.tokens.contains { line.contains($0) } },
                       "слушатель смены зоны — не обрезка; токен обязан быть С ТОЧКОЙ")
    }
}
