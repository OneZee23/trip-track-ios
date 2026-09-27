import SwiftUI

/// Капсула кнопок карты: «Вид карты» и «Моё местоположение» (спека §3.4).
///
/// ОДНА капсула шириной 44, а не две отдельные кнопки: обе про карту, стоят
/// в одном углу и привязаны к одному слоту — разнесённые, они читались двумя
/// разными решениями. Между ними волосяная линия с полями 10.
///
/// Стоит она на 12 pt выше ВЕРХА СЛОТА, а не над шторкой: когда слот занят
/// карточкой места, следовать надо за карточкой (принцип 1 — слот один).
struct AtlasMapControls: View {
    /// В пустом атласе выбирать нечего: остаётся одно «Моё местоположение»,
    /// и капсула становится кругом сама.
    var showsLayers: Bool = true
    /// Геопозиция запрещена: иконка перечёркнута и вторичного цвета, а тап
    /// объясняет, а не молчит (состояние 13).
    var locationDenied: Bool = false
    var layersLabel: String
    var locationLabel: String
    var onLayers: () -> Void
    var onLocate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsLayers {
                button("square.3.layers.3d", label: layersLabel,
                       id: "atlas_appearance", tint: AtlasTheme.ink, action: onLayers)
                Rectangle()
                    .fill(AtlasTheme.glassBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 10)
            }
            button(locationDenied ? "location.slash" : "location",
                   label: locationLabel, id: "atlas_locate",
                   tint: locationDenied ? AtlasTheme.secondary : AtlasTheme.ink,
                   action: onLocate)
        }
        .frame(width: 44)
        .atlasGlass(Capsule())
    }

    private func button(_ icon: String, label: String, id: String,
                        tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                // Цель 44 × 44 даже там, где глиф 18 (спека §7).
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
