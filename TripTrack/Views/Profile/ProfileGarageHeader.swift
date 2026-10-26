import SwiftUI

struct ProfileGarageHeader: View {
    var isForeign = false
    var onCoverEdge = false
    var publicVehicle: PublicVehicle? = nil
    var showsPaidCosmetics = false
    var roadTime: RoadSceneTime? = nil
    let ink: Color
    let secondaryInk: Color
    let onTap: (UUID) -> Void
    let onAdd: () -> Void

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var plus = PlusAccess.shared
    @EnvironmentObject private var lang: LanguageManager
    @State private var page = 0
    @State private var mainPhotos = VehiclePhotoStore.mainPhotos()
    @ScaledMetric(relativeTo: .caption) private var roadCaptionHeight: CGFloat = 62

    private var vehicles: [Vehicle] {
        let all = settings.recordableVehicles
        guard let active = settings.activeRecordableVehicleId else { return all }
        return all.sorted { ($0.id == active ? 0 : 1) < ($1.id == active ? 0 : 1) }
    }
    private var width: CGFloat {
        if onCoverEdge { return 250 }
        if roadTime != nil { return min(UIScreen.main.bounds.width - 72, 300) }
        return min(UIScreen.main.bounds.width * 0.67, 300)
    }
    private var pageHeight: CGFloat {
        if onCoverEdge { return 188 }
        guard roadTime != nil else { return width * 0.78 + 62 }
        let stageHeight = vehicles.map { VehicleStage.height(for: $0.avatarImageName, width: width) }.max() ?? 0
        return stageHeight + 20 + roadCaptionHeight
    }

    var body: some View {
        if isForeign {
            if let v = publicVehicle { foreign(v) }
            else if let roadTime { ProfileRoadScene(time: roadTime).frame(height: 211) }
        } else if vehicles.isEmpty && !onCoverEdge {
            VStack(spacing: 14) {
                if let roadTime { ProfileRoadScene(time: roadTime).frame(height: 211) }
                addVehicleButton.padding(.horizontal, roadTime == nil ? 0 : 20)
            }
        } else if vehicles.count == 1, let v = vehicles.first {
            own(v)
        } else if !vehicles.isEmpty {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(vehicles.enumerated()), id: \.element.id) { index, v in own(v).tag(index) }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: pageHeight)
                HStack(spacing: 10) {
                    ForEach(vehicles.indices, id: \.self) { index in
                        Circle().fill(index == page ? AppTheme.accent : secondaryInk.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }.padding(.top, 6)
            }
        }
    }

    private var addVehicleButton: some View {
        Button(action: onAdd) {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 24))
                Text(AppStrings.addVehicleTitle(lang.language)).font(.inter(14, weight: .semibold))
            }
            .foregroundStyle(secondaryInk)
            .frame(maxWidth: .infinity).frame(height: 130).contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    secondaryInk.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("garage_header_add")
    }

    private func own(_ v: Vehicle) -> some View {
        Button {
            Haptics.tap()
            onTap(v.id)
        } label: {
            VStack(spacing: 8) {
                VehicleStage(
                    assetName: v.avatarImageName, fallbackEmoji: v.avatarEmoji,
                    style: .effective(id: v.cardStyle, isPlus: plus.isPlus),
                    finish: .effective(v.paintFinish, isPlus: plus.isPlus), photo: mainPhotos[v.id], width: width)
                    .frame(height: onCoverEdge ? 155 : nil, alignment: .bottom)
                    .padding(.vertical, roadTime == nil ? 0 : 10)
                    .frame(maxWidth: .infinity)
                    .background { if let roadTime { ProfileRoadScene(time: roadTime) } }
                let layout = onCoverEdge ? AnyLayout(HStackLayout(spacing: 5)) : AnyLayout(VStackLayout(spacing: 8))
                layout {
                    name(v.name.isEmpty ? AppStrings.defaultVehicleName(lang.language) : v.name)
                    VehicleCatalogCaption(
                        make: v.make, model: v.model, year: v.year, bodyType: v.bodyType,
                        modelID: v.catalogModelId, generationID: v.catalogGenerationId,
                        variantID: v.catalogVariantId, foreground: secondaryInk, scalesText: roadTime != nil)
                }
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("garage_header_vehicle")
        .task { mainPhotos = VehiclePhotoStore.mainPhotos() }
    }

    private func foreign(_ v: PublicVehicle) -> some View {
        Button {
            Haptics.tap()
            onTap(v.id)
        } label: {
            VStack(spacing: 8) {
                VehicleStage(
                    assetName: VehicleAvatar.assetName(style: v.avatarStyle, avatar: v.avatarEmoji),
                    fallbackEmoji: v.avatarEmoji,
                    style: .effective(id: v.cardStyle, isPlus: showsPaidCosmetics),
                    finish: .effective(v.paintFinish, isPlus: showsPaidCosmetics),
                    remotePhoto: v.mainPhoto.flatMap { $0.isEmpty ? nil : URL(string: $0) }, width: width)
                    .frame(height: onCoverEdge ? 155 : nil, alignment: .bottom)
                    .padding(.vertical, roadTime == nil ? 0 : 10)
                    .frame(maxWidth: .infinity)
                    .background { if let roadTime { ProfileRoadScene(time: roadTime) } }
                let layout = onCoverEdge ? AnyLayout(HStackLayout(spacing: 5)) : AnyLayout(VStackLayout(spacing: 8))
                layout {
                    name(v.name)
                    VehicleCatalogCaption(
                        make: v.make ?? "", model: v.model ?? "", year: v.year ?? 0, bodyType: v.bodyType ?? "",
                        modelID: v.catalogModelId, generationID: v.catalogGenerationId,
                        variantID: v.catalogVariantId, foreground: secondaryInk, scalesText: roadTime != nil)
                }
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("garage_header_vehicle")
    }

    private func name(_ value: String) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(roadTime != nil ? .interScaled(17, weight: .semibold, relativeTo: .headline)
                      : .inter(onCoverEdge ? 15 : 16, weight: .semibold))
                .foregroundStyle(ink)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(secondaryInk)
        }
    }
}
