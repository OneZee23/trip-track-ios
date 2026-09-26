import SwiftUI

/// Внешний вид профиля: фон и рамка аватара.
///
/// Один лист на две косметики нарочно. Обе видны в ОДНОМ месте — на герое
/// профиля, — и выбирать их по отдельным экранам значит листать туда-сюда,
/// чтобы понять, сочетаются ли они. Предпросмотр наверху показывает ровно то,
/// что увидят другие: фон баннером, рамку на аватаре.
///
/// Платное здесь трёхзначно, и решает это `PlusGate`, а не экран: витрина без
/// платного (`.hidden`) не показывает премиум-секции ВОВСЕ — не «показывает
/// запертой», — а без подписки (`.locked`) тайл несёт замок и уводит в пейвол.
struct ProfileBackgroundPickerSheet: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var plus = PlusAccess.shared

    @State private var showPaywall = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    /// Бесплатные одиннадцать и «без фона» — их видят все и всегда.
    private var freeBackgrounds: [ProfileBackground] {
        ProfileBackground.allCases.filter { !$0.isPlus }
    }

    private var plusBackgrounds: [ProfileBackground] {
        ProfileBackground.allCases.filter(\.isPlus)
    }

    private var backgroundAccess: PlusAccessLevel {
        PlusGate.allows(.profileBackgrounds,
                        isPlus: plus.isPlus, storefrontHidesPlus: plus.storefrontHidesPlus)
    }

    private var frameAccess: PlusAccessLevel {
        PlusGate.allows(.avatarFrame,
                        isPlus: plus.isPlus, storefrontHidesPlus: plus.storefrontHidesPlus)
    }

    /// Что РИСОВАТЬ прямо сейчас — через общий резолвер, а не своим `if`:
    /// премиум-фон у аккаунта без подписки показывается как «без фона», и
    /// предпросмотр обязан врать не больше, чем сам профиль.
    private var currentBackground: ProfileBackground {
        ProfileBackground.effective(id: settings.profileBackground, isPlus: plus.isPlus)
    }

    private var currentFrame: AvatarFrame {
        AvatarFrame.effective(id: settings.avatarFrame, isPlus: plus.isPlus)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let lng = lang.language

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview(c)

                    section(title: AppStrings.settingsProfileBackground(lng), c: c) {
                        grid(freeBackgrounds, locked: false, c: c)
                    }

                    if backgroundAccess != .hidden {
                        section(title: AppStrings.plusSectionTitle(lng), c: c) {
                            grid(plusBackgrounds, locked: backgroundAccess == .locked, c: c)
                        }
                    }

                    if frameAccess != .hidden {
                        section(title: AppStrings.settingsAvatarFrame(lng), c: c) {
                            frameGrid(locked: frameAccess == .locked, c: c)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(c.bg)
            .navigationTitle(AppStrings.profileLookTitle(lng))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PlusPaywallSheet()
                .environmentObject(lang)
                .preferredColorScheme(scheme)
        }
    }

    // MARK: - Предпросмотр

    private func preview(_ c: AppTheme.Colors) -> some View {
        ZStack(alignment: .bottom) {
            ProfileBackgroundBanner(background: currentBackground, height: 160)
            // Аватар наполовину свисает с баннера — так же, как на «Моём
            // профиле»: рамку надо видеть ровно там, где она будет стоять.
            Text(settings.avatarEmoji)
                .font(.inter(34))
                .frame(width: 66, height: 66)
                .background(Circle().fill(c.card))
                .avatarFrame(currentFrame, lineWidth: 3)
                .offset(y: 26)
        }
        .padding(.bottom, 26)
        .padding(.horizontal, 16)
    }

    // MARK: - Секции

    @ViewBuilder
    private func section<Content: View>(
        title: String, c: AppTheme.Colors, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.inter(11, weight: .bold))
                .kerning(0.22)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
            content()
        }
    }

    private func grid(_ items: [ProfileBackground], locked: Bool, c: AppTheme.Colors) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { bg in
                tile(
                    isSelected: currentBackground == bg,
                    locked: locked,
                    caption: bg == .none
                        ? AppStrings.cosmeticDefaultOption(lang.language)
                        : bg.displayName,
                    c: c
                ) {
                    ProfileBackgroundTile(background: bg, isSelected: currentBackground == bg, size: 88)
                } action: {
                    setBackground(bg)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func frameGrid(locked: Bool, c: AppTheme.Colors) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AvatarFrame.allCases) { frame in
                tile(
                    // «Без рамки» бесплатна всегда: замок на отказе от
                    // косметики был бы обещанием того, чего платное не даёт.
                    isSelected: currentFrame == frame,
                    locked: locked && frame.isPlus,
                    caption: frame == .none
                        ? AppStrings.cosmeticDefaultOption(lang.language)
                        : frame.displayName,
                    c: c
                ) {
                    AvatarFrameTile(frame: frame, isSelected: currentFrame == frame, size: 88)
                } action: {
                    setFrame(frame)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Одна плитка: картинка, подпись, замок. Нажатие отвечает под пальцем
    /// (`PressableCardStyle`) в обоих состояниях — запертая плитка не
    /// «мёртвая», она ведёт в пейвол, и это надо чувствовать.
    private func tile<Art: View>(
        isSelected: Bool, locked: Bool, caption: String, c: AppTheme.Colors,
        @ViewBuilder art: () -> Art, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            if locked { showPaywall = true } else { action() }
        } label: {
            VStack(spacing: 6) {
                art()
                    .overlay(alignment: .center) {
                        if locked {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.black.opacity(0.42))
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                Text(caption)
                    .font(.inter(11, weight: .medium))
                    .foregroundStyle(isSelected && !locked ? AppTheme.accent : c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: - Запись

    private func setBackground(_ bg: ProfileBackground) {
        settings.profileBackground = bg.rawValue
        Task { await auth.syncProfileToServer() }
    }

    /// Через дверь `setAvatarFrame`, а не присваиванием: рамка живёт на
    /// аккаунте и обязана доехать И до базы, И до `/auth/profile-update`.
    private func setFrame(_ frame: AvatarFrame) {
        settings.setAvatarFrame(frame.rawValue)
    }
}

/// Плитка рамки в пикере — кольцо вокруг заглушки аватара, а не образец
/// цвета: рамку выбирают глазами по тому, как она смотрится на круге.
struct AvatarFrameTile: View {
    let frame: AvatarFrame
    let isSelected: Bool
    var size: CGFloat = 64

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.cardAlt)
            if frame == .none {
                Image(systemName: "slash.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(c.textTertiary)
            } else {
                Circle()
                    .fill(c.card)
                    .frame(width: size * 0.62, height: size * 0.62)
                    .avatarFrame(frame, lineWidth: 3.5)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? AppTheme.accent : Color.clear, lineWidth: 2.5)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, AppTheme.accent)
                    .padding(4)
            }
        }
    }
}
