import SwiftUI
import PhotosUI

/// Фотографии машины — экран 06 канона 0.6.4.
///
/// Два яруса, как у drive2 и как в макете: закреплённая ГЛАВНАЯ во всю ширину
/// (она же лицо машины на её экране и в чужом гараже) и сетка остальных.
/// Долгий тап по снимку — сделать главной или удалить.
struct VehiclePhotosView: View {
    let vehicleId: UUID
    let vehicleName: String

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [VehiclePhoto] = []
    @State private var picking: [PhotosPickerItem] = []
    @State private var isSaving = false
    @State private var actionTarget: VehiclePhoto?

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            nav(c: c, l: l)
            ScrollView {
                VStack(spacing: 12) {
                    if let main = photos.first {
                        hero(main, c: c, l: l)
                    }
                    grid(c: c, l: l)
                    hint(c: c, l: l)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg.ignoresSafeArea())
        // У экрана СВОЯ шапка с шевроном, поэтому системный навбар прячем —
        // иначе на экране две кнопки «назад», и непонятно, чем они разные.
        .toolbar(.hidden, for: .navigationBar)
        .task(id: vehicleId) { reload() }
        .onChange(of: picking) { _, items in
            guard !items.isEmpty else { return }
            Task { await save(items) }
        }
        .appConfirm(
            isPresented: Binding(
                get: { actionTarget != nil },
                set: { if !$0 { actionTarget = nil } }
            ),
            title: AppStrings.vehiclePhotoActions(l),
            message: nil,
            actions: photoActions(l),
            cancelTitle: AppStrings.cancel(l)
        )
    }

    // MARK: - Шапка

    private func nav(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            VStack(spacing: 1) {
                Text(AppStrings.vehiclePhotos(l))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(c.text)
                Text(vehicleName)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.text)
                        // 44×44 — минимум, ниже которого палец промахивается,
                        // а VoiceOver читает «кнопка» без имени: у картинки
                        // подписи нет, и системный ярлык её не заменяет.
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(AppStrings.back(l))
                Spacer()
                PhotosPicker(selection: $picking, maxSelectionCount: 10,
                             matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 34, height: 34)
                }
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    // MARK: - Главная

    private func hero(_ photo: VehiclePhoto, c: AppTheme.Colors,
                      l: LanguageManager.Language) -> some View {
        ZStack(alignment: .topLeading) {
            image(photo)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(AppStrings.vehiclePhotoMain(l))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(10)
        }
        // Обычный тап, а не долгий: раньше тап по снимку не делал ВООБЩЕ
        // ничего, а единственное действие пряталось за жестом, о котором можно
        // было узнать только из подписи внизу экрана.
        .onTapGesture { Haptics.tap(); actionTarget = photo }
    }

    // MARK: - Сетка

    @ViewBuilder
    private func grid(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let rest = Array(photos.dropFirst())
        if !rest.isEmpty {
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(rest) { photo in
                    Button {
                        Haptics.tap()
                        actionTarget = photo
                    } label: {
                        image(photo)
                            .frame(height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func image(_ photo: VehiclePhoto) -> some View {
        if let ui = VehiclePhotoStore.image(photo) {
            Image(uiImage: ui).resizable().scaledToFill().clipped()
        } else {
            // Файл исчез, а строка осталась — показываем заглушку, а не пустоту:
            // пустой прямоугольник читается как «грузится» и никогда не грузится.
            Rectangle().fill(Color.gray.opacity(0.2))
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }

    private func hint(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Text(photos.isEmpty
             ? AppStrings.vehiclePhotosEmpty(l)
             : AppStrings.vehiclePhotosHint(l))
            .font(.system(size: 11))
            .foregroundStyle(c.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    // MARK: - Действия

    private func photoActions(_ l: LanguageManager.Language) -> [AppDialogAction] {
        guard let target = actionTarget else { return [] }
        var actions: [AppDialogAction] = []
        if !target.isMain {
            actions.append(AppDialogAction(AppStrings.vehiclePhotoMakeMain(l)) {
                VehiclePhotoStore.makeMain(target.id, of: vehicleId)
                reload()
            })
        }
        actions.append(AppDialogAction(AppStrings.delete(l), kind: .destructive) {
            VehiclePhotoStore.delete(target.id, of: vehicleId)
            reload()
        })
        return actions
    }

    private func reload() {
        photos = VehiclePhotoStore.photos(of: vehicleId)
    }

    private func save(_ items: [PhotosPickerItem]) async {
        isSaving = true
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data) else { continue }
            _ = VehiclePhotoStore.add(ui, to: vehicleId)
        }
        picking = []
        isSaving = false
        reload()
    }
}
