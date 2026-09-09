import AppIntents

/// Кнопка «Отметка» на Live Activity.
///
/// Ставит контрольную точку прямо на ходу, не заставляя доставать телефон и
/// открывать приложение: едешь из Краснодара в Геленджик, проезжаешь море —
/// нажал, и в поездке осталось «сколько времени и километров до сюда».
///
/// Имя у отметки на ходу не спрашиваем: за рулём подписывать некогда, а
/// отметка нужна в ту же секунду. Назвать её можно потом, на экране поездки.
struct CheckpointIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Checkpoint"

    func perform() async throws -> some IntentResult {
        await TripIntentHandler.shared.handleCheckpoint()
        return .result()
    }
}
