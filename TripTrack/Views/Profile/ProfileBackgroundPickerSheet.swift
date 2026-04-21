import SwiftUI
import OSLog

private let bgLog = Logger(subsystem: "com.triptrack", category: "profile.bg")

struct ProfileBackgroundPickerSheet: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared

    @State private var isSaving = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru
        let current = ProfileBackground.from(settings.profileBackground)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Live preview of the current selection
                    ZStack {
                        ProfileBackgroundBanner(background: current, height: 160)
                        Text(current.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.25), in: Capsule())
                    }
                    .padding(.horizontal, 16)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ProfileBackground.allCases) { bg in
                            Button {
                                Haptics.selection()
                                setBackground(bg)
                            } label: {
                                VStack(spacing: 6) {
                                    ProfileBackgroundTile(
                                        background: bg,
                                        isSelected: current == bg,
                                        size: 88
                                    )
                                    Text(bg.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(current == bg ? AppTheme.accent : c.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(c.bg)
            .navigationTitle(isRu ? "Фон профиля" : "Profile background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
        }
    }

    private func setBackground(_ bg: ProfileBackground) {
        settings.profileBackground = bg.rawValue

        // If signed-in, propagate to server so public profile shows same bg.
        guard auth.isSignedIn else { return }
        Task {
            do {
                let req = ProfileUpdateRequest(
                    displayName: nil,
                    avatarEmoji: nil,
                    profileBackground: bg.rawValue
                )
                let _: EmptyResponse = try await APIClient.shared.post(
                    APIEndpoint.profileUpdate, body: req)
            } catch {
                bgLog.error("profile bg sync failed: \(error.localizedDescription)")
            }
        }
    }
}
