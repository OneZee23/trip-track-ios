import SwiftUI

/// Чужое публичное путешествие (0.6.8) — ВРЕМЕННАЯ заглушка.
///
/// Волна 5, задача 1 кладёт только строки/DTO/адаптеры/навигацию: этот файл
/// существует, чтобы пять стеков, разбирающих `ProfilePreviewDest`, и
/// `.navigateToJourney` компилировались и пушили КУДА-ТО. Задача 4 заменит
/// файл целиком настоящим экраном (шапка, плечи, «Опубликовать»/«Скрыть»).
struct PublicJourneyView: View {
    let journeyId: UUID
    var pushPath: Binding<[ProfilePreviewDest]>?

    var body: some View {
        Text(journeyId.uuidString)
    }
}
