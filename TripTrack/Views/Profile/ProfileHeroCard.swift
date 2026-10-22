import SwiftUI

/// Identity and trip totals on «Me». A chosen profile background is shown
/// here as others see it; without one the card is light.
///
/// The default is a warm tint with an accent edge (owner, 13 Oct 2026,
/// variant C). Variant A, a dark card with a glow, shipped in 0.9.0 (79) and
/// was rolled back the next day: «Me» gave everyone a striking cover without
/// choosing one, so the profile background setting (eleven free, eight PRO)
/// looked like it did nothing. Only a chosen background darkens this card, so
/// what people see here is what others see on their profile.
struct ProfileHeroCard: View {
    let background: ProfileBackground
    let avatarEmoji: String
    let name: String
    var isNamePlaceholder: Bool = false
    let level: Int
    let rankTitle: String
    let trips: Int
    let km: Double
    let regions: Int
    var showsStats: Bool = true
    var isForeign = false
    var isOwnProfilePreview = false
    var publicProfile: SocialProfile? = nil
    var publicVehicle: PublicVehicle? = nil
    var followTitle: String? = nil
    var followBusy = false
    var followEnabled = true
    var onFollow: () -> Void = {}
    var bio: String? = nil
    var country: String? = nil
    var privacyStats = false
    var detailsEnabled = true
    var onCopyName: (() -> Void)? = nil
    var onTapVehicle: (UUID) -> Void = { _ in }
    var onAddVehicle: () -> Void = {}
    let onTapProfile: () -> Void
    let onTapLevel: () -> Void
    let onTapStats: () -> Void
    let onTapSettings: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var plus = PlusAccess.shared

    /// The background as others see it; `nil` for the light default. An
    /// expired PRO falls back here too (`effective`), never to a dark card.
    private var chosenCover: ProfileBackground? {
        let effective = background.effective(isPlus: paidCosmetics)
        return effective == .none ? nil : effective
    }
    private var hasCover: Bool { chosenCover != nil }
    private var colors: AppTheme.Colors { AppTheme.colors(for: scheme) }
    private var ink: Color { hasCover ? .white : colors.text }
    private var secondaryInk: Color { hasCover ? .white.opacity(0.85) : colors.textSecondary }
    private var rule: Color { hasCover ? .white.opacity(0.22) : AppTheme.accent.opacity(0.18) }

    private var paidCosmetics: Bool { isForeign ? publicProfile?.showsPaidCosmetics ?? false : plus.isPlus }
    private var frame: AvatarFrame {
        .effective(id: isForeign ? publicProfile?.avatarFrame : settings.avatarFrame, isPlus: paidCosmetics)
    }
    private var showsBadge: Bool {
        if isForeign {
            return isOwnProfilePreview
                ? PlusBadgeVisibility.shows(isPlus: paidCosmetics, isOwn: true, showsOwnBadge: settings.showPlusBadge)
                : publicProfile?.isPlus == true
        }
        return PlusBadgeVisibility.shows(isPlus: plus.isPlus, isOwn: true, showsOwnBadge: settings.showPlusBadge)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            identityRow
            if let bio, !bio.isEmpty {
                Text(bio).font(.interScaled(14, relativeTo: .subheadline))
                    .foregroundStyle(ink).lineLimit(3)
                    .accessibilityIdentifier("profile_bio")
            }
            ProfileGarageHeader(isForeign: isForeign, publicVehicle: publicVehicle,
                                showsPaidCosmetics: paidCosmetics, ink: ink, secondaryInk: secondaryInk,
                                onTap: onTapVehicle, onAdd: onAddVehicle)
            if showsStats {
                Rectangle().fill(rule).frame(height: 1)
                statsRow
            }
        }
        .padding(20)
        .background {
            if let chosenCover {
                chosenCover.view()
                    .overlay(.black.opacity(0.64))
            } else {
                defaultBackdrop
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(hasCover ? .clear : AppTheme.accent.opacity(0.22), lineWidth: 1)
        }
    }

