import Foundation
import Combine
import UIKit

/// Точка у вкладки «Я», пока есть черновики, которых ещё не открывали
/// (спека §матрица, состояние 12).
///
/// Точка, а не число: черновик — это вопрос, а не счётчик непрочитанного, и
/// «3» над иконкой обещало бы список, который надо разобрать до нуля.
///
/// «Не открывали» считается по ВРЕМЕНИ, а не по списку id: черновики заводит
/// только этот телефон и только автотрекингом, поэтому «есть запись свежее
/// последнего открытия списка» отвечает на вопрос точно, а список id рос бы
/// вместе с библиотекой и переживал бы удаление своих записей.
@MainActor
final class DraftsBadge: ObservableObject {
    static let shared = DraftsBadge()

    @Published private(set) var hasUnseen = false

    private static let key = "drafts.seenAt"
    private var bag: Set<AnyCancellable> = []

    private init() {
        let centre = NotificationCenter.default
        for name: Notification.Name in [.tripRecordingEnded, .draftTripResolved,
                                        .draftTripDecisionQueued, .tripDeleted,
                                        UIApplication.didBecomeActiveNotification] {
            centre.publisher(for: name)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &bag)
        }
        refresh()
    }

    /// Пересчитать. Ходит в базу, поэтому зовётся по событиям, а не из `body`.
    func refresh(repository: TripRepository = CoreDataTripRepository()) {
        let seen = UserDefaults.standard.object(forKey: Self.key) as? Date ?? .distantPast
        let fresh = Self.hasUnseen(drafts: repository.fetchDraftTrips(), seenAt: seen)
        if fresh != hasUnseen { hasUnseen = fresh }
    }

    /// Само правило — чистой функцией, чтобы его держал тест, а не открытый
    /// экран на телефоне: у вопроса «горит ли точка» два входа (запись новой
    /// поездки и открытие списка), и разойтись им нельзя.
    ///
    /// Строго больше, а не «больше либо равно»: `markSeen` пишет момент
    /// открытия, и черновик, записанный РОВНО в ту же секунду, человек на
    /// экране уже видел.
    nonisolated static func hasUnseen(drafts: [Trip], seenAt: Date) -> Bool {
        drafts.contains { $0.startDate > seenAt }
    }

    /// Список открыли — точка уходит.
    func markSeen() {
        UserDefaults.standard.set(Date(), forKey: Self.key)
        if hasUnseen { hasUnseen = false }
    }
}
