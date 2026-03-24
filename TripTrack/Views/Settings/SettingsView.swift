import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
            List {
                // Theme
                Section(isRu ? "Тема" : "Theme") {
                    Picker(isRu ? "Оформление" : "Appearance", selection: $themeManager.mode) {
                        Text(isRu ? "Системная" : "System").tag(ThemeManager.Mode.system)
                        Text(isRu ? "Светлая" : "Light").tag(ThemeManager.Mode.light)
                        Text(isRu ? "Тёмная" : "Dark").tag(ThemeManager.Mode.dark)
                    }
                }

                // Language
                Section(isRu ? "Язык" : "Language") {
                    Picker(isRu ? "Язык" : "Language", selection: $lang.language) {
                        Text("Русский").tag(LanguageManager.Language.ru)
                        Text("English").tag(LanguageManager.Language.en)
                    }
                }

                // About
                Section(isRu ? "О приложении" : "About") {
                    HStack {
                        Text(isRu ? "Версия" : "Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1")
                            .foregroundStyle(c.textTertiary)
                    }

                    HStack {
                        Text(isRu ? "Сборка" : "Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundStyle(c.textTertiary)
                    }
                }
            }
            .navigationTitle(isRu ? "Настройки" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isRu ? "Готово" : "Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }
}
