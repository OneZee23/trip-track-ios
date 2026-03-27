import SwiftUI

struct VehicleCardView: View {
    let vehicle: Vehicle
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var showInfo = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let progress = vehicle.progressToNextLevel
        let isRu = lang.language == .ru

        VStack(spacing: 0) {
            // Main card content
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(frameColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                    vehicle.avatarView(size: 44)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(vehicle.name.isEmpty
                            ? (isRu ? "Мой авто" : "My car")
                            : vehicle.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)

                        Spacer()

                        Text("LVL \(vehicle.level)")
                            .font(.custom("PressStart2P-Regular", size: 9))
                            .foregroundStyle(frameColor)
                    }

                    Text(vehicle.levelTitle(lang.language))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(frameColor)

                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(c.cardAlt).frame(height: 6)
                                Capsule()
                                    .fill(frameColor)
                                    .frame(width: max(3, geo.size.width * progress), height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text(formatOdometer(vehicle.odometerKm))
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                            .fixedSize()
                    }

                    HStack {
                        if !vehicle.stickers.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(vehicle.stickers, id: \.self) { sticker in
                                    Image(systemName: sticker.icon)
                                        .font(.system(size: 12))
                                        .foregroundStyle(sticker.color)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showInfo.toggle() }
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(c.textTertiary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)

            // Expandable info section
            if showInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle().fill(c.border).frame(height: 1)

                    Text(isRu ? "Машина прокачивается километрами:" : "Vehicle levels up with kilometers:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(c.textSecondary)

                    if let nextKm = vehicle.kmToNextLevel {
                        Text(isRu ? "До следующего уровня: \(String(format: "%.0f", nextKm)) км"
                             : "Next level in: \(String(format: "%.0f", nextKm)) km")
                            .font(.system(size: 12))
                            .foregroundStyle(c.text)
                    }

                    Text(isRu ? "Новая → Обкатка → Знакомая → Своя → Напарник → Ветеран → Боевой конь → Легенда → Бессмертный → Одометр ∞"
                         : "New → Break-in → Familiar → Yours → Partner → Veteran → Warhorse → Legend → Immortal → Odometer ∞")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .surfaceCard(cornerRadius: 16)
    }

    private var frameColor: Color {
        switch vehicle.level {
        case 1...2: return .gray
        case 3: return Color(red: 205/255, green: 127/255, blue: 50/255)
        case 4...5: return Color(red: 192/255, green: 192/255, blue: 192/255)
        case 6: return Color(red: 255/255, green: 215/255, blue: 0/255)
        case 7...8: return Color(red: 180/255, green: 210/255, blue: 230/255)
        default: return AppTheme.accent
        }
    }

    private func formatOdometer(_ km: Double) -> String {
        if km >= 1000 {
            return String(format: "%.1fK km", km / 1000)
        }
        return String(format: "%.0f km", km)
    }
}
