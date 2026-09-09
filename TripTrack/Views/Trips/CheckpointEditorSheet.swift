import SwiftUI

/// Всё, что можно сделать с отметкой, — на одном листе.
///
/// Не меню из трёх пунктов, за каждым из которых открывается ещё один экран:
/// назвать, прикрепить снимок и удалить — это три действия над одной вещью, и
/// показывать их порознь значит заставлять человека возвращаться.
struct CheckpointEditorSheet: View {
    let checkpoint: TripCheckpoint
    let number: Int
    /// Снимки, которые уже относятся к отметке по времени или месту, обложка
    /// первой — их не надо искать, они уже здесь.
    let nearbyPhotos: [TripPhoto]
    /// Остальные снимки поездки — на случай, если время соврало.
    let otherPhotos: [TripPhoto]
    let language: LanguageManager.Language
    /// Имя, правил ли его человек, обложка. Флаг нужен из-за геокодера: он
    /// дописывает имя асинхронно, и лист, закрытый с нетронутым полем, не
    /// должен откатить «Джубгу» обратно в «Отметка 1».
    let onSave: (String?, Bool, UUID?, [UUID]) -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    /// Обложка и прикреплённые рукой снимки — то, что уедет в базу.
    @State private var photoId: UUID?
    @State private var photoIds: [UUID]
    @State private var confirmingDelete = false
    /// После удаления сохранять нечего — и не во что.
    @State private var deleted = false

