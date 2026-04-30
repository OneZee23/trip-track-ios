import SwiftUI

/// Bottom-sheet name editor. Replaces the previous `.alert` so the user
/// gets a focused TextField with proper styling, inline validation, and a
/// character counter — not a system-error-styled prompt.
///
/// The sheet shows a slightly different headline depending on whether the
/// user is editing a real name vs replacing a placeholder. That tiny
/// difference makes the placeholder case feel intentional ("name yourself")
/// rather than corrective.
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

        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Headline + subhead. For placeholder users we lean into
                // "name yourself" framing; for real edits, "your name".
                VStack(alignment: .leading, spacing: 6) {
                    Text(isPlaceholder
                         ? (isRu ? "Назовите себя" : "Name yourself")
                         : (isRu ? "Ваше имя" : "Your name"))
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(c.text)
                    Text(isRu
                         ? "Это имя увидят те, кто открывает Ваш профиль или Ваши публичные поездки."
                         : "Visible on your public profile and trips.")
                        .font(.system(size: 13))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)

                // Big input — focused on appear, with character counter
                // floating bottom-right when within 8 chars of the limit so
                // it stays calm in the common case.
                VStack(alignment: .trailing, spacing: 6) {
                    TextField(
                        isRu ? "Например, Иван" : "e.g., Alex",
                        text: $text,
                    )
                    .font(.system(size: 20, weight: .semibold))
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 14))

                    HStack(spacing: 8) {
                        if let err = validationError {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 11))
                                Text(err)
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(AppTheme.red)
                            .transition(.opacity)
                        }
                        Spacer(minLength: 0)
                        if trimmed.count >= Self.maxLength - 8 {
                            Text("\(trimmed.count)/\(Self.maxLength)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(trimmed.count >= Self.maxLength
                                                 ? AppTheme.red
                                                 : c.textTertiary)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: validationError != nil)
                    .animation(.easeInOut(duration: 0.15), value: trimmed.count)
                    .padding(.horizontal, 4)
                }

                Spacer(minLength: 0)

                // Save button — full-width primary. Cancel is in the nav bar
                // so the bottom is anchored on the affirmative action.
                Button {
                    Haptics.action()
                    commit()
                } label: {
                    Text(isRu ? "Сохранить" : "Save")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(canSave ? AppTheme.accent : c.textTertiary.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .animation(.easeInOut(duration: 0.15), value: canSave)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .background(c.bg)
            .toolbar {
                // Use the unified close affordance so every sheet across
                // the app dismisses in the same place. Save button sits
                // bottom-anchored as the affirmative action; the X is the
                // exit, matching ProfileBackgroundPickerSheet, BluetoothScanSheet,
                // CloudSyncView, SyncStatusSheetView, and DebugLogsView.
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
