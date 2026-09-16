import XCTest
@testable import TripTrack

/// Сторож самого главного правила находок: **всё считается ПОСЛЕ финиша**.
///
/// Приложение не имеет права звать человека свернуть с дороги — ни подсказкой
/// «рядом секрет», ни звуком, ни уведомлением на ходу. Это не вопрос вкуса:
/// секрет, о котором сказали в движении, превращает дорогу в охоту, а охота за
/// рулём кончается плохо. Поэтому матчеры и процессор зовутся ровно из одного
/// места — из цепочки финиша, — и внутри своей папки не знают ни про GPS, ни
/// про уведомления, ни про звук.
///
/// Проверить это поведением нельзя: экран, который напишут в следующей волне и
/// который спросит `SecretMatcher` прямо в `body`, соберётся и пройдёт весь
/// набор. Поймать такое можно только там, где оно случается — в тексте файла.
/// Инструмент тот же, что у `UnitsDisciplineTests` (`UnitGuard`): корень от
/// `#filePath`, комментарии сняты, allowlist парами «путь + ПРИЧИНА».
///
/// Полей у класса нет намеренно — сторожу нечего хранить между тестами.
final class NoLiveSecretPromptsTests: XCTestCase {

    // MARK: Правило A — кто вообще смеет звать разбор

    /// Имена, которые за пределами разрешённых мест не должны встречаться.
    private static let matcherTokens = ["SecretMatcher", "RiddleMatcher", "DiscoveryProcessor"]

    /// Места, где имя разбора — это норма, а не нарушение: сама папка находок
    /// и два экрана волны.
    ///
    /// `Views/MyMap` — «Атлас»: показывает УЖЕ найденное и подсказки загадок по
    /// открытой территории, то есть читает базу, а не зовёт матчеры на ходу.
    /// Экран итогов — единственное место, где находка произносится вслух, и он
    /// тоже читает готовую сводку. Обоим сейчас звать разбор незачем, поэтому
    /// «строка ещё нужна?» с них НЕ спрашивается: это разрешённые места, а не
    /// прощённые нарушения.
    private static let allowedPaths: [(path: String, reason: String)] = [
        ("TripTrack/Services/Discoveries",
         "Сама папка разбора."),
        ("TripTrack/Views/MyMap",
         "«Атлас»: печати и подсказки — из базы, по уже найденному."),
        ("TripTrack/Views/Tracking/TripCompleteSummaryView.swift",
         "Экран итогов показывает готовую сводку `TripDiscoveries`; сам ничего не считает.")
    ]

    /// Прощённые файлы — каждый с причиной словами.
    ///
    /// Строка здесь обязана быть ВИДИМЫМ РЕШЕНИЕМ в диффе: добавленный путь
    /// ревьюер пролистает, путь с причиной — нет. Не пишется причина — значит
    /// места в списке нет, и звать разбор оттуда нельзя.
    private static let allowlist: [(path: String, reason: String)] = [
        ("TripTrack/ViewModels/MapViewModel.swift",
         "Цепочка финиша: зовётся только после `stopRecording`, последним за "
         + "`PostTripTrackProcessor`, `PlaceManager.process` и `RevealedLayerStore.ingest`. "
         + "Единственная дверь в разбор во всём приложении.")
    ]

    // MARK: Правило B — чего не смеет сама папка

    /// Внутри `Services/Discoveries` этих имён быть не может: они и есть
    /// «живое» — GPS, уведомления, звук. Разбор идёт по УЖЕ записанному треку,
    /// из базы, и ни в одном из трёх ему нет нужды.
    private static let liveTokens = [
        "LocationManager", "CLLocationManager", "UNUserNotificationCenter", "AVAudioPlayer"
    ]

    private static let discoveriesDir = "TripTrack/Services/Discoveries"

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

