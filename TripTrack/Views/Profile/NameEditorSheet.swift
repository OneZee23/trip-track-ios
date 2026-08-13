import SwiftUI

/// Compact bottom-sheet name editor (Figma 126:907): Отмена / Имя / Готово
/// header, accent-bordered input with a trailing clear-X, helper + counter
/// row. `maxLength` stays 30 — the server contract; the mock's "До 40" would
/// silently change validation, so the helper copy interpolates the real cap.
struct NameEditorSheet: View {
    let initialName: String
    let isPlaceholder: Bool
    let onSave: (String) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var validationError: String?
    @FocusState private var isFocused: Bool

    private static let maxLength = 30

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSave = !trimmed.isEmpty && trimmed != initialName.trimmingCharacters(in: .whitespacesAndNewlines)
                      && validationError == nil
                      && trimmed.count <= Self.maxLength

        VStack(spacing: 0) {
            // Custom grabber — this sheet drew a one-off 40×5 bar; every other
            // sheet (SignInPromptSheet, VehiclePickerSheet) uses 34×5 at 18%,
            // so it read as a different component stacked over them.
            Capsule()
                .fill(.primary.opacity(0.18))
                .frame(width: 34, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 10)

            // Отмена / Имя / Готово
            ZStack {
                Text(AppStrings.nameEditorTitle(lang.language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(c.text)

                HStack {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Text(AppStrings.cancel(lang.language))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        Haptics.action()
                        commit()
                    } label: {
                        Text(AppStrings.done(lang.language))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .opacity(canSave ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .accessibilityIdentifier("name_editor_done")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // Input — white card, 1.5pt accent border, trailing clear-X.
            HStack(spacing: 8) {
                TextField(
                    isRu ? "Например, Иван" : "e.g., Alex",
                    text: $text,
                )
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(c.text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit { if canSave { commit() } }
                .onChange(of: text) { _, newValue in
                    // Hard cap — silently truncate paste / over-type so
                    // users don't have to manually delete excess chars.
                    if newValue.count > Self.maxLength {
                        text = String(newValue.prefix(Self.maxLength))
                    }
                    validationError = validate(text)
                }
                .accessibilityIdentifier("name_editor_field")

                if !text.isEmpty {
                    Button {
                        Haptics.tap()
                        text = ""
                        validationError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(c.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(c.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.accent, lineWidth: 1.5)
            )
            // Was 12 while the header and helper rows sat at 16, so the one
            // element with a hard border overhung the caption under it.
            .padding(.horizontal, 16)

            // Helper (or validation error) + counter
            HStack(alignment: .top, spacing: 8) {
                if let err = validationError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                        Text(err)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(AppTheme.red)
                    .transition(.opacity)
                } else {
                    Text(AppStrings.nameHelper(lang.language, max: Self.maxLength))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("\(trimmed.count)/\(Self.maxLength)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(trimmed.count >= Self.maxLength
                                     ? AppTheme.red
                                     : c.textTertiary)
            }
            .animation(.easeInOut(duration: 0.15), value: validationError != nil)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .background(c.bg)
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.hidden)
        .onAppear {
            // Pre-fill placeholder users with empty so they don't have to
            // delete the random name first; for real edits, start with their
            // existing name selected for immediate overwrite.
            text = isPlaceholder ? "" : initialName
            validationError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }

    private func commit() {
        // Sanitize one final time on commit so what we send up matches the
        // visible state — protects against a paste that placed an invisible
        // char between the last `onChange` and the user tapping Save.
        let sanitized = ContentFilter.sanitize(text)
        guard !sanitized.isEmpty, validationError == nil else { return }
        onSave(sanitized)
        dismiss()
    }

    private func validate(_ value: String) -> String? {
        let sanitized = ContentFilter.sanitize(value)
        let isRu = lang.language == .ru
        if sanitized.count < 2 && !sanitized.isEmpty {
            return isRu ? "Слишком коротко" : "Too short"
        }
        // Reuse the same content filter the rest of the app validates with
        // (profanity / mixed-script / repeats / punctuation flood). Keeping
        // a single source of truth means a name accepted here is also
        // accepted on the server-side, with identical localized messaging.
        if !sanitized.isEmpty,
           let err = ContentFilter.validate(sanitized, field: .displayName, language: lang.language) {
            return err
        }
        return nil
    }
}
