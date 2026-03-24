import SwiftUI

final class ThemeManager: ObservableObject {
    enum Mode: String, CaseIterable {
        case dark, light, system
    }

    @Published var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "appThemeMode")
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appThemeMode"),
           let m = Mode(rawValue: saved) {
            self.mode = m
        } else {
            self.mode = .system
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch mode {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}
