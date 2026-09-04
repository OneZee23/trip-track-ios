import SwiftUI

// MARK: - «Мой профиль» hub (Figma 1687:119, grid 1778:119 / 1783:120, unset 1838:226)

/// Everything about *the user themselves* behind one pushed screen: the avatar
/// (edited in place) plus five rows that each open their own editor.
///
/// A pushed screen, never a sheet — the user's own words: «не снизу
/// экранчиком, а полноценный отдельный экран». So it carries `CustomNavBar`
/// with no `navBarInSheet`, exactly like `StatsScreenView`.
///
/// Display state comes straight off `AuthService` / `SettingsManager` /
/// `MapViewModel` rather than through the host: the host would have to observe
/// the same three objects to pass them down, and a stale copy of the name is
/// the one thing this screen must never show right after its editor saved.
/// The host only supplies navigation.
struct MyProfileView: View {
    var onTapName: () -> Void
    var onTapUsername: () -> Void
    var onTapAbout: () -> Void
    var onTapLevel: () -> Void
    var onTapCountry: () -> Void
    var onTapBackground: () -> Void
    var onTapStats: () -> Void
    /// Подписчики / подписки. Same destination the public profile's counters
    /// open — this screen just gives the owner a way in that doesn't go
    /// through a preview of themselves.
    var onTapFollowList: (FollowListMode) -> Void
    var onTapPreview: () -> Void

    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared

    @State private var isEditingAvatar = false
    /// Follower / following totals for THIS account, straight from the same
    /// profile GET the follow list uses for its segment chips. nil = not
    /// answered yet, and the counters print «—» rather than a zero nobody
    /// verified: «0 подписчиков» on a failed request is a claim, not a blank.
    @State private var followCounts: (followers: Int, following: Int)?

    /// The one avatar list in the app. It used to live as a private constant
    /// inside `ProfileView`; it moved here because this is the screen that
    /// edits the avatar, and two copies of a preset list drift the moment one
    /// of them grows an emoji.
    ///
    /// Canon 1778:156 — twelve curated faces in a 4×3 grid, in this order.
    ///
    /// People and one dog. The spec note on the page is explicit that objects
    /// are out («предметы запрещены»), which retired the guitar, camera, game
    /// pad, rocket and sunrise this list used to carry: an avatar is meant to
    /// read as somebody at a glance in a 28pt feed circle, and a 🎸 there says
    /// nothing about who posted. Anyone already wearing one of the retired
    /// emoji keeps it — it is stored as a string and rendered everywhere from
    /// the store, not from this list — they just cannot pick it again.
    ///
    /// The backend's `AVATAR_EMOJI_PATTERN` accepts any non-whitespace 1–16
    /// char string, so this can change without a schema change.
    static let avatars = [
        "😎", "🙂", "😄", "🤠",
        "🥸", "🧔", "👨‍🦳", "👩",
        "👩‍🦰", "👱‍♀️", "👵", "🐶",
    ]

