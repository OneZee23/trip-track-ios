import SwiftUI

/// Всё, что можно сделать с отрезком, — на одном листе: назвать и удалить.
///
/// Тот же лист, что у отметки (`CheckpointEditorSheet`), и по той же причине:
/// два действия над одной вещью показываются вместе, а не двумя экранами.
/// Время и километры сюда не приезжают — они уже стоят крупно в самой скобке,
/// с которой этот лист открыли, и повторять их значило бы просить сравнить два
/// одинаковых числа.
struct SegmentEditorSheet: View {
    let segment: TripSegment
    /// Имя для заголовка: рукой или «A → B» из имён отметок. Считает экран
    /// (`TripSegmentName`) — лист про отметки поездки не знает.
    let title: String
    let language: LanguageManager.Language
    /// Пустое имя — законно: отрезок вернётся к «A → B».
    let onSave: (String?) -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var confirmingDelete = false
    /// После удаления сохранять нечего — и не во что.
    @State private var deleted = false
    @State private var committed = false
    private let initialName: String

    /// Тот же предел, что у имени отметки: имя едет в строку ленты и в
    /// заголовок листа, и длиннее сорока знаков резалось бы в обоих.
    static let maxNameLength = CheckpointEditorSheet.maxNameLength

    init(
        segment: TripSegment,
        title: String,
        language: LanguageManager.Language,
        onSave: @escaping (String?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.segment = segment
        self.title = title
        self.language = language
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: segment.name ?? "")
        initialName = segment.name ?? ""
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.checkpointLeg(language).uppercased(language))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(AppTheme.accent)
                    Text(title)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(c.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Button {
                    Haptics.tap()
                    save()
                } label: {
                    NavCircleIcon(systemImage: "xmark")
                }
                .buttonStyle(.plain)
            }

            // Счётчик появляется только у предела — как у имени отметки.
            VStack(alignment: .trailing, spacing: 4) {
                TextField(AppStrings.segmentNameField(language), text: $name)
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

            Button {
                Haptics.tap()
                confirmingDelete = true
            } label: {
                Text(AppStrings.segmentDelete(language))
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
        .accessibilityIdentifier("segment_editor")
        // Свайп вниз закрывает лист мимо «×» — имя не должно пропасть.
        .onDisappear { if !deleted { commit() } }
        .appConfirm(
            isPresented: $confirmingDelete,
            title: AppStrings.segmentDeleteConfirm(language),
            actions: [
                AppDialogAction(AppStrings.delete(language), kind: .destructive) {
                    deleted = true
                    onDelete()
                    dismiss()
                }
            ]
        )
    }

    /// Отдать имя владельцу ровно один раз, откуда бы ни закрыли лист. Имя,
    /// которого человек не трогал, не отдаётся вовсе: `updateSegment` — это
    /// правка поездки, и она поставила бы поездку в очередь синка за одно
    /// открытие листа.
    private func commit() {
        guard !committed else { return }
        committed = true
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != initialName else { return }
        onSave(trimmed.isEmpty ? nil : trimmed)
    }

    private func save() {
        commit()
        dismiss()
    }
}
