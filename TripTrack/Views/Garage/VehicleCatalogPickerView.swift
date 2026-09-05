import SwiftUI

/// Выбор марки и модели из справочника — экран 12 канона 0.6.4.
///
/// Поиск здесь не украшение, а ЕДИНСТВЕННЫЙ способ добраться до марки: их
/// девяносто семь, и листать столько никто не станет. Поэтому поле ввода стоит
/// первым и работает по алиасам — человек печатает «уаз» и «тойота», а в списке
/// написано «UAZ» и «Toyota» (`VehicleCatalog.search`).
///
/// Каталог заведомо неполон: 521 модель не покроет всё, что ездит. Пустой
/// результат — не тупик, а предложение вписать своими словами; форма всегда
/// оставляет свободный ввод.
struct VehicleCatalogPickerView: View {
    /// Тип транспорта решает, что показывать: тому, кто сказал «велосипед»,
    /// не предлагаем Toyota — это не свобода выбора, а список неправильных
    /// ответов.
    let type: String
    let initialQuery: String
    /// Отдаёт марку, модель и кузов. Кузов подставляется из справочника, но
    /// проходит через `VehicleAvatar.resolveStyle` — каталог предлагает, тип решает.
    let onPick: (String, String, String) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    init(type: String, initialQuery: String = "",
         onPick: @escaping (String, String, String) -> Void) {
        self.type = type
        self.initialQuery = initialQuery
        self.onPick = onPick
        _query = State(initialValue: initialQuery)
    }

    private var results: [VehicleCatalog.Make] {
        VehicleCatalog.search(query, type: type)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            header(c: c, l: l)
            searchField(c: c, l: l)

            if results.isEmpty {
                emptyState(c: c, l: l)
            } else {
                list(c: c)
            }
        }
        .background(c.bg.ignoresSafeArea())
    }

    // MARK: - Шапка

    private func header(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            Text(AppStrings.vehicleMakeModel(l))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(c.text)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text(AppStrings.done(l))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    // MARK: - Поиск

    private func searchField(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textTertiary)
            TextField(AppStrings.catalogSearchPlaceholder(l), text: $query)
                .font(.system(size: 15))
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(c.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 14).fill(c.cardAlt))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Список

    private func list(c: AppTheme.Colors) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results, id: \.name) { make in
                    GarageSectionLabel(text: make.name, color: c.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    ForEach(make.models, id: \.name) { model in
                        Button {
                            let body = VehicleCatalog.defaultBody(for: model, type: type)
                            onPick(make.name, model.name, body)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Text(model.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(c.text)
                                Spacer(minLength: 8)
                                Text(AppStrings.avatarStyleName(
                                    lang.language,
                                    style: VehicleCatalog.defaultBody(for: model, type: type)))
                                    .font(.system(size: 12))
                                    .foregroundStyle(c.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - Пусто

    private func emptyState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 12) {
            Text(AppStrings.catalogNothingFound(l))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Свободный ввод — не запасной путь, а полноправный: каталог
            // никогда не будет полным, и упереться в него нельзя.
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    onPick(query.trimmingCharacters(in: .whitespaces), "",
                           VehicleAvatar.defaultStyle(forType: type))
                    dismiss()
                } label: {
                    Text(AppStrings.catalogUseTyped(l))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.accent.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
