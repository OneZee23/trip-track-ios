import SwiftUI

/// «Попутчики» — the faces that were in the car with you (Figma 1195:148).
///
/// On your own trip the card is a door: tap it to add or remove people. On
/// someone else's it is read-only, because who was in their car is theirs to
/// say.
struct TripCompanionsCard: View {
    let companions: [TripCompanion]
    let isOwn: Bool
    let language: LanguageManager.Language
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Faces shown before the row turns into «+3». Four is what fits beside a
    /// two-line label on the narrowest phone.
    private static let visibleFaces = 4

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button(action: onTap) {
            HStack(spacing: 12) {
                if companions.isEmpty {
                    ZStack {
                        Circle().fill(c.cardAlt).frame(width: 34, height: 34)
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                } else {
                    faces(c)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(companions.isEmpty ? c.textSecondary : c.text)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isOwn {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(c.card)
                    .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOwn)
        .accessibilityIdentifier("companions_card")
    }

    /// Overlapping circles, the way a group of people is always drawn.
    private func faces(_ c: AppTheme.Colors) -> some View {
        let shown = Array(companions.prefix(Self.visibleFaces))
        let hidden = companions.count - shown.count
        return HStack(spacing: -10) {
            ForEach(shown) { companion in
                ZStack {
                    Circle().fill(c.cardAlt)
                    Text(companion.avatar).font(.system(size: 16))
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(c.card, lineWidth: 2))
            }
            if hidden > 0 {
                ZStack {
                    Circle().fill(c.cardAlt)
                    Text("+\(hidden)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(c.textSecondary)
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(c.card, lineWidth: 2))
            }
        }
    }

    private var title: String {
        if companions.isEmpty {
            return AppStrings.companionsAddPrompt(language)
        }
        return companions.displayNames
    }

    private var subtitle: String {
        if companions.isEmpty {
            return AppStrings.companionsEmptyHint(language)
        }
        return isOwn
            ? AppStrings.companionsRodeWithYou(language)
            : AppStrings.companionsRodeAlong(language)
    }
}

/// Add, rename and remove the people who were in the car.
struct TripCompanionsSheet: View {
    @State var companions: [TripCompanion]
    let onSave: ([TripCompanion]) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var draftName = ""
    @State private var draftAvatar = TripCompanion.avatarPalette[0]
    @FocusState private var nameFocused: Bool

    /// Past this many the card stops being a glance and starts being a list.
    private static let limit = 10

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            header(c)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: CompanionsHeaderHeightKey.self, value: proxy.size.height)
                    }
                )
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !companions.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(companions) { companion in
                                row(companion, c: c)
                                if companion.id != companions.last?.id {
                                    Divider().padding(.leading, 58)
                                }
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 14).fill(c.card)
                        }
                    }

                    if companions.count < Self.limit {
                        addBlock(c)
                    } else {
                        Text(AppStrings.companionsLimitReached(lang.language, limit: Self.limit))
                            .font(.system(size: 12.5))
                            .foregroundStyle(c.textTertiary)
                    }

                    Text(AppStrings.companionsLocalNote(lang.language))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                // The form's own height — the sheet is exactly this tall
                // instead of a full screen with the content at the top of it.
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CompanionsSheetHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(c.bg)
        .onPreferenceChange(CompanionsSheetHeightKey.self) { h in
            guard h > 0 else { return }
            contentHeight = h
        }
        .onPreferenceChange(CompanionsHeaderHeightKey.self) { h in
            guard h > 0 else { return }
            headerHeight = h
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        // Adding a companion makes the list longer, and the sheet should grow
        // with it rather than jump.
        .animation(.easeOut(duration: 0.22), value: sheetHeight)
    }

    /// Same hand-built header as the edit sheet — a `navigationTitle` inside a
    /// sheet brings a nav bar whose height cannot be measured for the detent.
    private func header(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Text(AppStrings.companionsSection(lang.language))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .padding(.horizontal, 84)

            HStack {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Text(AppStrings.cancel(lang.language))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
                Spacer()
                Button {
                    Haptics.action()
                    onSave(companions)
                    dismiss()
                } label: {
                    Text(AppStrings.done(lang.language))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityIdentifier("companions_done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    @State private var contentHeight: CGFloat = 340
    @State private var headerHeight: CGFloat = 50

    private var sheetHeight: CGFloat {
        min(headerHeight + contentHeight + 12, UIScreen.main.bounds.height * 0.9)
    }

    private func row(_ companion: TripCompanion, c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(c.cardAlt).frame(width: 34, height: 34)
                Text(companion.avatar).font(.system(size: 17))
            }
            Text(companion.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(c.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.2)) {
                    companions.removeAll { $0.id == companion.id }
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.delete(lang.language))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func addBlock(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.companionsAddPrompt(lang.language).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(c.textTertiary)

            HStack(spacing: 10) {
                TextField(AppStrings.companionsNamePlaceholder(lang.language), text: $draftName)
                    .font(.system(size: 16))
                    .foregroundStyle(c.text)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .onChange(of: draftName) { _, new in
                        if new.count > TripCompanion.nameLimit {
                            draftName = String(new.prefix(TripCompanion.nameLimit))
                        }
                    }
                    .padding(14)
                    .background { RoundedRectangle(cornerRadius: 12).fill(c.card) }
                    .accessibilityIdentifier("companion_name_field")

                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            Circle().fill(canAdd ? AppTheme.accent : c.textTertiary.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .accessibilityIdentifier("companion_add")
            }

            // Faces to tell people apart at a glance.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TripCompanion.avatarPalette, id: \.self) { face in
                        let selected = face == draftAvatar
                        Button {
                            Haptics.selection()
                            draftAvatar = face
                        } label: {
                            Text(face)
                                .font(.system(size: 19))
                                .frame(width: 38, height: 38)
                                .background(
                                    Circle().fill(selected ? AppTheme.accent.opacity(0.18) : c.card)
                                )
                                .overlay(
                                    Circle().strokeBorder(
                                        selected ? AppTheme.accent : .clear, lineWidth: 1.8
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
        }
    }

    private var canAdd: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, companions.count < Self.limit else { return }
        Haptics.success()
        withAnimation(.easeOut(duration: 0.2)) {
            companions.append(TripCompanion(name: name, avatar: draftAvatar))
        }
        draftName = ""
        // Next person gets the next face, so a family of four isn't four
        // identical circles.
        if let idx = TripCompanion.avatarPalette.firstIndex(of: draftAvatar) {
            draftAvatar = TripCompanion.avatarPalette[(idx + 1) % TripCompanion.avatarPalette.count]
        }
        nameFocused = true
    }
}

private struct CompanionsSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CompanionsHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
