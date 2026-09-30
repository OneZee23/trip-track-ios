import Combine
import Foundation
import SwiftUI

/// Кто решает, показать ли контекстное предложение, — одна дверь на два экрана.
///
/// Экраны («Лента» и «Я») только СПРАШИВАЮТ; правило живёт в
/// `ProContextOffer`, память — в `ProOfferLedger`, а здесь только то, чего ни
/// у того, ни у другого нет: состояние СЕССИИ. Первая ли она, записал ли
/// человек поездку сию минуту, показывали ли лист с момента запуска — всё это
/// живёт ровно столько, сколько живёт процесс, и в `UserDefaults` ему не место.
@MainActor
final class ProOfferCoordinator: ObservableObject {
    static let shared = ProOfferCoordinator()

    /// Какой момент показывать. `nil` — не показывать.
    @Published private(set) var pending: ProOfferMoment?

    private let ledger: ProOfferLedger
    private var isFirstSession = false
    private var recordedTripThisSession = false
    private var shownThisSession = false
    /// Ответили ли уже права StoreKit.
    ///
    /// Пока `false`, `isPlus` у `PlusAccess` тоже `false` — но это «не
    /// знаем», а не «не подписчик». Предлагать в это окно нельзя: платящему
    /// человеку показался бы лист «Профиль можно оформить», и показ
    /// записался бы в память НАВСЕГДА — момент M1 у него не появился бы
    /// больше никогда (находка ревью).
    private var entitlementsKnown = false
    private var observer: NSObjectProtocol?
    private var stateWatch: AnyCancellable?

    init(ledger: ProOfferLedger = ProOfferLedger()) {
        self.ledger = ledger
        // Первая сессия — та, в которой мы впервые записали дату запуска.
        // Узнаётся ДО записи, иначе первая сессия становится неотличимой от
        // второй.
        isFirstSession = ledger.firstLaunchAt == nil
        ledger.rememberFirstLaunchIfNeeded()
        // Блочный наблюдатель, а не `#selector`: селектор на изолированном
        // классе приходит с чужого потока, и `@objc`-метод пришлось бы
        // объявлять неизолированным — то есть заводить второй путь к тому же
        // полю. Здесь путь один, и он на главном актёре.
        observer = NotificationCenter.default.addObserver(
            forName: .tripRecordingEnded, object: nil, queue: .main
        ) { [weak self] _ in
            // Человек смотрит на итог только что записанной поездки —
            // предлагать ему что-либо в эту сессию нельзя (спека §11).
            MainActor.assumeIsolated { self?.recordedTripThisSession = true }
        }

        // Окончание подписки ловим НАБЛЮДЕНИЕМ, а не звонком из `PlusStore`:
        // направление зависимости обязано идти от потребителя к источнику.
        // Иначе `PlusStore` — место, где живёт StoreKit и больше ничего, —
        // начал бы знать про контекстные предложения.
        //
        // `dropFirst()` — ОБЯЗАТЕЛЕН, и это не осторожность. `@Published`
        // отдаёт ТЕКУЩЕЕ значение синхронно в момент подписки, а `state`
        // стартует `.none` и становится настоящим только после круга к демону
        // StoreKit. Координатор же создаётся лениво, на первом кадре Ленты
        // или «Я», то есть заведомо раньше. Без `dropFirst` первая эмиссия
        // была бы этим `.none` и СТИРАЛА бы правильно запомненное
        // `proExpiredAt` — человек, ждущий продления, не увидел бы M4 вовсе
        // (находка ревью).
        stateWatch = PlusStore.shared.$state
            .dropFirst()
            .sink { [weak self] state in
                MainActor.assumeIsolated {
                    self?.entitlementsKnown = true
                    self?.ledger.recordProExpired(
                        at: state == .expired ? PlusStore.shared.displayExpiry : nil)
                }
            }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Экран показался. Зовут «Лента» и «Я», и только они: запись, экран
    /// поездки и лист ручной поездки в список не входят.
    ///
    /// - Parameter fromPush: экран открыт уведомлением, а не рукой. Спека §11
    ///   запрещает лист в этом случае: человек шёл за своим делом.
    func screenAppeared(hasNetwork: Bool, tripCount: Int, fromPush: Bool = false) {
        guard pending == nil else { return }
        let input = ProContextOffer.Input(
            now: Date(),
            isPlus: PlusAccess.shared.isPlus,
            storefrontHidesPlus: PlusAccess.shared.storefrontHidesPlus,
            tripCount: tripCount,
            firstLaunchAt: ledger.firstLaunchAt,
            proExpiredAt: ledger.proExpiredAt,
            lastOfferAt: ledger.lastOfferAt,
            consecutiveDeclines: ledger.consecutiveDeclines,
            totalDeclines: ledger.totalDeclines,
            shownMoments: ledger.shownMoments,
            isFirstSession: isFirstSession,
            recordedTripThisSession: recordedTripThisSession,
            hasNetwork: hasNetwork,
            onEligibleScreen: true,
            alreadyShownThisSession: shownThisSession,
            entitlementsKnown: entitlementsKnown,
            // «После ошибок» — по той же красной строке, что показывает
            // баннер связи в «Ленте»: если у человека что-то не уехало, лист
            // с предложением купить он воспримет ровно так, как не надо.
            afterFailure: !SyncQueue.shared.failed.isEmpty,
            fromPush: fromPush)
        guard let moment = ProContextOffer.moment(input) else { return }
        shownThisSession = true
        ledger.recordShown(moment)
        pending = moment
    }

    /// «Подробнее о PRO» / «Продлить». Интерес отменяет паузу, но историю
    /// отказов не стирает.
    func accepted() {
        ledger.recordInterest()
        pending = nil
    }

    /// «Не сейчас» или закрытие жестом — одно и то же, и цена у них одна.
    /// Иначе правило частоты обходилось бы свайпом.
    func declined() {
        ledger.recordDecline()
        pending = nil
    }

    /// Извещение (M4 на витрине, которая не продаёт) закрывается БЕЗ отказа:
    /// человек не отказывался, ему сообщили.
    func acknowledged() {
        pending = nil
    }

    /// Подписка кончилась — повод для момента M4. Зовёт `PlusAccess`, когда
    /// право пропало; продление снимает отметку.
    func proExpired(at date: Date?) {
        ledger.recordProExpired(at: date)
    }
}