    private static let avatarDiameter: CGFloat = 96
    /// The cover reaches this far down the screen; the disc hangs off its
    /// bottom edge.
    ///
    /// It has been both ways. At 132 the band was mostly empty air above the
    /// disc — nothing lives inside it, since the name and the handle are rows
    /// below. At 100 it read as a cropped stripe rather than as a cover. 170
    /// is the size at which the art is the point: deep enough to be a cover,
    /// and the first card still lands above the fold.
    private static let bannerHeight: CGFloat = 170
    private static let tileHeight: CGFloat = 64
    /// Canon tiles are 64×64 SQUARES. Flexible columns stretched them to 76×64
    /// dominoes on a 393pt screen; capping the width at the height keeps the
    /// square and turns the extra width into gutter, which is what canon's 24pt
    /// column gap is.
    private static let tileMaxWidth: CGFloat = 64
    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12), count: 4
    )

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ScrollView {
            VStack(spacing: 0) {
                hero(c, l)

                if isEditingAvatar {
                    avatarGrid(c, l)
                        .padding(.horizontal, 16)
                }

                // Under the face, above the fields: подписчики are part of who
                // the account IS, not one more thing to edit. Signed-in only —
                // both lists are server-side, and a guest has neither.
                if auth.isSignedIn {
                    followCard(c, l)
                        .padding(.horizontal, 16)
                        .padding(.top, isEditingAvatar ? 16 : 22)
                }

                rows(c, l)
                    .padding(.horizontal, 16)
                    // Canon breathes differently in the two states: 28pt under
                    // «Сменить аватар» (1687:119), 20pt under the grid's hint
                    // (1778:119) — the hint is smaller type and needs less air.
                    .padding(.top, isEditingAvatar ? 20 : 28)
            }
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hideAppTabBar()
        .safeAreaInset(edge: .top, spacing: 0) {
            CustomNavBar(title: AppStrings.myProfileTitle(l))
        }
        .accessibilityIdentifier("my_profile_screen")
        // Keyed on the session so a sign-in while this screen is open fills the
        // counters in instead of leaving two dashes behind.
        .task(id: auth.isSignedIn) { await loadFollowCounts() }
    }

    // MARK: - Подписчики / подписки

    /// One card, two halves, a rule between them — the same shape the public
    /// profile's stats card uses, so the two screens count the same way.
    ///
    /// Placed here rather than as two more chevron rows below: a follower count
    /// is a NUMBER, and a number set as a row value on the right edge of a
    /// settings row reads as a setting whose value happens to be 12.
    private func followCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack(spacing: 0) {
            followCell(
                count: followCounts?.followers,
                label: AppStrings.followersCaption(l, n: followCounts?.followers ?? 0),
                mode: .followers, c: c, identifier: "my_profile_followers"
            )

            Rectangle()
                .fill(c.borderBright)
                .frame(width: 1, height: 36)

            followCell(
                count: followCounts?.following,
                label: AppStrings.followingCaption(l, n: followCounts?.following ?? 0),
                mode: .following, c: c, identifier: "my_profile_following"
            )
        }
        .padding(.vertical, 14)
        .surfaceCard(cornerRadius: 16)
    }

    private func followCell(
        count: Int?,
        label: String,
        mode: FollowListMode,
        c: AppTheme.Colors,
        identifier: String
    ) -> some View {
        Button {
            Haptics.tap()
            onTapFollowList(mode)
        } label: {
            VStack(spacing: 3) {
                Text(count.map(String.init) ?? "—")
                    .font(.system(size: 20, weight: .heavy).monospacedDigit())
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 3) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                    // The one thing that says these two halves are doors and
                    // not a read-out.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// One profile GET, exactly as `FollowListView` loads its segment counts.
    /// Failure is silent and leaves the dashes: this is a decoration on a hub
    /// screen, not a reason for an error banner.
    private func loadFollowCounts() async {
        guard auth.isSignedIn, let accountId = TokenStore.shared.accountId else {
            followCounts = nil
            return
        }
        do {
            let p: SocialProfile = try await APIClient.shared.get(
                APIEndpoint.userProfile(accountId.uuidString))
            followCounts = (p.followerCount, p.followingCount)
        } catch {
            followCounts = nil
        }
    }

    // MARK: - Hero

    /// Disc + pencil badge + «Сменить аватар», all one tap target: the label
    /// exists to explain the disc, so making them two separate buttons would
    /// only invent a way to miss.
    ///
    /// The disc hangs off the bottom edge of the profile's OWN background
    /// banner. Two things that buys: the screen opens on colour instead of on
    /// the third identical white plate, and «Фон профиля» four rows down stops
    /// being a word — you are looking at what it does. It is also how the
    /// public profile and the preview already introduce a person, so the hub
    /// that edits the profile now opens the same way the profile itself does.
    private func hero(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let background = ProfileBackground.from(settings.profileBackground)

        // ДВЕ зоны, а не одна кнопка на весь герой. Раньше баннер, аватар и
        // подпись лежали внутри общего Button, и тап по фону открывал выбор
        // аватара — то есть попадание в баннер делало ровно не то, на что
        // человек целился. Аватар лежит в ZStack поверх баннера, поэтому в
        // области пересечения выигрывает он, как и ожидается.
        return VStack(spacing: 10) {
                ZStack(alignment: .bottom) {
                    // «Без фона» draws nothing at all, which would leave the
                    // disc floating on the page ground — the bare look this
                    // header exists to fix.
                    //
                    // The stand-in is a faint accent wash rather than a flat
                    // `cardAlt` plate: cardAlt sits a hair off the page ground,
                    // so the default looked like a rectangle of empty screen
                    // with the avatar stranded in the middle of it — worse than
                    // no header. A wash reads as a band at any brightness, and
                    // still reads as the quiet option beside any real preset.
                    Button {
                        Haptics.tap()
                        onTapBackground()
                    } label: {
                        Group {
                        if background == .none {
                            UnevenRoundedRectangle(
                                bottomLeadingRadius: 24, bottomTrailingRadius: 24
                            )
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accentDim, c.cardAlt],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: Self.bannerHeight)
                            .frame(maxWidth: .infinity)
                        } else {
                            ProfileBackgroundBanner(
                                background: background, height: Self.bannerHeight
                            )
                        }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.settingsProfileBackground(l))
                    .accessibilityIdentifier("my_profile_hero_background")
                    // Room for the half of the disc that hangs below the banner.
                    .padding(.bottom, Self.avatarDiameter / 2)

                    Button {
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isEditingAvatar.toggle()
                        }
                    } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(c.cardAlt)
                            .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
                            .overlay {
                                // `avatarEmoji` is only ever written from this
                                // grid and from the server's copy of it, both of
                                // which are single emoji.
                                Text(settings.avatarEmoji)
                                    .font(.system(size: 48))
                            }
                            // A ring in the PAGE colour, so the disc reads as
                            // punched out of the banner rather than dropped on
                            // top of it.
                            .overlay(Circle().strokeBorder(c.bg, lineWidth: 4))

                        if !isEditingAvatar {
                            pencilBadge(c)
                                // Canon hangs the badge off the rim rather than
                                // inside it (1687:147: 4pt past both edges).
                                .offset(x: 4, y: 4)
                                .transition(.opacity)
                        }
                    }
                    .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.myProfileChangeAvatar(l))
                    .accessibilityIdentifier("my_profile_hero_avatar")
                }

                // Подпись про аватар — часть аватарной зоны, а не фона.
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isEditingAvatar.toggle()
                    }
                } label: {
                    Text(AppStrings.myProfileChangeAvatar(l))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        .accessibilityIdentifier("my_profile_avatar")
    }

    private func pencilBadge(_ c: AppTheme.Colors) -> some View {
        Image(systemName: "pencil")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(c.textSecondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(c.card))
            .overlay(Circle().stroke(c.borderBright, lineWidth: 1))
            .shadow(
                color: .black.opacity(scheme == .dark ? 0.40 : 0.07),
                radius: 4,
                y: 1
            )
    }

    // MARK: - Avatar grid

    private func avatarGrid(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Self.gridColumns, spacing: 12) {
                ForEach(Self.avatars, id: \.self) { emoji in
                    avatarTile(emoji, c)
                }
            }

            // There is no Done button — the hint is the only thing telling the
            // user the tap already stuck.
            Text(AppStrings.myProfileAvatarHint(l))
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)

            // The retired-avatar easter egg, said out loud exactly once: here,
            // with the grid open and an irreversible tap one finger away.
            //
            // The curated set lost the objects (see `avatars`), but nobody is
            // migrated off one — the emoji is stored as a string and keeps
            // rendering everywhere. So a long-standing user can be wearing a
            // face no new user can ever pick, and that is worth keeping. What
            // is NOT acceptable is letting them spend it without knowing: the
            // grid highlights nothing, so without this line the only signal
            // that something rare was lost arrives after it is gone.
            if !Self.avatars.contains(settings.avatarEmoji) {
                Text(AppStrings.myProfileAvatarRetired(l, emoji: settings.avatarEmoji))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("my_profile_avatar_retired")
            }
        }
        .padding(.top, 16)
        .animation(.easeInOut(duration: 0.15), value: settings.avatarEmoji)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func avatarTile(_ emoji: String, _ c: AppTheme.Colors) -> some View {
        let isCurrent = settings.avatarEmoji == emoji
        return Button {
            Haptics.tap()
            select(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 30))
                .frame(maxWidth: Self.tileMaxWidth, minHeight: Self.tileHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isCurrent ? AppTheme.accentBg : c.cardAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isCurrent ? AppTheme.accent : .clear, lineWidth: 2)
                )
                // The 8%-accent fill barely separates from `cardAlt` in dark
                // mode; the glow is what makes "this is the one you're
                // wearing" survive the theme.
                .shadow(color: isCurrent ? AppTheme.accent.opacity(0.28) : .clear, radius: 8)
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func select(_ emoji: String) {
        guard settings.avatarEmoji != emoji else { return }
        settings.avatarEmoji = emoji
        settings.saveSettings()
        // Feed cards and the public profile render the SERVER's copy of the
        // avatar, so a local save alone would leave the new face invisible to
        // everyone including the user's own feed row.
        Task { await auth.syncProfileToServer() }
    }

    // MARK: - Rows

    /// Three cards, not eight.
    ///
    /// Every row used to be its own floating plate with the same gap above and
    /// below it, so the screen was a wall of identical white bars with nothing
    /// to read a shape from — and it grew that way honestly: canon 1687:119
    /// drew five, and страна, фон and превью landed on top of them. Grouping by
    /// what the rows ARE gives the eye three blocks instead of eight bars, and
    /// the gaps between the cards now carry meaning that the gaps between rows
    /// never did.
    ///
    /// The split: who you are (and can edit), how the profile looks, what the
    /// app has counted about you. The last card is read-only on purpose — its
    /// rows open screens, they don't take a value.
    ///
    /// No group headings: the settings sheet groups its cards the same way
    /// without labelling them, and three cards of four/two/two do not need a
    /// caption to be legible.
    ///
    /// Icons are the other half of the fix. `SettingsIconRow` is the row
    /// grammar the settings sheet already uses — same 30pt accent tile, same
    /// 14.5-semibold label — so these two screens stop looking like they came
    /// from different apps.
    private func rows(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 12) {
            card(c) {
                row(
                    icon: "person.fill",
                    label: AppStrings.myProfileRowName(l),
                    value: displayName ?? AppStrings.meAddYourName(l),
                    isUnset: displayName == nil,
                    identifier: "my_profile_row_name",
                    action: onTapName
                )
                divider(c)
                row(
                    icon: "at",
                    label: AppStrings.myProfileRowUsername(l),
                    value: username.map { "@\($0)" } ?? AppStrings.myProfileUsernameUnset(l),
                    isUnset: username == nil,
                    identifier: "my_profile_row_username",
                    action: onTapUsername
                )
                divider(c)
                row(
                    icon: "text.alignleft",
                    label: AppStrings.myProfileRowAbout(l),
                    value: bio ?? AppStrings.myProfileAboutUnset(l),
                    isUnset: bio == nil,
                    identifier: "my_profile_row_about",
                    action: onTapAbout
                )
                divider(c)
                row(
                    icon: "flag.fill",
                    label: AppStrings.myProfileRowCountry(l),
                    value: countryGlyph ?? AppStrings.countryNone(l),
                    isUnset: false,
                    identifier: "my_profile_row_country",
                    action: onTapCountry
                )
            }

            card(c) {
                // Not in canon, moved here from «Настройки».
                //
                // The banner it picks is drawn on THIS profile — on this very
                // screen, since the header above is that banner — so the switch
                // belongs on the screen that edits the profile. Under Настройки
                // it sat between «Гараж» and «Отправить логи», i.e. among the
                // app's tools rather than among the user's own things.
                row(
                    icon: "photo.on.rectangle",
                    label: AppStrings.settingsProfileBackground(l),
                    // The preset's own name — «Sunset», «Ocean». Proper nouns,
                    // the same word the picker shows, so it is not routed
                    // through AppStrings.
                    value: ProfileBackground.from(settings.profileBackground).displayName,
                    isUnset: false,
                    identifier: "my_profile_row_background",
                    action: onTapBackground
                )
                // «Как видят другие» used to hang off an undocumented
                // long-press on the header name — i.e. off nothing anyone would
                // find. It is a view of your identity, so it sits with the row
                // that decides how that identity looks.
                // Only when there IS a public profile: signed out the screen
                // behind this row has nothing to draw.
                if auth.isSignedIn {
                    divider(c)
                    row(
                        icon: "eye.fill",
                        label: AppStrings.myProfileRowPreview(l),
                        value: "",
                        isUnset: false,
                        identifier: "my_profile_row_preview",
                        action: onTapPreview
                    )
                }
            }

            card(c) {
                row(
                    icon: "star.fill",
                    label: AppStrings.myProfileRowLevel(l),
                    value: levelValue(l),
                    isUnset: false,
                    identifier: "my_profile_row_level",
                    action: onTapLevel
                )
                divider(c)
                row(
                    icon: "chart.bar.fill",
                    label: AppStrings.myProfileRowStats(l),
                    value: AppStrings.myProfileStatsSummary(
                        l,
                        trips: mapVM.cachedTripCount,
                        km: GarageFormat.odometer(mapVM.cachedTotalKm, lng: l)
                    ),
                    isUnset: false,
                    identifier: "my_profile_row_stats",
                    action: onTapStats
                )
            }
        }
    }

    private func card<Content: View>(
        _ c: AppTheme.Colors, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) { content() }
            .surfaceCard(cornerRadius: 16)
    }

    private func divider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.borderBright)
            .frame(height: 1)
    }

    /// `isUnset` paints the value accent instead of secondary — canon 1838:226
    /// draws the empty slot as the one orange thing on the screen, because a
    /// blank profile field is a job the user hasn't done rather than a value.
    private func row(
        icon: String,
        label: String,
        value: String,
        isUnset: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        SettingsIconRow(icon: icon, title: label, action: action) {
            HStack(spacing: 8) {
                if !value.isEmpty {
                    SettingsRowValue(text: value, tint: isUnset ? AppTheme.accent : nil)
                }
                SettingsRowChevron()
            }
        }
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Row values

    private var displayName: String? {
        guard let name = auth.userName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    /// Stored WITHOUT the «@» — the row adds it back. Local-only for now; the
    /// backend owes an account field and an availability endpoint, which is
    /// tracked on `SettingsManager.profileUsername`.
    private var username: String? {
        let v = settings.profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private var bio: String? {
        let v = settings.profileBio.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// The flag, or nil for «Не указывать» — which is a real answer, so the
    /// row says «Не указана» rather than nagging in accent like the two
    /// genuinely-empty identity rows above it.
    private var countryGlyph: String? {
        CountryChoice.glyph(for: settings.profileCountry)
    }

    /// «LVL 12 · Путешественник» — the same level/rank pair `LvlPill` shows in
    /// the Я header, so the row can't disagree with the pill above it.
    private func levelValue(_ l: LanguageManager.Language) -> String {
        let level = settings.profileLevel
        return "LVL \(level) · \(DriverRank.from(level: level).title(l))"
    }
}
