import SwiftUI

/// The settings picker sheet, worn three times: «Единицы» (Figma 1685:119),
/// «Язык» (1685:176) and «Тема» (1685:233) are the same component with
/// different rows in it, so it is built once and handed its content.
///
/// Generic over `Hashable` rather than the `Identifiable & Equatable` the
/// brief named: the three payloads — `DistanceUnit`, `LanguageManager.Language`,
/// `ThemeManager.Mode` — are plain `String` enums living in files this screen
/// does not own, and none of them conforms to `Identifiable`. `Hashable` is
/// the weaker constraint every one of them already satisfies, so the call
/// sites need no conformance extensions bolted onto types that belong to the
/// model layer.
///
/// The sheet reports a pick and closes; it holds no state of its own. Which
/// store the pick lands in is the caller's business — units and language and
/// theme each live somewhere different.
struct SettingsOptionPicker<Option: Hashable>: View {
    let title: String
    let options: [Option]
    let selection: Option
    let footnote: String
    /// The 2–3 character token in the leading badge («км», «Ру»), or an SF
    /// Symbol name when `badgeIsSymbol` is set.
    let badge: (Option) -> String
    var badgeIsSymbol: Bool = false
    let label: (Option) -> String
    let onSelect: (Option) -> Void
    /// Stem for the sheet's accessibility identifiers («units_row_0»,
    /// «units_close»), so UI tests match on structure and not on a label that
    /// changes with the very setting this sheet edits.
    var accessibilityPrefix: String = "settings_option"

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            // Drawn rather than `.presentationDragIndicator(.visible)`, which
            // floats the system's grabber over the title — same treatment the
            // Name/About/Username editors already use.
            Capsule()
                .fill(.primary.opacity(0.18))
                .frame(width: 34, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 10)

            header(c)

            VStack(spacing: 4) {
                // Indexed rather than by element: a row needs to know what sits
                // above it to decide whether it draws a separator.
                ForEach(options.indices, id: \.self) { index in
                    row(options[index], index: index, c: c)
                }
            }
            // 8, not 16: the selected row's fill runs 8pt wider than the row
            // content on each side (1685:125), so the gutter lives here and
            // the content adds its own 8 back.
            .padding(.horizontal, 8)

            Text(footnote)
                .font(.system(size: 11.5))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
        // Canon paints this sheet white (#FFF), not the cream page ground —
        // and it has to, or the unselected badges (`cardAlt`) sit on a
        // near-identical warm grey and stop reading as badges at all.
        //
        // The 20pt under the footnote is the whole of the bottom margin: this
        // sheet ends in a caption, so the home-indicator strip on top of it
        // was just an empty white field the height of another row.
        .contentSizedSheet(background: c.card, contentClearsHomeIndicator: true)
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Header

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.16)
                .foregroundStyle(c.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                SheetCloseCircle()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(accessibilityPrefix)_close")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Row

    private func row(_ option: Option, index: Int, c: AppTheme.Colors) -> some View {
        let isSelected = option == selection
        // Canon draws a hairline only where two plain rows meet (1685:251,
        // the one separator in the three-row theme picker): the selected row's
        // warm fill already parts it from its neighbours, and a rule on top of
        // that fill would box it in.
        let showsDivider = index > 0
            && !isSelected
            && options[index - 1] != selection

        return Button {
            Haptics.tap()
            onSelect(option)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                badgeView(option, isSelected: isSelected, c: c)

                Text(label(option))
                    .font(.system(size: 14.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                // Kept in the layout at zero opacity so every row is the same
                // width up to the checkmark column; a mark that only exists on
                // one row shifts that row's label when the pick moves.
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(height: 44)
            // 56 around a 44pt row: the fill bleeds 6pt past the content on
            // both sides so the pill reads taller than the text inside it,
            // which is what makes the current choice unmistakable at a glance.
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.accentBg : Color.clear)
                    .frame(height: 56)
            }
            .overlay(alignment: .top) {
                if showsDivider {
                    Rectangle()
                        .fill(c.borderBright)
                        .frame(height: 1)
                        // Starts past the badge column, so the rule separates
                        // the labels and not the whole row.
                        .padding(.leading, 56)
                        .padding(.trailing, 8)
                        // Centred in the 4pt gap above, not on the row's edge.
                        .offset(y: -2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(accessibilityPrefix)_row_\(index)")
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
    }

    // MARK: - Badge

    /// The leading disc: «км» / «mi» / «Ру» / «En», or a sun / moon / gear.
    ///
    /// `accentDim` (0.15) is canon's #FCE4DB to within a percent — that hex is
    /// the accent at 0.16 over white — and unlike a literal it follows the
    /// accent into dark mode instead of glowing cream on a black sheet.
    @ViewBuilder
    private func badgeView(_ option: Option, isSelected: Bool, c: AppTheme.Colors) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? AppTheme.accentDim : c.cardAlt)

            if badgeIsSymbol {
                Image(systemName: badge(option))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.accent : c.text)
            } else {
                Text(badge(option))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.accent : c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: 32, height: 32)
    }
}
