import SwiftUI

struct HiddenEdgesQuestionSheet: View {
    let onboarding: Bool
    let onSave: (Int) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int?
    @State private var wholeRouteCount = 0

    private let options = [0, 200, 500, 1_000]

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        VStack(alignment: .leading, spacing: 12) {
            Image("HiddenEdgesIllustration")
                .resizable().interpolation(.none).scaledToFit()
                .frame(maxWidth: .infinity).frame(height: onboarding ? 180 : 160)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text(AppStrings.hiddenQuestionTitle(l))
                .font(.inter(22, weight: .heavy)).foregroundStyle(c.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(AppStrings.hiddenQuestionBody(l))
                .font(.inter(14)).foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { metres in
                    optionRow(metres, c: c, l: l)
                }
            }
            if wholeRouteCount > 0 {
                Text(AppStrings.hiddenQuestionWholeTrips(l, count: wholeRouteCount))
                    .font(.inter(12.5, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                guard let selection else { return }
                Haptics.success()
                onSave(selection)
                if !onboarding { dismiss() }
            } label: {
                Text(AppStrings.hiddenSave(l)).font(.inter(16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(selection == nil ? c.textTertiary : AppTheme.accent, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(PressableCardStyle())
            .disabled(selection == nil)
            .accessibilityIdentifier("hidden_question_save")
            Text(AppStrings.hiddenSettingsFootnote(l))
                .font(.inter(11.5)).foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(18)
        .background(c.bg)
        .contentSizedSheet(background: c.bg)
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("hidden_edges_question")
        .onChange(of: selection) { _, value in
            wholeRouteCount = value.map(wholeRouteHiddenCount) ?? 0
        }
    }

    private func optionRow(_ metres: Int, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let selected = selection == metres
        return Button { Haptics.selection(); selection = metres } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 21, weight: .regular)).foregroundStyle(selected ? AppTheme.accent : c.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(metres == 0 ? AppStrings.privacyEdgeNever(l) : Measure.distance(metres: Double(metres), unit: distanceUnit, lang: l))
                        .font(.inter(15, weight: .bold)).foregroundStyle(c.text)
                    if metres > 0 {
                        Text(AppStrings.hiddenOptionDetail(l, metres: metres))
                            .font(.inter(12.5)).foregroundStyle(c.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? AppTheme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metres == 0 ? AppStrings.privacyEdgeNever(l) : "\(Measure.distance(metres: Double(metres), unit: distanceUnit, lang: l)), \(AppStrings.hiddenOptionDetail(l, metres: metres))")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("hidden_question_option_\(metres)")
    }

    private func wholeRouteHiddenCount(_ metres: Int) -> Int {
        guard metres > 0 else { return 0 }
        let trips = CoreDataTripRepository(persistenceController: .shared).fetchTrips(limit: 50, offset: 0)
        return trips.reduce(into: 0) { count, trip in
            guard trip.isOnServer, !trip.isPrivate, trip.distance > 0 else { return }
            let parts = trip.hiddenParts
            let start = parts?.startMetres ?? metres
            let end = parts?.endMetres ?? metres
            if trip.distance <= Double(start + end) { count += 1 }
        }
    }
}