    /// The card with a warm accent tint: set apart from the white cards under
    /// it, but still lighter than any paid cover.
    private var defaultBackdrop: some View {
        ZStack {
            colors.card
            AppTheme.accent.opacity(scheme == .dark ? 0.16 : 0.08)
        }
    }

    private var identityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    Haptics.tap()
                    onTapProfile()
                } label: {
                    Text(avatarEmoji)
                        .font(.inter(32))
                        .frame(width: 60, height: 60)
                        .background(hasCover ? .white.opacity(0.16) : colors.cardAlt, in: Circle())
                        .avatarFrame(
                            frame,
                            lineWidth: 3)
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel(AppStrings.myProfileTitle(lang.language))
                .accessibilityIdentifier("profile_avatar")
                .disabled(isForeign)

                if !typeSize.isAccessibilitySize {
                    identityText
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                if !isForeign {
                    Button {
                        Haptics.tap()
                        onTapSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(secondaryInk)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel(AppStrings.settingsTitle(lang.language))
                    .accessibilityIdentifier("profile_gear")
                }
            }
            if typeSize.isAccessibilitySize { identityText }
        }
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Haptics.tap()
                if isForeign { onCopyName?() } else { onTapProfile() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .accessibilityIdentifier(isForeign ? "profile_display_name" : "profile_name_text")
                        .font(.interScaled(21, weight: .bold, relativeTo: .title3))
                        .tracking(-0.3)
                        .foregroundStyle(isNamePlaceholder ? secondaryInk : ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsBadge {
                        ProBadge(height: 16)
                    }
                }
                .frame(minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .onLongPressGesture { onCopyName?() }
            .accessibilityIdentifier(isForeign ? "profile_copy_name" : "profile_name")

            Button {
                Haptics.tap()
                onTapLevel()
            } label: {
                HStack(spacing: 5) {
                    Text("LVL \(level)")
                        .font(.custom("Handjet-Black", size: 17, relativeTo: .subheadline))
                        .foregroundStyle(hasCover ? .white : AppTheme.accent)
                    Text(rankTitle)
                        .font(.interScaled(12, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(secondaryInk)
                    if detailsEnabled {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(secondaryInk)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 26, alignment: .leading)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
                .padding(.vertical, -9)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(isForeign ? "public_lvl_pill" : "profile_lvl_pill")
            .disabled(!detailsEnabled)
            if let country {
                Text(country).font(.inter(12)).foregroundStyle(secondaryInk)
                    .accessibilityIdentifier("profile_country")
            }
            if let followTitle {
                Button(action: onFollow) {
                    HStack(spacing: 6) {
                        if followBusy { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text(followTitle).font(.inter(13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 7).padding(.horizontal, 14)
                    .background(AppTheme.accent, in: Capsule())
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .padding(.vertical, -7)
                }
                .buttonStyle(PressableCardStyle())
                .disabled(followBusy || !followEnabled)
                .accessibilityIdentifier("profile_follow")
            }
        }
    }

    private var statsRow: some View {
        Button {
            Haptics.tap()
            onTapStats()
        } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                column(value: privacyStats ? "••••" : "\(trips)", label: AppStrings.trips(lang.language))
                column(value: privacyStats ? "••••" : Measure.distanceValue(km: km, unit: distanceUnit, lang: lang.language),
                       label: AppStrings.statsKmTotal(lang.language, unit: distanceUnit))
                column(value: privacyStats ? "••••" : "\(regions)", label: AppStrings.statsRegions(lang.language))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("profile_stats_strip")
        .disabled(!detailsEnabled || (isForeign && privacyStats))
    }

    private func column(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.interScaled(22, weight: .bold, relativeTo: .title3).monospacedDigit())
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.interScaled(11, weight: .medium, relativeTo: .caption))
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
