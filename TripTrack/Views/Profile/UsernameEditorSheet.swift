import SwiftUI

/// Handle editor (Figma 1833:6719, «занято» 1837:119, «невалидно» 1838:119):
/// Отмена / Юзернейм / Готово over a bordered field, a hint + counter row, and
/// the live verdict line the screen exists for.
///
/// Chrome, detent and keyboard behaviour are lifted from `NameEditorSheet` on
/// purpose — the two sit one tap apart on the same profile hub, and a second
/// editor style there would read as a second app.
struct UsernameEditorSheet: View {
    let initialUsername: String
    /// True when the host actually has somewhere to ask. With no endpoint the
    /// screen suppresses the verdict line entirely rather than printing a
    /// permanent failure at someone who cannot do anything about it.
    var canCheckAvailability: Bool = true
    /// Asks the server whether a handle is free. nil = the check itself failed.
    let checkAvailability: (String) async -> Bool?
    let onSave: (String) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var verdict: Verdict = .idle
    @State private var checkTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private static let minLength = 3
    private static let maxLength = 20
    /// Long enough that typing «alexandr» costs one lookup instead of eight,
    /// short enough that the answer still feels attached to the keystroke.
    private static let debounce: Duration = .milliseconds(400)
    /// Post-lowercasing set, so no A–Z here — `normalize` folds case first.
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._"
    )

    /// What we can say about the handle under the cursor right now. `.idle` is
    /// "nothing to say": empty, or still the handle the profile already has.
    private enum Verdict: Equatable {
        case idle
        case tooShort
        case invalidChars
        case checking
        case free
        case taken
        case checkFailed
    }

    // MARK: - Body

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            Capsule()
                .fill(.primary.opacity(0.18))
                .frame(width: 34, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 10)

            header(c)

            field(c)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                helperRow(c)
                verdictRow(c)
            }
            .animation(.easeInOut(duration: 0.15), value: verdict)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .contentSizedSheet(background: c.bg)
        .presentationDragIndicator(.hidden)
        .onAppear {
            text = Self.normalize(initialUsername)
            verdict = .idle
            // A beat, or the sheet's own presentation transition eats the
            // keyboard's — same delay NameEditorSheet needs.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                isFocused = true
            }
        }
        .onDisappear { checkTask?.cancel() }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func header(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Text(AppStrings.usernameTitle(lang.language))
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
                        .foregroundStyle(canSave ? AppTheme.accent : c.textTertiary)
                        
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityIdentifier("username_editor_done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func field(_ c: AppTheme.Colors) -> some View {
        // Zero spacing: canon glues the «@» to the first character, so the two
        // read as one word rather than as a prefix and a field.
        HStack(spacing: 0) {
            // The «@» is chrome, never part of the stored handle — drawn here
            // so the field reads as a handle even while it is empty, and so a
            // pasted «@vitaliy» can drop its own copy without looking eaten.
            Text("@")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(c.textTertiary)

            TextField("", text: $text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(c.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .focused($isFocused)
                    // Stock iOS blue against an all-orange screen.
                    .tint(AppTheme.accent)
                .onSubmit { if canSave { commit() } }
                .onChange(of: text) { _, raw in
                    let clean = Self.normalize(raw)
                    // Writing back re-enters this handler with clean == raw,
                    // which is where the verdict actually gets recomputed.
                    if clean != raw {
                        text = clean
                    } else {
                        revalidate(clean)
                    }
                }
                .accessibilityLabel(AppStrings.usernameTitle(lang.language))
                .accessibilityIdentifier("username_editor_field")

            if !text.isEmpty {
                Button {
                    Haptics.tap()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(c.textTertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
}
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(c.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor(c), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: verdict)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    @ViewBuilder
    private func helperRow(_ c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // «Занято» is the one state where the rules line has done its job
            // and the ask has to be repeated instead.
            Text(verdict == .taken
                 ? AppStrings.usernameTakenHint(lang.language)
                 : AppStrings.usernameHint(lang.language))
                .font(.system(size: 11.5))
                .foregroundStyle(c.textSecondary)
                // Both strings run two lines; reserving them keeps the
                // content-sized detent from twitching as they swap.
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text("\(text.count)/\(Self.maxLength)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(text.count >= Self.maxLength ? AppTheme.red : c.textTertiary)
        }
    }

    @ViewBuilder
    private func verdictRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 4) {
            switch verdict {
            case .idle:
                EmptyView()
            case .checking:
                // Quiet, and alone: showing the previous verdict while a new
                // answer is in flight is how a stale «занято» gets believed.
                ProgressView()
                    .controlSize(.mini)
            case .free:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text(AppStrings.usernameFree(lang.language))
                    .font(.system(size: 12, weight: .semibold))
            case .taken:
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                Text(AppStrings.usernameTaken(lang.language))
                    .font(.system(size: 12, weight: .semibold))
            case .tooShort:
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                Text(AppStrings.usernameTooShort(lang.language))
                    .font(.system(size: 12, weight: .semibold))
            case .invalidChars:
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                Text(AppStrings.usernameInvalidChars(lang.language))
                    .font(.system(size: 12, weight: .semibold))
            case .checkFailed:
                // Silent when there is nobody to ask — see `canCheckAvailability`.
                if canCheckAvailability {
                    Text(AppStrings.usernameCheckFailed(lang.language))
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .foregroundStyle(verdictColor(c))
        // Fixed so the line appearing and disappearing never resizes the sheet.
        .frame(height: 16, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("username_editor_verdict")
    }

    // MARK: - Derived state

    private var canSave: Bool {
        guard text.count >= Self.minLength,
              text != Self.normalize(initialUsername) else { return false }
        switch verdict {
        // `.checkFailed` saves on purpose: a lookup that never answered must
        // not trap someone in the editor with a handle they cannot commit.
        case .free, .checkFailed: return true
        default: return false
        }
    }

    private func borderColor(_ c: AppTheme.Colors) -> Color {
        switch verdict {
        case .tooShort, .invalidChars, .taken: return AppTheme.red
        default: return isFocused ? AppTheme.accent : c.borderBright
        }
    }

    private func verdictColor(_ c: AppTheme.Colors) -> Color {
        switch verdict {
        case .free: return AppTheme.green
        case .tooShort, .invalidChars, .taken: return AppTheme.red
        // The lookup failed, not the handle — neutral, so nothing here reads
        // as an accusation about what was typed.
        default: return c.textSecondary
        }
    }

    // MARK: - Validation

    /// Handles are case-insensitive and «@»-less on the wire; folding here
    /// rather than on commit means what is on screen is always what is checked.
    private static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        while s.hasPrefix("@") { s.removeFirst() }
        return String(s.prefix(maxLength))
    }

    /// Re-runs the whole verdict for `handle`, cheap checks first so a bad
    /// handle never costs a round trip.
    private func revalidate(_ handle: String) {
        // Every keystroke invalidates whatever is in flight. A «занято» that
        // lands after the user already fixed the handle is worse than no check.
        checkTask?.cancel()
        checkTask = nil

        guard !handle.isEmpty, handle != Self.normalize(initialUsername) else {
            verdict = .idle
            return
        }
        guard handle.count >= Self.minLength else {
            verdict = .tooShort
            return
        }
        guard !handle.unicodeScalars.contains(where: { !Self.allowed.contains($0) }) else {
            verdict = .invalidChars
            return
        }

        verdict = .checking
        checkTask = Task { @MainActor in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            let answer = await checkAvailability(handle)
            // Two guards, not one. `cancel()` is cooperative, so a reply can
            // still land after the next keystroke started its own task;
            // comparing the handle we asked about against what is on screen
            // NOW is what actually stops a stale verdict overwriting a fresh
            // one — the sleep only collapses the common case.
            guard !Task.isCancelled, handle == text else { return }
            switch answer {
            case .some(true): verdict = .free
            case .some(false): verdict = .taken
            case .none: verdict = .checkFailed
            }
        }
    }

    private func commit() {
        let handle = Self.normalize(text)
        guard handle.count >= Self.minLength else { return }
        onSave(handle)
        dismiss()
    }
}
