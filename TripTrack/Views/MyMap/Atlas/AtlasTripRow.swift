import SwiftUI

/// Строка поездки в шторке: мини-карта, название, «когда · сколько», шеврон.
///
/// Одна на регион своего «Атласа» и на регион и маршрут чужой карты (0.9.1):
/// две строки одной и той же поездки, нарисованные двумя кодами, однажды
/// разошлись бы — и на соседних экранах поездка читалась бы по-разному.
struct AtlasTripRow: View {
    let trip: MapTripPin
    /// Чужую поездку сначала спрашивают у сервера (0.9.1): на это время на
    /// месте шеврона крутится индикатор, как у рекорда в чужой статистике.
    var isOpening = false
    let onOpen: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var unit

    var body: some View {
        Button {
            Haptics.tap()
            onOpen()
        } label: {
            HStack(spacing: 12) {
                MapTripThumb(trip: trip, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate,
                                                 language: lang.language)
                         ?? AppStrings.tripTitle(lang.language))
                        .font(AppType.itemTitle)
                        .foregroundStyle(AtlasTheme.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Слот держит ширину и под индикатором: иначе текст строки
                // дёргался бы на нажатии.
                ZStack {
                    if isOpening {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AtlasTheme.secondary.opacity(0.7))
                    }
                }
                .frame(width: 18)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("atlas_region_trip")
    }

    /// Высота строки — числом: шторка чужой карты считает свою высоту по
    /// числу строк, а не измерением (урок «Высота листов «Атласа»»).
    static let height: CGFloat = 56

    private var subtitle: String {
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        let km = Measure.distance(metres: trip.distance, unit: unit,
                                  lang: lang.language, style: .tenths)
        return when + " · " + km
    }
}
