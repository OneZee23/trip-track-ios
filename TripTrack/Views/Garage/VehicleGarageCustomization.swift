import SwiftUI

struct VehicleGarageCustomization: View {
    @Binding var finish: String
    @Binding var tags: [String]
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var plus = PlusAccess.shared
    @State private var showFinish = false
    @State private var showPaywall = false
    @State private var pendingPaywall = false

    private var access: PlusAccessLevel {
        PlusGate.allows(.vehicleCardStyle, isPlus: plus.isPlus, storefrontHidesPlus: plus.storefrontHidesPlus)
    }
    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        if access != .hidden {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showFinish = true
                    Haptics.tap()
                } label: {
                    HStack {
                        Text(AppStrings.garageFinish(l)).foregroundStyle(c.text)
                        Spacer()
                        Text(VehicleFinish.effective(finish, isPlus: plus.isPlus).label(l)).foregroundStyle(
                            c.textSecondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(
                            c.textTertiary)
                    }.font(.inter(14)).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(PressableCardStyle()).accessibilityIdentifier("garage_finish_row")
                if access == .open {
                    Text(AppStrings.garageTags(l)).font(.inter(13, weight: .semibold)).foregroundStyle(c.text)
                    ForEach(0..<3) { index in
                        TextField(
                            AppStrings.garageTags(l),
                            text: Binding(
                                get: { index < tags.count ? tags[index] : "" },
                                set: { value in
                                    while tags.count <= index { tags.append("") }
                                    tags[index] = String(value.prefix(24))
                                })
                        )
                        .font(.inter(14)).padding(10).background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("garage_tag_\(index)")
                    }
                    Text(AppStrings.garageTagsHint(l)).font(.inter(12)).foregroundStyle(c.textTertiary)
                } else {
                    Button {
                        showPaywall = true
                        Haptics.tap()
                    } label: {
                        HStack {
                            Text(AppStrings.garageTags(l)).font(.inter(14)).foregroundStyle(c.text)
                            Spacer()
                            Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(c.textTertiary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(PressableCardStyle())
                }
            }
            .sheet(
                isPresented: $showFinish,
                onDismiss: {
                    if pendingPaywall {
                        pendingPaywall = false
                        showPaywall = true
                    }
                }
            ) {
                SettingsOptionPicker(
                    title: AppStrings.garageFinish(l), options: VehicleFinish.availableFinishes,
                    selection: VehicleFinish.effective(finish, isPlus: plus.isPlus), footnote: "",
                    badge: { $0 == .gloss ? "sparkles" : "circle.fill" }, badgeIsSymbol: true,
                    label: { $0.label(l) + ($0.isPlus && access == .locked ? " 🔒" : "") },
                    onSelect: { picked in
                        if picked.isPlus && access == .locked {
                            pendingPaywall = true
                        } else {
                            finish = picked.rawValue
                        }
                    }, accessibilityPrefix: "garage_finish")
            }
            .sheet(isPresented: $showPaywall) { PlusPaywallSheet(feature: .vehicleCardStyle) }
        }
    }
}
