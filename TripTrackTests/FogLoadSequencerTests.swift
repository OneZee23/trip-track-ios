import XCTest
@testable import TripTrack

/// Порядок ответов у двух загрузок тумана — не наш.
@MainActor
final class FogLoadSequencerTests: XCTestCase {

    /// Две загрузки внахлёст, отвечающие В ОБРАТНОМ ПОРЯДКЕ: на карту обязана
    /// лечь вторая. Это карточка итогов — карта просит слой при установке, а
    /// секундой позже финиш присылает `.revealedLayerChanged`, и первая задача
    /// досчитывает ДОТУРИСТИЧЕСКИЙ слой (`RevealedLayerStore.layer(before:)`
    /// отмену не проверяет нигде).
    func testOnlyTheLatestRequestInstalls() async {
        var sequencer = FogLoadSequencer()
        var installed: String?

        let first = sequencer.begin()
        let second = sequencer.begin()

        // Ответы приходят в обратном порядке: свежий, потом устаревший.
        for (token, layer) in [(second, "свежий"), (first, "вчерашний")] {
            guard sequencer.isCurrent(token) else { continue }
            installed = layer
        }

        XCTAssertEqual(installed, "свежий",
                       "обогнавшая старая загрузка сняла свежую вуаль")
        XCTAssertTrue(sequencer.isCurrent(second))
        XCTAssertFalse(sequencer.isCurrent(first))
    }

    func testTheOnlyRequestIsAlwaysCurrent() {
        var sequencer = FogLoadSequencer()
        // Двумя строками, а не одной: `isCurrent(sequencer.begin())` читает
        // приёмник ДО того, как аргумент его подвинет.
        let token = sequencer.begin()
        XCTAssertTrue(sequencer.isCurrent(token))
    }
}
