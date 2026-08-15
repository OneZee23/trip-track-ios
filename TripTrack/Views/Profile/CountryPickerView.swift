import SwiftUI

// MARK: - Country choice (Figma 675:119 «07 · Флаг страны (пикер)»)

/// The value a profile's flag carries: an ISO-3166 alpha-2 code, one of the two
/// sentinels, or `nil` for «Не указывать».
///
/// The sentinels exist because «весь мир» and «нейтральный флаг» are real
/// answers to "where are you from", not missing data — a user who deliberately
/// picks 🏳️ (preview 1716:119) is saying something different from one who never
/// opened this screen. Modelling them as codes rather than as extra optional
/// fields keeps the stored value a single string all the way to the server.
///
/// Both are outside ISO 3166-1 alpha-2 (which is two letters), so they can
/// never collide with a real country.
enum CountryChoice {
    static let world = "WORLD"
    static let neutral = "NEUTRAL"

    /// One row of the country table. Names are data, not UI copy — they are a
    /// closed reference list keyed by ISO code, so they live here rather than
    /// in `AppStrings` (which would gain ~120 one-line functions for no gain).
    struct Entry: Identifiable {
        let code: String
        let nameRu: String
        let nameEn: String

        var id: String { code }
        /// 🇷🇺 from "RU". Reuses the atlas's regional-indicator arithmetic
        /// instead of pasting 60 literals nobody can proofread; it is a pure
        /// static, so touching it does not load the 35 000-vertex atlas.
        var flag: String { RegionAtlas.flag(for: code) }

        /// Foundation carries country names in all seven languages, so this
        /// asks it rather than growing the tables by 65 rows per language. The
        /// hand-written pair stays as the fallback for the rows that are not
        /// real regions («Весь мир», the neutral flag) and for a locale that
        /// has no name for a code.
        func name(_ lang: LanguageManager.Language) -> String {
            lang.locale.localizedString(forRegionCode: code)
                ?? (lang == .ru ? nameRu : nameEn)
        }
    }

