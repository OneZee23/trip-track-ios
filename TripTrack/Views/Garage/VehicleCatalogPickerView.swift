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
    let onPick: (VehicleCatalogSelection) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var catalogHits: [CarCatalog.ModelHit] = []
    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    init(type: String, initialQuery: String = "",
         onPick: @escaping (VehicleCatalogSelection) -> Void) {
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

        NavigationStack {
            VStack(spacing: 0) {
                header(c: c, l: l)
                searchField(c: c, l: l)
                list(c: c)
            }
            .background(c.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: query) {
                let requestedQuery = query
                let hits = type == "car" ? await CarCatalog.shared.search(requestedQuery) : []
                guard !Task.isCancelled, requestedQuery == query else { return }
                catalogHits = hits
            }
        }
    }

    // MARK: - Шапка

    private func header(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            Text(AppStrings.vehicleMakeModel(l))
                .font(.inter(17, weight: .bold))
                .foregroundStyle(c.text)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Text(AppStrings.done(l))
                        .font(.inter(15, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(PressableCardStyle())
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
                .font(.inter(15))
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
                .accessibilityIdentifier("catalog_search")
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
                ForEach(catalogHits, id: \.model.id) { hit in
                    NavigationLink {
                        VehicleCatalogModelSteps(hit: hit, type: type) { selection in
                            onPick(selection)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.make.name + " " + hit.model.name)
                                    .font(.inter(15, weight: .semibold)).foregroundStyle(c.text)
                                Text(modelYears(hit))
                                    .font(.inter(12)).foregroundStyle(c.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").foregroundStyle(c.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("catalog_model_" + hit.model.id)
                }
                if !results.isEmpty {
                    GarageSectionLabel(text: AppStrings.catalogOtherModels(lang.language), color: c.textSecondary)
                        .padding(16)
                }
                ForEach(results, id: \.name) { make in
                    GarageSectionLabel(text: make.name, color: c.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    ForEach(make.models, id: \.name) { model in
                        Button {
                            let body = VehicleCatalog.defaultBody(for: model, type: type)
                            onPick(VehicleCatalogSelection(make: make.name, model: model.name, body: body))
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Text(model.name)
                                    .font(.inter(15, weight: .medium))
                                    .foregroundStyle(c.text)
                                Spacer(minLength: 8)
                                Text(AppStrings.avatarStyleName(
                                    lang.language,
                                    style: VehicleCatalog.defaultBody(for: model, type: type)))
                                    .font(.inter(12))
                                    .foregroundStyle(c.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                if results.isEmpty && catalogHits.isEmpty {
                    Text(AppStrings.catalogNothingFound(lang.language))
                        .font(.inter(13)).foregroundStyle(c.textSecondary).padding(16)
                }
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        onPick(VehicleCatalogSelection(make: query.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       model: "", body: VehicleAvatar.defaultStyle(forType: type)))
                        dismiss()
                    } label: {
                        Text(AppStrings.catalogUseTyped(lang.language))
                            .font(.inter(14, weight: .semibold)).foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func modelYears(_ hit: CarCatalog.ModelHit) -> String {
        let span = VehicleCatalogModelSteps.yearSpan(start: hit.yearStart, end: hit.yearEnd)
        guard let year = hit.matchedYear else { return span }
        return span + " · " + AppStrings.catalogHasYear(lang.language, year: year)
    }
}