    /// Нарушения правила A БЕЗ учёта allowlist — прощение идёт отдельным шагом,
    /// чтобы вторым тестом можно было спросить «а нужна ли ещё эта строка».
    private static let rawMentions: [Violation] = files.flatMap { file -> [Violation] in
        guard !inAllowedDir(file.path) else { return [] }
        return scan(file, tokens: matcherTokens)
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

    /// Правило A: разбор зовут только финиш и экраны, которые читают готовое.
    func testOnlyTheFinishChainKnowsAboutTheMatchers() throws {
        try requireSources()
        let found = Self.rawMentions.filter { !Self.allowed($0.path) }

        for violation in found.prefix(25) {
            XCTFail("""

                \(violation.path):\(violation.line) — «\(violation.token)» вне цепочки финиша.
                  строка: \(violation.text.prefix(160))
                  находки считаются ТОЛЬКО после `stopRecording`, по записанному треку. \
                Нужен доступ к найденному — читай `DiscoveryStore`, а не зови матчеры. \
                Появилась новая законная дверь — впиши файл в `allowlist` \
                в `NoLiveSecretPromptsTests` ВМЕСТЕ С ПРИЧИНОЙ.
                """)
        }
        XCTAssertTrue(found.isEmpty, "Мест, зовущих разбор мимо финиша: \(found.count)")
    }

    /// Правило B: сама папка находок не знает ни про GPS, ни про уведомления,
    /// ни про звук — то есть физически не может заговорить на ходу.
    func testDiscoveriesFolderCannotSpeakDuringTheDrive() throws {
        try requireSources()
        let inside = Self.files.filter { $0.path.hasPrefix(Self.discoveriesDir + "/") }
        XCTAssertFalse(inside.isEmpty, "папка находок не прочиталась — сторож смотрит не туда")

        var found: [Violation] = []
        for file in inside { found.append(contentsOf: Self.scan(file, tokens: Self.liveTokens)) }

        for violation in found.prefix(25) {
            XCTFail("""

                \(violation.path):\(violation.line) — «\(violation.token)» внутри папки находок.
                  строка: \(violation.text.prefix(160))
                  разбор идёт по УЖЕ записанному треку из базы: ни живого GPS, \
                ни уведомления, ни звука здесь быть не может.
                """)
        }
        XCTAssertTrue(found.isEmpty, "Живых источников внутри папки находок: \(found.count)")
    }

    /// Allowlist не имеет права заплывать жиром: файл однажды почистят, а
    /// строка останется — и дыра будет ровно там, где её никто не ищет.
    func testEveryAllowlistLineIsStillNeeded() throws {
        try requireSources()
        let mentioning = Set(Self.rawMentions.map(\.path))
        for entry in Self.allowlist {
            XCTAssertTrue(mentioning.contains(entry.path), """

                `\(entry.path)` больше не зовёт разбор — удали строку из `allowlist` \
                в `NoLiveSecretPromptsTests`.
                  причина, которая там записана: \(entry.reason)
                """)
        }
    }

    // MARK: Сам сторож под сторожем

    /// Тест, который проверяет ТЕСТ: на подброшенных строках он обязан
    /// сработать. Без этого сторож — самый опасный вид зелёного: читает файлы,
    /// ничего не находит и выглядит работающим, даже если смотрит не в ту папку.
    func testTheGuardActuallyCatchesPlantedLines() {
        let planted = """
            struct TrackingHUD: View {
                var body: some View {
                    // рядом секрет — подсказать бы
                    let hits = SecretMatcher.matches(track: live, catalog: c, salt: s)
                    let solved = RiddleMatcher.solved(track: live, candidates: near)
                    Task { await DiscoveryProcessor.shared.process(tripId: id, delta: d) }
                    UNUserNotificationCenter.current().add(request)
                    AVAudioPlayer.chime()
                }
            }
            """
        let (code, _) = UnitGuard.strip(planted)
        var caught: Set<String> = []
        for line in code {
            for token in Self.matcherTokens + Self.liveTokens where line.contains(token) {
                caught.insert(token)
            }
        }
        XCTAssertTrue(caught.contains("SecretMatcher"), "не увидел матчер секретов")
        XCTAssertTrue(caught.contains("RiddleMatcher"), "не увидел матчер загадок")
        XCTAssertTrue(caught.contains("DiscoveryProcessor"), "не увидел процессор")
        XCTAssertTrue(caught.contains("UNUserNotificationCenter"), "не увидел уведомление")
        XCTAssertTrue(caught.contains("AVAudioPlayer"), "не увидел звук")
        // А комментарий про секрет нарушением НЕ является: объяснение словами
        // — это документ, а не вызов.
        XCTAssertFalse(code.joined().contains("подсказать бы"), "комментарии не сняты")
    }
}