    /// Canon order (Figma draws the first 20, RU first), then the rest of the
    /// drivable neighbourhood and the places people actually come from. Not
    /// alphabetical on purpose: the grid has no labels, so a user finds their
    /// flag by shape in the first rows or not at all.
    static let all: [Entry] = [
        Entry(code: "RU", nameRu: "Россия", nameEn: "Russia"),
        Entry(code: "DE", nameRu: "Германия", nameEn: "Germany"),
        Entry(code: "US", nameRu: "США", nameEn: "United States"),
        Entry(code: "GB", nameRu: "Великобритания", nameEn: "United Kingdom"),
        Entry(code: "FR", nameRu: "Франция", nameEn: "France"),
        Entry(code: "IT", nameRu: "Италия", nameEn: "Italy"),
        Entry(code: "ES", nameRu: "Испания", nameEn: "Spain"),
        Entry(code: "PL", nameRu: "Польша", nameEn: "Poland"),
        Entry(code: "KZ", nameRu: "Казахстан", nameEn: "Kazakhstan"),
        Entry(code: "BY", nameRu: "Беларусь", nameEn: "Belarus"),
        Entry(code: "UA", nameRu: "Украина", nameEn: "Ukraine"),
        Entry(code: "TR", nameRu: "Турция", nameEn: "Türkiye"),
        Entry(code: "GE", nameRu: "Грузия", nameEn: "Georgia"),
        Entry(code: "AM", nameRu: "Армения", nameEn: "Armenia"),
        Entry(code: "CN", nameRu: "Китай", nameEn: "China"),
        Entry(code: "JP", nameRu: "Япония", nameEn: "Japan"),
        Entry(code: "KR", nameRu: "Южная Корея", nameEn: "South Korea"),
        Entry(code: "FI", nameRu: "Финляндия", nameEn: "Finland"),
        Entry(code: "SE", nameRu: "Швеция", nameEn: "Sweden"),
        Entry(code: "CZ", nameRu: "Чехия", nameEn: "Czechia"),
        Entry(code: "AZ", nameRu: "Азербайджан", nameEn: "Azerbaijan"),
        Entry(code: "UZ", nameRu: "Узбекистан", nameEn: "Uzbekistan"),
        Entry(code: "KG", nameRu: "Киргизия", nameEn: "Kyrgyzstan"),
        Entry(code: "TJ", nameRu: "Таджикистан", nameEn: "Tajikistan"),
        Entry(code: "TM", nameRu: "Туркменистан", nameEn: "Turkmenistan"),
        Entry(code: "MD", nameRu: "Молдова", nameEn: "Moldova"),
        Entry(code: "LT", nameRu: "Литва", nameEn: "Lithuania"),
        Entry(code: "LV", nameRu: "Латвия", nameEn: "Latvia"),
        Entry(code: "EE", nameRu: "Эстония", nameEn: "Estonia"),
        Entry(code: "NO", nameRu: "Норвегия", nameEn: "Norway"),
        Entry(code: "DK", nameRu: "Дания", nameEn: "Denmark"),
        Entry(code: "NL", nameRu: "Нидерланды", nameEn: "Netherlands"),
        Entry(code: "BE", nameRu: "Бельгия", nameEn: "Belgium"),
        Entry(code: "AT", nameRu: "Австрия", nameEn: "Austria"),
        Entry(code: "CH", nameRu: "Швейцария", nameEn: "Switzerland"),
        Entry(code: "PT", nameRu: "Португалия", nameEn: "Portugal"),
        Entry(code: "GR", nameRu: "Греция", nameEn: "Greece"),
        Entry(code: "HU", nameRu: "Венгрия", nameEn: "Hungary"),
        Entry(code: "RO", nameRu: "Румыния", nameEn: "Romania"),
        Entry(code: "BG", nameRu: "Болгария", nameEn: "Bulgaria"),
        Entry(code: "SK", nameRu: "Словакия", nameEn: "Slovakia"),
        Entry(code: "SI", nameRu: "Словения", nameEn: "Slovenia"),
        Entry(code: "HR", nameRu: "Хорватия", nameEn: "Croatia"),
        Entry(code: "RS", nameRu: "Сербия", nameEn: "Serbia"),
        Entry(code: "IE", nameRu: "Ирландия", nameEn: "Ireland"),
        Entry(code: "IS", nameRu: "Исландия", nameEn: "Iceland"),
        Entry(code: "MN", nameRu: "Монголия", nameEn: "Mongolia"),
        Entry(code: "IL", nameRu: "Израиль", nameEn: "Israel"),
        Entry(code: "AE", nameRu: "ОАЭ", nameEn: "UAE"),
        Entry(code: "IN", nameRu: "Индия", nameEn: "India"),
        Entry(code: "TH", nameRu: "Таиланд", nameEn: "Thailand"),
        Entry(code: "VN", nameRu: "Вьетнам", nameEn: "Vietnam"),
        Entry(code: "ID", nameRu: "Индонезия", nameEn: "Indonesia"),
        Entry(code: "CA", nameRu: "Канада", nameEn: "Canada"),
        Entry(code: "MX", nameRu: "Мексика", nameEn: "Mexico"),
        Entry(code: "BR", nameRu: "Бразилия", nameEn: "Brazil"),
        Entry(code: "AR", nameRu: "Аргентина", nameEn: "Argentina"),
        Entry(code: "AU", nameRu: "Австралия", nameEn: "Australia"),
        Entry(code: "NZ", nameRu: "Новая Зеландия", nameEn: "New Zealand"),
        Entry(code: "ZA", nameRu: "ЮАР", nameEn: "South Africa"),
        Entry(code: "EG", nameRu: "Египет", nameEn: "Egypt"),
        Entry(code: "MA", nameRu: "Марокко", nameEn: "Morocco")
    ]

    private static let byCode: [String: Entry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.code, $0) }
    )

    static func entry(for code: String) -> Entry? { byCode[code.uppercased()] }

    /// What to draw for a stored value anywhere outside this screen — the
    /// profile header pill (1717:135), the preview, a feed byline. `nil` for
    /// «Не указывать», which has no glyph at all: the caller hides the pill
    /// rather than drawing an empty one.
    static func glyph(for value: String?) -> String? {
        switch value {
        case world: return "🌍"
        case neutral: return "🏳️"
        case let code?: return code.count == 2 ? RegionAtlas.flag(for: code) : nil
        case nil: return nil
        }
    }

    /// Spoken/written name for a stored value. The three special values read
    /// their copy from `AppStrings` (they are UI copy); countries read the
    /// table above (they are data).
    static func label(for value: String?, _ lang: LanguageManager.Language) -> String {
        switch value {
        case world: return AppStrings.countryWorld(lang)
        case neutral: return AppStrings.countryNeutral(lang)
        case let code?: return entry(for: code)?.name(lang) ?? code
        case nil: return AppStrings.countryNone(lang)
        }
    }
}

// MARK: - Picker

