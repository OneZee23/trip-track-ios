import Combine
import Foundation
import UIKit

@MainActor
final class FilmingModeManager: ObservableObject {
    static let shared = FilmingModeManager()

    @Published private(set) var state: FilmingModeState
    private var cancellables = Set<AnyCancellable>()

    private init(center: NotificationCenter = .default) {
        let settings = PrivacySettings.load()
        state = FilmingModeState(
            manual: settings.filmingManual,
            automatic: settings.filmingAuto,
            isCaptured: UIScreen.main.isCaptured,
            debugForced: Self.isDebugForceEnabled)
        center.publisher(for: UIScreen.capturedDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        center.publisher(for: .filmingSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    var isActive: Bool { state.isActive }

    private func refresh() {
        let settings = PrivacySettings.load()
        state = FilmingModeState(
            manual: settings.filmingManual,
            automatic: settings.filmingAuto,
            isCaptured: UIScreen.main.isCaptured,
            debugForced: Self.isDebugForceEnabled)
    }

    private static var isDebugForceEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-force-filming-mode")
        #else
        return false
        #endif
    }
}