    init(
        checkpoint: TripCheckpoint,
        number: Int,
        nearbyPhotos: [TripPhoto],
        otherPhotos: [TripPhoto],
        language: LanguageManager.Language,
        onSave: @escaping (String?, Bool, UUID?, [UUID]) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.checkpoint = checkpoint
        self.number = number
        self.nearbyPhotos = nearbyPhotos
        self.otherPhotos = otherPhotos
        self.language = language
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: checkpoint.name ?? "")
        initialName = checkpoint.name ?? ""
        _photoId = State(initialValue: checkpoint.photoId)
        _photoIds = State(initialValue: checkpoint.photoIds)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.accent, in: Circle())
                Text(AppStrings.checkpointWord(language))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(c.text)
                Spacer()
                Button {
                    Haptics.tap()
                    save()
                } label: {
                    NavCircleIcon(systemImage: "xmark")
                }
                .buttonStyle(.plain)
            }

            // Имя — подпись на маркере и строка в ленте, не описание. Сорок
            // знаков вмещают «Заправка перед границей» и любое имя из
            // геокодера; всё длиннее резалось бы многоточием в трёх местах.
            // Счётчик появляется только у предела — чтобы не шуметь у «Море».
            VStack(alignment: .trailing, spacing: 4) {
                TextField(AppStrings.checkpointNamePlaceholder(language), text: $name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(c.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: name) { _, newValue in
                        if newValue.count > Self.maxNameLength {
                            name = String(newValue.prefix(Self.maxNameLength))
                        }
                    }
                if name.count >= Self.maxNameLength - 10 {
                    Text("\(name.count)/\(Self.maxNameLength)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(name.count >= Self.maxNameLength ? AppTheme.red : c.textTertiary)
                        .padding(.trailing, 4)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: name.count >= Self.maxNameLength - 10)

            // Две полки: снимки ЭТОЙ отметки (обложка первой, с подписью) и
            // остальные снимки поездки, откуда можно добавить. Выбранный снимок
            // переезжает на первую полку сразу, а не остаётся во второй с
            // рамкой: лист показывает состояние ПОСЛЕ выбора, не до него.
            if !linkedPhotos.isEmpty {
                photoRow(title: AppStrings.checkpointPhotosNearby(language), photos: linkedPhotos, linked: true, c: c)
            }
            if !addablePhotos.isEmpty {
                photoRow(title: AppStrings.checkpointPhotosOther(language), photos: addablePhotos, linked: false, c: c)
            }

            Button {
                Haptics.tap()
                confirmingDelete = true
            } label: {
                Text(AppStrings.checkpointDelete(language))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(AppTheme.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressableCardStyle())
        }
        .padding(20)
        .background(c.bg)
        // Свайп вниз закрывает лист мимо кнопки — правки не должны пропасть.
        // Сохранение идемпотентно, так что второй вызов после «×» безвреден.
        .onDisappear { if !deleted { commit() } }
        .appConfirm(
            isPresented: $confirmingDelete,
            title: AppStrings.checkpointDelete(language),
            actions: [
                AppDialogAction(AppStrings.delete(language), kind: .destructive) {
                    deleted = true
                    onDelete()
                    dismiss()
                }
            ]
        )
    }

    /// Полка отметки с учётом текущего выбора: обложка первой, за ней
    /// прикреплённые рукой в порядке прикрепления, потом те, что привязались
    /// по времени и месту. Обложка без явного выбора — первый на полке.
    private var linkedPhotos: [TripPhoto] {
        let all = nearbyPhotos + otherPhotos
        var seen: Set<UUID> = []
        var list: [TripPhoto] = []
        func add(_ id: UUID) {
            guard !seen.contains(id), let photo = all.first(where: { $0.id == id }) else { return }
            seen.insert(id); list.append(photo)
        }
        if let photoId { add(photoId) }
        photoIds.forEach(add)
        nearbyPhotos.forEach { add($0.id) }
        return list
    }

    /// Остальные снимки поездки: что можно добавить к отметке.
    private var addablePhotos: [TripPhoto] {
        let linked = Set(linkedPhotos.map(\.id))
        return otherPhotos.filter { !linked.contains($0.id) }
    }

    private func photoRow(title: String, photos: [TripPhoto], linked: Bool, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        if linked {
                            linkedChip(photo, isCover: photos.first?.id == photo.id, c: c)
                        } else {
                            addableChip(photo, c: c)
                        }
                    }
                }
                // Запас под крестик, который торчит за угол миниатюры: без него
                // полка срезала ему верх и правый край.
                .padding(.leading, 1)
                .padding(.trailing, 10)
                .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: photoIds)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: photoId)
    }

    /// Снимок на полке отметки. Нажатие делает его обложкой — подпись
    /// переезжает, ничего не пропадает. Прикреплённый рукой снимок можно
    /// открепить крестиком; подобранный по времени — нет: его сюда поставила
    /// не рука, и снимать нечего.
    private func linkedChip(_ photo: TripPhoto, isCover: Bool, c: AppTheme.Colors) -> some View {
        let manual = photoIds.contains(photo.id) || photoId == photo.id
        return Button {
            guard !isCover else { return }
            Haptics.selection()
            photoId = photo.id
        } label: {
            thumb(photo, c: c)
                .overlay(alignment: .bottom) {
                    if isCover {
                        Text(AppStrings.checkpointCover(language))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent, in: Capsule())
                            .padding(.bottom, 5)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isCover ? AppTheme.accent : c.border, lineWidth: isCover ? 3 : 1)
                }
        }
        .buttonStyle(PressableCardStyle())
        .overlay(alignment: .topTrailing) {
            if manual {
                Button {
                    Haptics.tap()
                    photoIds.removeAll { $0 == photo.id }
                    if photoId == photo.id { photoId = nil }
                } label: {
                    // Глиф цветом фона на цвете текста: в тёмной теме круг
                    // белый, и белый крестик на нём пропадал.
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(c.bg)
                        .frame(width: 20, height: 20)
                        .background(c.text, in: Circle())
                        .overlay(Circle().strokeBorder(c.bg, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel(AppStrings.delete(language))
            }
        }
        .accessibilityLabel(isCover
            ? "\(AppStrings.nounPhotos(language, 1)), \(AppStrings.checkpointCover(language))"
            : AppStrings.nounPhotos(language, 1))
        .accessibilityAddTraits(isCover ? .isSelected : [])
    }

    /// Снимок из остальной поездки. Нажатие ПРИКРЕПЛЯЕТ его — он переезжает
    /// на полку отметки в конец, а обложка остаётся где была: выбор второго
    /// снимка не должен отбирать её у первого.
    private func addableChip(_ photo: TripPhoto, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.selection()
            photoIds.append(photo.id)
        } label: {
            thumb(photo, c: c)
                .opacity(0.8)
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(AppTheme.accent, in: Circle())
                        .padding(4)
                }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("\(AppStrings.checkpointAttachPhoto(language)): \(AppStrings.nounPhotos(language, 1))")
    }

    private func thumb(_ photo: TripPhoto, c: AppTheme.Colors) -> some View {
        AsyncThumbnailView(filename: photo.filename)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @State private var committed = false
    static let maxNameLength = 40
    private let initialName: String

    /// Отдать правки владельцу — ровно один раз, откуда бы ни пришли: с «×»
    /// или со свайпа.
    private func commit() {
        guard !committed else { return }
        committed = true
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? nil : trimmed, trimmed != initialName, photoId, photoIds)
    }

    private func save() {
        commit()
        dismiss()
    }
}
