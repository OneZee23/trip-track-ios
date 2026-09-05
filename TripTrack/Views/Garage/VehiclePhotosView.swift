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
    /// Открытый во весь экран снимок. Тап теперь открывает СНИМОК, а не список
    /// действий: список был временной заплаткой на то, что смотреть было негде,
    /// а «сделать главной» и «удалить» переехали в саму открытую фотографию —
    /// туда, где на неё смотрят целиком.
    @State private var viewerIndex: Int?
    /// Страницы, замороженные на время показа, и id главной — отдельно.
    ///
    /// Пересобирать этот массив под открытым просмотрщиком нельзя: «сделать
    /// главной» ставит снимок первым, порядок меняется, а страница под пальцем
    /// и внутреннее состояние пейджера остаются на старом месте. Наружу это
    /// выглядело так: звезда не загорается, счётчик прыгает на «1 из 4», а сама
    /// фотография не двигается — три разных ответа на один тап.
    ///
    /// Поэтому порядок фиксируется в момент открытия, а звезда рисуется по
    /// `viewerMainId`, который меняется сразу. Список пересортируется потом, на
    /// закрытии, когда это уже никого не сбивает.
    @State private var viewerPages: [PhotoFullScreenView.Page] = []
    @State private var viewerMainId: UUID?
    /// Разовый вопрос «показывать ли эти снимки другим», который задаётся ровно
    /// в тот момент, когда он впервые осмыслен: у машины появилась первая
    /// фотография. Ось выключена по умолчанию, и без вопроса человек добавил бы
    /// снимки и не понял, почему их никто не видит.
    @State private var askVisibility = false

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
        // `onDismiss`, а НЕ работа в сеттере привязки.
        //
        // Сеттер вызывается в тот же миг, что и анимация закрытия, и всё, что
        // в нём стоит, выполняется поверх неё: выборка из CoreData, проверка
        // каждого файла на диске, иногда сохранение. Свайп вниз получался
        // вязким — заметно хуже, чем тот же жест в фотографиях поездки, где в
        // этом месте только сброс индекса. Здесь список перечитывается уже
        // ПОСЛЕ того, как просмотрщик ушёл.
        .fullScreenCover(
            item: Binding(
                get: { viewerIndex.map { ViewerStart(index: $0) } },
                set: { if $0 == nil { viewerIndex = nil } }
            ),
            onDismiss: { reload() }
        ) { start in
            PhotoFullScreenView(
                pages: viewerPages,
                initialIndex: start.index,
                language: lang.language,
                onDelete: { id in
                    // Только исполняем удаление. Страницу убирает и переводит
                    // взгляд сам просмотрщик: массив снаружи он не слушает —
                    // подмена списка под открытым листателем и была причиной
                    // того, что удалённый снимок оставался на экране.
                    VehiclePhotoStore.delete(id, of: vehicleId)
                },
                onSetMain: { id in
                    VehiclePhotoStore.makeMain(id, of: vehicleId)
                    viewerMainId = id
                },
                isMain: { $0 == viewerMainId },
                onDismiss: { viewerIndex = nil }
            )
        }
        .appConfirm(
            isPresented: $askVisibility,
            title: AppStrings.vehiclePhotoAskTitle(l),
            message: AppStrings.vehiclePhotoAskBody(l),
            actions: [
                AppDialogAction(AppStrings.vehiclePhotoAskShow(l)) {
                    setPhotosVisible(true)
                }
            ],
            cancelTitle: AppStrings.vehiclePhotoAskKeep(l)
        )
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

    /// Обёртка ради `fullScreenCover(item:)`: индекс сам по себе не
    /// `Identifiable`, а расширять `Int` на весь проект — плохая мена.
    private struct ViewerStart: Identifiable { let index: Int; var id: Int { index } }

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
            image(photo, maxSize: 400)
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
        .onTapGesture { Haptics.tap(); openViewer(at: 0) }
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
                        openViewer(at: photos.firstIndex(where: { $0.id == photo.id }) ?? 0)
                    } label: {
                        image(photo, maxSize: 140)
                            .frame(height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    /// Размер передаётся тот, в котором снимок и покажут: герой во всю ширину
    /// и плитка в сто точек — разные картинки, и грузить для плитки герой
    /// незачем.
    private func image(_ photo: VehiclePhoto, maxSize: CGFloat) -> some View {
        VehiclePhotoImage(photo: photo, maxSize: maxSize)
    }

    @ViewBuilder
    private func hint(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if photos.isEmpty {
            // Пустой экран был строкой мелкого серого текста под пустотой, и
            // добавить снимок можно было только «плюсом» в углу шапки — то
            // есть единственное действие экрана пряталось там, куда не
            // смотрят. Настоящее пустое состояние: рисунок, слова и кнопка.
            VStack(spacing: 14) {
                EmptyStateIllustration(name: "empty_garage", size: 120)
                Text(AppStrings.vehiclePhotosEmpty(l))
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PhotosPicker(selection: $picking, maxSelectionCount: 10,
                             matching: .images, photoLibrary: .shared()) {
                    Text(AppStrings.addPhotos(l))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppTheme.accent, in: Capsule())
                }
                .disabled(isSaving)
                .accessibilityIdentifier("vehicle_photos_empty_add")
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)
        } else {
            Text(AppStrings.vehiclePhotosHint(l))
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
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

    /// Спрашивать ли: только у машины, которой этот вопрос ещё не задавали, и
    /// только когда снимок действительно первый.
    private func askVisibilityIfFirstPhoto(hadNone: Bool) {
        guard hadNone, !photos.isEmpty,
              !VehiclePhotoVisibilityAsk.wasAsked(vehicleId) else { return }
        VehiclePhotoVisibilityAsk.markAsked(vehicleId)
        askVisibility = true
    }

    private func setPhotosVisible(_ visible: Bool) {
        guard let v = SettingsManager.shared.vehicle(for: vehicleId) else { return }
        SettingsManager.shared.updateVehicleVisibility(
            id: vehicleId,
            visibleToOthers: v.visibleToOthers,
            plateVisible: v.plateVisible,
            mapVisible: v.mapVisible,
            photosVisible: visible)
    }

    /// Снимок порядка на момент открытия — см. `viewerPages`.
    private func openViewer(at index: Int) {
        viewerPages = photos.map {
            .init(id: $0.id, source: .vehicle(filename: $0.filename),
                  timestamp: $0.timestamp)
        }
        viewerMainId = photos.first(where: { $0.isMain })?.id
        viewerIndex = index
    }

    private func reload() {
        photos = VehiclePhotoStore.photos(of: vehicleId)
    }

    private func save(_ items: [PhotosPickerItem]) async {
        let hadNone = photos.isEmpty
        isSaving = true
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data) else { continue }
            _ = VehiclePhotoStore.add(ui, to: vehicleId)
        }
        picking = []
        isSaving = false
        reload()
        askVisibilityIfFirstPhoto(hadNone: hadNone)
    }
}
