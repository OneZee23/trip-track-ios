import SwiftUI

struct VehicleCatalogModelSteps: View {
    let hit: CarCatalog.ModelHit
    let type: String
    let onPick: (VehicleCatalogSelection) -> Void
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var generations: [CarCatalog.Generation] = []

    static func yearSpan(start: Int?, end: Int?) -> String {
        let lastYear = end ?? Calendar.current.component(.year, from: Date())
        return [start, lastYear].compactMap { $0.map(String.init) }.joined(separator: "–")
    }

    /// Catalog bodies that our silhouette names describe EXACTLY. A liftback
    /// or a wagon has no name of its own there — `defaultBody` draws them as a
    /// saloon and a hatchback — and a subtitle «Седан» under «Polo лифтбэк»
    /// would contradict the line above it. Generation names already carry the
    /// body, so the unnamed ones are simply left out.
    static func namedBodies(_ bodies: [String]?) -> [String] {
        let exact: [String: String] = ["sedan": "car", "hatchback": "hatchback", "crossover": "crossover",
                                       "pickup": "pickup", "van": "van", "convertible": "convertible"]
        var seen = Set<String>()
        return (bodies ?? []).compactMap { exact[$0] }.filter { seen.insert($0).inserted }
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Page(title: AppStrings.catalogGeneration(lang.language)) {
            ForEach(generations, id: \.id) { generation in
                NavigationLink {
                    YearStep(hit: hit, generation: generation, type: type, onPick: onPick)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(generation.name + " · " + Self.yearSpan(start: generation.yearStart, end: generation.yearEnd))
                            .font(.inter(15, weight: .semibold)).foregroundStyle(c.text)
                        let bodies = Self.namedBodies(generation.bodies)
                        if !bodies.isEmpty {
                            Text(bodies.map { AppStrings.avatarStyleName(lang.language, style: $0) }
                                .joined(separator: " · "))
                                .font(.inter(12)).foregroundStyle(c.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("catalog_generation_" + generation.id)
            }
        }
        .task {
            generations = await CarCatalog.shared.generations(of: hit.model.id, year: hit.matchedYear)
        }
    }

    private struct YearStep: View {
        let hit: CarCatalog.ModelHit
        let generation: CarCatalog.Generation
        let type: String
        let onPick: (VehicleCatalogSelection) -> Void
        @EnvironmentObject private var lang: LanguageManager
        @Environment(\.colorScheme) private var scheme
        @State private var year: Int?
        private let years: [Int]

        init(hit: CarCatalog.ModelHit, generation: CarCatalog.Generation, type: String,
             onPick: @escaping (VehicleCatalogSelection) -> Void) {
            self.hit = hit
            self.generation = generation
            self.type = type
            self.onPick = onPick
            let current = Calendar.current.component(.year, from: Date())
            let start = generation.yearStart ?? current
            let end = min(generation.yearEnd ?? current, current)
            let availableYears = start <= end ? Array((start...end).reversed()) : []
            years = availableYears
            _year = State(initialValue: hit.matchedYear.flatMap { availableYears.contains($0) ? $0 : nil })
        }

        var body: some View {
            let c = AppTheme.colors(for: scheme)
            Page(title: AppStrings.vehicleYear(lang.language)) {
                Text(generation.name).font(.inter(15, weight: .semibold)).foregroundStyle(c.text)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(years, id: \.self) { value in
                        Button { year = value; Haptics.selection() } label: {
                            Text(String(value)).font(.inter(15, weight: .semibold))
                                .foregroundStyle(year == value ? Color.white : c.text)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(year == value ? AppTheme.accent : c.cardAlt,
                                            in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityIdentifier("catalog_year_" + String(value))
                        .accessibilityAddTraits(year == value ? .isSelected : [])
                    }
                }
                if let year {
                    NavigationLink {
                        VariantStep(hit: hit, generation: generation, year: year, type: type, onPick: onPick)
                    } label: {
                        Text(AppStrings.continueButton(lang.language))
                            .font(.inter(15, weight: .semibold)).foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(AppTheme.accent, in: Capsule()).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("catalog_year_continue")
                }
            }
        }
    }

    private struct VariantStep: View {
        let hit: CarCatalog.ModelHit
        let generation: CarCatalog.Generation
        let year: Int
        let type: String
        let onPick: (VehicleCatalogSelection) -> Void
        @EnvironmentObject private var lang: LanguageManager
        @Environment(\.colorScheme) private var scheme
        @State private var variants: [CarCatalog.Variant] = []

        var body: some View {
            let c = AppTheme.colors(for: scheme)
            Page(title: AppStrings.catalogVariant(lang.language)) {
                Text(generation.name + " · " + String(year))
                    .font(.inter(15, weight: .semibold)).foregroundStyle(c.text)
                ForEach(variants, id: \.id) { variant in
                    Button { finish(variant) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(variant.label ?? variant.specLine(lang.language) ?? AppStrings.catalogUnknownEngine(lang.language))
                                .font(.inter(15, weight: .semibold)).foregroundStyle(c.text)
                            if let line = variant.specLine(lang.language) {
                                Text(line).font(.inter(12)).foregroundStyle(c.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("catalog_variant_" + variant.id)
                }
                Button { finish(nil) } label: {
                    Text(AppStrings.catalogUnknownEngine(lang.language))
                        .font(.inter(15, weight: .semibold)).foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("catalog_unknown_engine")
            }
            .task {
                variants = await CarCatalog.shared.variants(of: generation.id, year: year)
            }
        }

        private func finish(_ variant: CarCatalog.Variant?) {
            onPick(VehicleCatalogSelection(hit: hit, generation: generation, year: year, variant: variant, type: type))
        }
    }

    private struct Page<Content: View>: View {
        let title: String
        @ViewBuilder let content: () -> Content
        @EnvironmentObject private var lang: LanguageManager
        @Environment(\.colorScheme) private var scheme
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            let c = AppTheme.colors(for: scheme)
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text(AppStrings.back(lang.language))
                        }
                        .font(.inter(15, weight: .semibold)).foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                    Spacer()
                    Text(title).font(.inter(17, weight: .bold)).foregroundStyle(c.text)
                }
                .padding(.horizontal, 16)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10, content: content)
                        .frame(maxWidth: .infinity).padding(16)
                }
            }
            .background(c.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