/// «Страна» — pushed from the flag on the profile. A picker, not a form: one
/// tap commits and pops, so there is no Save button and no local draft state
/// that could disagree with what the caller stores.
///
/// Where the value is persisted is deliberately not decided here — the screen
/// takes the current value in and hands the new one back out.
struct CountryPickerView: View {
    let selection: String?
    /// `nil` = «Не указывать». Fires before the pop, so the caller's write and
    /// the disappear animation overlap instead of queueing.
    let onSelect: (String?) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// Canon draws five columns of 52pt squares with 17pt between them, which
    /// exactly fills the 360pt artboard. Columns are flexible rather than
    /// fixed so the same five stay edge-to-edge on a 393–440pt phone (see the
    /// artboard note in `NavCircleIcon`); the tiles grow with them and stay
    /// square via `aspectRatio`.
    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 17),
        count: 5
    )

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppStrings.countryHint(l))
                    .font(.system(size: 13))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                specialCard(c, l)

                Text(AppStrings.countrySectionAll(l))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(c.textTertiary)

                LazyVGrid(columns: Self.columns, spacing: 10) {
                    ForEach(entries) { entry in
                        tile(entry, c, l)
                    }
                }
            }
            .padding(.horizontal, 16)
            // Canon puts 14pt between the bar and the hint; the bar already
            // pays 12 of it.
            .padding(.top, 2)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hideAppTabBar()
        .safeAreaInset(edge: .top, spacing: 0) {
            CustomNavBar(title: AppStrings.countryTitle(l))
        }
        .accessibilityIdentifier("country_picker")
    }

    /// The table plus, if needed, whatever the user already has. A value can
    /// arrive from the server (or from a future longer list) that this build's
    /// table does not carry — showing it as a trailing tile keeps the screen
    /// honest about the current state instead of rendering nothing selected
    /// and silently losing the flag on the next tap.
    private var entries: [CountryChoice.Entry] {
        guard let selection, selection.count == 2,
              CountryChoice.entry(for: selection) == nil else {
            return CountryChoice.all
        }
        let code = selection.uppercased()
        return CountryChoice.all + [CountryChoice.Entry(code: code, nameRu: code, nameEn: code)]
    }

    // MARK: - Special rows

    private func specialCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            specialRow(value: nil, title: AppStrings.countryNone(l), c: c) {
                Image(systemName: "nosign")
                    .font(.system(size: 16))
                    .foregroundStyle(c.textSecondary)
            }
            specialRow(value: CountryChoice.world, title: AppStrings.countryWorld(l), c: c) {
                Text("🌍").font(.system(size: 18))
            }
            specialRow(value: CountryChoice.neutral, title: AppStrings.countryNeutral(l), c: c) {
                Text("🏳️").font(.system(size: 18))
            }
        }
        // Clip before the card fill, not after: the selected row paints a tinted
        // full-bleed background that would otherwise square off the card's
        // corners, and clipping the finished card would eat its shadow too.
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .surfaceCard(cornerRadius: 16)
    }

    private func specialRow<Glyph: View>(
        value: String?,
        title: String,
        c: AppTheme.Colors,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        let isSelected = selection == value
        return Button {
            commit(value)
        } label: {
            HStack(spacing: 11) {
                // One 20pt slot for all three glyphs so the labels line up —
                // an 18pt emoji is ~21pt wide, the SF Symbol is 18.
                glyph()
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Same 12% accent wash the selected tile carries, so «Весь мир»
            // and 🇷🇺 read as one selection model.
            .background(isSelected ? AppTheme.orangeDim : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
    }

    // MARK: - Country tile

    private func tile(
        _ entry: CountryChoice.Entry,
        _ c: AppTheme.Colors,
        _ l: LanguageManager.Language
    ) -> some View {
        let isSelected = selection?.uppercased() == entry.code
        return Button {
            commit(entry.code)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AppTheme.orangeDim : c.card)
                Text(entry.flag)
                    .font(.system(size: 22))
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isSelected {
                    // strokeBorder, not stroke: an inset border keeps the 1.5pt
                    // line inside the 14pt corner instead of straddling it.
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(AppTheme.accent, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected { checkBadge }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.name(l))
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier("country_tile_\(entry.code)")
    }

    /// Accent disc with a white tick, hung on the tile's top-right corner
    /// (canon 1682:132). White reads on the brand orange in both themes, so it
    /// is a literal here rather than a scheme colour.
    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(AppTheme.accent))
            .padding(.top, 2.5)
            .padding(.trailing, 5.5)
    }

    // MARK: - Commit

    private func commit(_ value: String?) {
        // No-op taps still pop — the row the user pressed is the one already
        // set, and re-picking it is a perfectly ordinary way to back out.
        if value != selection {
            Haptics.selection()
            onSelect(value)
        }
        dismiss()
    }
}
