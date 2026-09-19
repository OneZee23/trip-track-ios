import XCTest
@testable import TripTrack

/// Строки лога про ПОКУПКИ читает сторож, а не внимательность.
///
/// `APILogger.redact` чистит только ТЕЛА HTTP, а `DebugLogExporter` и
/// «Журнал» кладут `log.composedMessage` дословно, без единого прохода
/// чистки: `PIISensitiveKeys` их не касается вовсе. Значит вся дисциплина
/// здесь держится на авторе строки — и однажды уже не удержалась.
/// `TipJarService` был пробником под `#if DEBUG` и писал щедро: id аккаунта
/// и полные id транзакций с `privacy: .public`. В 0.8.0 файл стал боевым, а
/// строки уехали в релизный бинарник как были (проверено `strings` в аудите
/// ИБ). Сервер ту же дисциплину соблюдает — `plus.service.ts` режет любой id
/// транзакции до восьми символов.
final class PurchaseLogPrivacyTests: XCTestCase {

    /// Файлы, которые логируют покупку, и то, чего в их строках быть не может.
    private static let purchaseFiles = [
        "TripTrack/Services/TipJarService.swift",
        "TripTrack/Services/Plus/PlusStore.swift",
        "TripTrack/Services/Plus/PlusAttachQueue.swift",
    ]

    /// Подстроки, которые при `privacy: .public` означают утечку.
    private static let forbiddenPublic = [
        "accountToken=",
        "appAccountToken",
        "String(transaction.id)",
        "transaction.originalID",
        "jwsRepresentation",
    ]

    func testNoPurchaseLogLineExposesAnAccountOrAFullTransactionId() throws {
        let root = UnitGuard.repoRoot()
        var offences: [String] = []

        for path in Self.purchaseFiles {
            let url = root.appendingPathComponent(path)
            let text = try XCTUnwrap(try? String(contentsOf: url, encoding: .utf8),
                                     "сторож смотрит в никуда: \(path)")
            for (index, line) in UnitGuard.strip(text).code.enumerated() {
                guard line.contains("privacy: .public") else { continue }
                for token in Self.forbiddenPublic where line.contains(token) {
                    offences.append("""
                    \(path):\(index + 1)
                        \(line.trimmingCharacters(in: .whitespaces))
                        ПОЧЕМУ НЕЛЬЗЯ: «\(token)» с `.public` уезжает дословно в \
                    экспорт лога и в sysdiagnose — мимо `PIISensitiveKeys` и мимо \
                    `APILogger.redact`, которые чистят только тела HTTP.
                    """)
                }
            }
        }

        XCTAssertTrue(offences.isEmpty,
                      "платёжная строка лога с идентификатором наружу:\n\n"
                      + offences.joined(separator: "\n\n"))
    }

    /// Хвост в восемь символов — столько же, сколько печатает сервер: строки
    /// двух сторон должны склеиваться, и не более того.
    func testTransactionIdIsTruncatedToEightCharacters() {
        XCTAssertEqual(TipJarService.shortId(2_000_000_123_456_789), "23456789")
        XCTAssertEqual(TipJarService.shortId(7), "7", "короткий id остаётся собой")
        XCTAssertEqual(TipJarService.shortId(123_456_789).count, 8)
    }
}
