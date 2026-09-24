import SwiftUI

/// Черновики над «Историей» (спека §3.3). В сам список истории они не
/// ложатся: история складывает поездки в путешествия, календарь и статистику,
/// а черновик ни в одно из них не вошёл. Карточка та же, что в «Истории», и
/// на ней — пометка «Не подтверждена».
struct ProfileDraftsSection: View {
    let drafts: [Trip]
    let level: Int
    let vehicles: [Vehicle]
    let onOpen: (Trip) -> Void

    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileSectionLabel(text: AppStrings.draftSectionTitle(lang.language))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .accessibilityIdentifier("profile_drafts_header")
            LazyVStack(spacing: 12) {
                ForEach(drafts) { trip in
                    ProfileTripCardView(
                        trip: trip,
                        level: level,
                        vehicle: vehicles.first { $0.id == trip.vehicleId },
                        onTap: { onOpen(trip) }
                    )
                    .overlay(alignment: .topTrailing) { badge.padding(10) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var badge: some View {
        Text(AppStrings.draftBadge(lang.language))
            .font(.inter(12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppTheme.accent, in: Capsule())
    }
}
