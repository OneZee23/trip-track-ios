import XCTest
@testable import TripTrack

/// Кто имеет право завершить поездку за человека.
///
/// Правило «поставленную на паузу поездку не завершает никто» было записано в
/// коде прямым текстом и соблюдалось в двух дверях из четырёх: путь по
/// бездействию и восстановление стоячей поездки паузу проверяли, а отключение
/// магнитолы — нет.
///
/// 6 сентября 2026 это дважды за одну поездку разорвало маршрут Краснодар —
/// Джанхот. Человек глушил мотор у магазина, нажав перед этим «Паузу»;
/// магнитола отваливалась по Bluetooth, приложение спрашивало «Поездка
/// закончена?» и через три минуты закрывало запись само. Поездка сохранялась
/// огрызками по 9,6 км.
///
/// Тестов на это правило не было ни одного — потому оно и продержалось.
final class AutoStopOnPauseTests: XCTestCase {

    private func decide(
        mode: AutoRecordMode,
        isRecording: Bool = true,
        isPaused: Bool = false,
        idle: Bool = false,
        distance: Double = 20_000,
        duration: TimeInterval = 3_600,
        timeout: Int = 3
    ) -> AutoTripPolicy.BluetoothDisconnectDecision {
        AutoTripPolicy.onBluetoothDisconnect(
            mode: mode,
            isRecording: isRecording,
            isPaused: isPaused,
            isIdleBeyondFastStop: idle,
            tripDistance: distance,
            tripDuration: duration,
            autoStopTimeout: timeout
        )
    }

    // MARK: - Пауза сильнее любого датчика

    /// Главный тест. Пауза — самое сильное «я остановился нарочно», какое
    /// человек может дать приложению: магнитола знает только про зажигание, а
    /// пауза знает про намерение. Ни один режим и ни одно стечение датчиков не
    /// имеет права закрыть такую поездку.
    func testAPausedTripIsNeverStoppedByBluetooth() {
        for mode in AutoRecordMode.allCases {
            for idle in [false, true] {
                for (distance, duration) in [(20_000.0, 3_600.0), (50.0, 30.0)] {
                    XCTAssertEqual(
                        decide(mode: mode, isPaused: true, idle: idle,
                               distance: distance, duration: duration),
                        .ignore,
                        "режим \(mode.rawValue), стояла=\(idle), \(Int(distance)) м — поездку на паузе закрыли"
                    )
                }
            }
        }
    }

    /// Та самая поездка: полтора часа за рулём, пауза у магазина, мотор
    /// заглушен. Раньше здесь заводился таймер на три минуты.
    func testTheShopStopThatBrokeTheDrive() {
        let decision = decide(mode: .remind, isPaused: true, idle: false,
                              distance: 60_000, duration: 4_350)
        XCTAssertEqual(decision, .ignore)
    }

    // MARK: - «Напоминания» больше не завершают сами

    /// Режим называется «напоминания». Он спрашивал и всё равно закрывал
    /// поездку через три минуты — то есть был автоматикой с отсрочкой, а
    /// человек выбирал не её.
    func testRemindModeAsksAndDoesNotAct() {
        XCTAssertEqual(decide(mode: .remind), .promptOnly)
        // Даже когда все признаки «приехали» налицо — спросить, не закрывать.
        XCTAssertEqual(decide(mode: .remind, idle: true), .promptOnly)
    }

    /// Выключенная автоматика не подаёт голоса вовсе.
    func testOffModeStaysSilent() {
        XCTAssertEqual(decide(mode: .off), .ignore)
        XCTAssertEqual(decide(mode: .off, idle: true), .ignore)
    }

    // MARK: - Полная автоматика не изменилась

    /// Всё, что умел режим «автоматика», он умеет по-прежнему: эти три теста
    /// держат его поведение неизменным, чтобы починка паузы не утащила за
    /// собой то, что работало.
    func testAutoModeStillEndsAnObviouslyFinishedTrip() {
        XCTAssertEqual(decide(mode: .auto, idle: true), .stopNow)
    }

    func testAutoModeStillEndsAfterARealDrive() {
        XCTAssertEqual(decide(mode: .auto, distance: 20_000, duration: 3_600), .stopNow)
    }

    func testAutoModeStillGivesTheGraceToAShortTrip() {
        // Слишком коротко и близко, чтобы быть поездкой, — вероятнее дребезг
        // Bluetooth, и отсрочка существует ровно для него.
        XCTAssertEqual(decide(mode: .auto, distance: 100, duration: 60, timeout: 3),
                       .promptThenStop(afterMinutes: 3))
    }

    func testNothingHappensWhenNothingIsRecording() {
        XCTAssertEqual(decide(mode: .auto, isRecording: false, idle: true), .ignore)
    }

    // MARK: - Текст не обещает того, чего код не сделает

    /// В «напоминаниях» уведомление обещало «Автозавершение через 3 мин» —
    /// и сдерживало обещание, разрывая поездку. Теперь оно спрашивает; значит
    /// и говорить должно вопросом, на всех тринадцати языках.
    func testThePromptStopsPromisingAnAutomaticEnd() {
        for lang in LanguageManager.Language.allCases {
            let asks = AppStrings.notifTripStopBody(lang, minutes: nil, reason: .bluetooth)
            let warns = AppStrings.notifTripStopBody(lang, minutes: 3, reason: .bluetooth)

            XCTAssertFalse(asks.isEmpty, "\(lang): пустой текст")
            XCTAssertNotEqual(asks, warns, "\(lang): вопрос не отличается от обещания")
            XCTAssertFalse(asks.contains(where: \.isNumber),
                           "\(lang): в вопросе осталась минута из обещания — «\(asks)»")
            XCTAssertTrue(warns.contains("3"), "\(lang): обещание потеряло срок — «\(warns)»")
        }
    }
}
