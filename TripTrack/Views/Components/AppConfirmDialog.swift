import SwiftUI

// MARK: - Action

/// One answer on a house dialog.
///
/// `kind` decides the colour, not the caller: a screen should say what the
/// button MEANS and let the component decide what that looks like, or the
/// twentieth dialog invents its own red.
struct AppDialogAction: Identifiable {
    enum Kind {
        /// The ordinary confirming answer — accent fill, white ink.
        case primary
        /// Irreversible. Red fill, white ink.
        case destructive
        /// A secondary choice that is neither — quiet fill, normal ink.
        case plain
    }

    let id = UUID()
    let title: String
    var kind: Kind = .primary
    /// Set when a row needs its own identifier for the UI tests.
    var identifier: String?
    let handler: () -> Void

    init(_ title: String,
         kind: Kind = .primary,
         identifier: String? = nil,
         handler: @escaping () -> Void = {}) {
        self.title = title
        self.kind = kind
        self.identifier = identifier
        self.handler = handler
    }
}

// MARK: - Dialog

/// The app's own modal. Replaces every `alert` / `confirmationDialog` /
/// `actionSheet` in the codebase — see the «Dialogs» section of CLAUDE.md for
/// why none of those may ship here.
///
/// Shape: a scrim that swallows taps, the question in our type on our card, and
/// the answers stacked with the safe one nearest the thumb. Deliberately the
/// same anatomy `TrackingView.stopConfirmSheet` already used, generalised so
/// every screen stops rolling its own.
///
/// Two traps this component exists to close, both of which shipped before it:
///  • A system dialog dismisses itself on any button tap; an overlay does not.
///    Every action here dismisses BEFORE it runs its handler, so no caller can
///    forget and leave a card hanging over a write that already happened.
///  • A plain overlay is not a modal to VoiceOver — the rotor walks past the
///    scrim onto the page behind it. The scrim is hidden and the card is a
///    proper accessibility container.
struct AppConfirmDialog: View {
    let title: String
    var message: String?
    let actions: [AppDialogAction]
    /// nil hides the cancel row entirely — only for dialogs that are pure
    /// acknowledgement («понятно»), where the single action IS the way out.
    var cancelTitle: String?
    let onDismiss: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    /// Drives the entrance from INSIDE the dialog.
    ///
    /// The presentation itself is animation-free (see `AppConfirmPresenter`):
    /// UIKit's cover transition slides the whole layer up from the bottom
    /// edge, and with a scrim on it that reads as a grey plate sliding in
    /// behind the card — a bug, not a modal. With the slide off, the scrim and
    /// the card fade and settle here, on our own curve.
    @State private var appeared = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            Color.black
                .opacity(appeared ? 0.35 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .accessibilityHidden(true)

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 13.5))
                            .lineSpacing(3)
                            .foregroundStyle(c.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(actions) { action in
                        button(action, c: c)
                    }

                    if let cancelTitle {
                        Button {
                            Haptics.tap()
                            dismiss()
                        } label: {
                            label(cancelTitle, ink: c.textSecondary, fill: c.cardAlt)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("app_dialog_cancel")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(c.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
            .padding(.horizontal, 24)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("app_dialog")
        }
        .onAppear {
            AppDialogPresentation.opened()
            withAnimation(.easeOut(duration: 0.22)) { appeared = true }
        }
        .onDisappear { AppDialogPresentation.closed() }
    }

    /// Play the exit before handing control back, so the card leaves the way it
    /// arrived instead of vanishing between two frames.
    private func dismiss(then work: (() -> Void)? = nil) {
        withAnimation(.easeIn(duration: 0.16)) { appeared = false }
        Task { @MainActor in
            // Matches the exit curve above. CLAUDE.md forbids
            // DispatchQueue.main.async in new code.
            try? await Task.sleep(nanoseconds: 160_000_000)
            onDismiss()
            work?()
        }
    }

    private func button(_ action: AppDialogAction, c: AppTheme.Colors) -> some View {
        Button {
            switch action.kind {
            case .destructive: Haptics.action()
            case .primary:     Haptics.success()
            case .plain:       Haptics.tap()
            }
            // Dismiss FIRST: the handler may push a screen or present another
            // sheet, and doing that under a card still on screen is how you get
            // two modals fighting over the same window.
            dismiss(then: action.handler)
        } label: {
            switch action.kind {
            case .primary:
                label(action.title, ink: .white, fill: AppTheme.accent)
            case .destructive:
                label(action.title, ink: .white, fill: AppTheme.red)
            case .plain:
                label(action.title, ink: c.text, fill: c.cardAlt)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(action.identifier ?? "app_dialog_action")
    }

    private func label(_ text: String, ink: Color, fill: Color) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(ink)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Modifiers

extension View {
    /// House replacement for `.alert` / `.confirmationDialog`.
    ///
    ///     .appConfirm(isPresented: $confirmingDelete,
    ///                 title: AppStrings.deleteTripTitle(l),
    ///                 message: AppStrings.deleteTripBody(l),
    ///                 actions: [
    ///                     AppDialogAction(AppStrings.delete(l), kind: .destructive) { delete() }
    ///                 ])
    ///
    /// `cancelTitle` defaults to «Отмена»; pass nil only for an acknowledgement
    /// whose single action is itself the way out.
    func appConfirm(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        actions: [AppDialogAction],
        cancelTitle: String? = AppStrings.cancel(LanguageManager.currentLanguage)
    ) -> some View {
        modifier(AppConfirmPresenter(
            isPresented: isPresented,
            title: title,
            message: message,
            actions: actions,
            cancelTitle: cancelTitle
        ))
    }

    /// Item-driven variant, for the call sites that carry their subject in an
    /// optional rather than a Bool («delete THIS photo»).
    func appConfirm<Item: Identifiable>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        message: @escaping (Item) -> String? = { _ in nil },
        actions: @escaping (Item) -> [AppDialogAction],
        cancelTitle: String? = AppStrings.cancel(LanguageManager.currentLanguage)
    ) -> some View {
        modifier(AppConfirmItemPresenter(
            item: item,
            title: title,
            message: message,
            actions: actions,
            cancelTitle: cancelTitle
        ))
    }
}

// MARK: - Presentation

/// Puts the dialog on screen without UIKit's transition.
///
/// Two things had to be true at once, and one modifier is what makes them
/// compatible.
///
/// It is a transparent `fullScreenCover` and NOT an `overlay`, because an
/// overlay is laid out inside the view it modifies: hung on a section inside a
/// ScrollView the dialog got a scrim the size of that section, scrolled away
/// with the content and could be clipped off-screen entirely, and on a tab root
/// the custom tab bar painted straight over the scrim and stayed tappable — you
/// could change tabs with a delete pending. A cover is window-level, so every
/// dialog outranks all of it without each call site having to know where it
/// sits in the tree.
///
/// But a cover is presented with `coverVertical`: the layer slides up from the
/// bottom edge, so the scrim arrives as a grey plate sweeping in behind the
/// card. Suppressing that needs the transaction that PRESENTS it to carry
/// `disablesAnimations`, which the caller's `showDelete = true` does not — and
/// it is not the caller's job to know. Hence the mirrored state below: the
/// caller flips its own flag however it likes, and the flip is replayed into
/// `shown` inside a transaction we control. (An earlier attempt put
/// `.transaction` on the cover's CONTENT instead, which suppresses nothing at
/// the presentation edge and silently killed the card's own fade.)
private struct AppConfirmPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    var message: String?
    let actions: [AppDialogAction]
    var cancelTitle: String?

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onAppear { present(isPresented) }
            .onChange(of: isPresented) { _, new in present(new) }
            .fullScreenCover(isPresented: $shown) {
                AppConfirmDialog(
                    title: title,
                    message: message,
                    actions: actions,
                    cancelTitle: cancelTitle,
                    onDismiss: {
                        present(false)
                        isPresented = false
                    }
                )
                // See-through, so the page stays visible under the scrim the
                // dialog paints itself.
                .presentationBackground(.clear)
            }
    }

    private func present(_ value: Bool) {
        guard shown != value else { return }
        guard value else {
            withoutPresentationAnimation { shown = false }
            return
        }
        // Wait out any dialog still on screen — see `AppDialogPresentation`.
        Task { @MainActor in
            await AppDialogPresentation.waitUntilFree()
            guard isPresented, !shown else { return }
            withoutPresentationAnimation { shown = true }
        }
    }
}

private struct AppConfirmItemPresenter<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let title: (Item) -> String
    let message: (Item) -> String?
    let actions: (Item) -> [AppDialogAction]
    var cancelTitle: String?

    @State private var shown: Item?

    func body(content: Content) -> some View {
        content
            .onAppear { present(item) }
            // Keyed on the id: `Item` is only `Identifiable`, and that is the
            // one part of it this can compare.
            .onChange(of: item?.id) { _, _ in present(item) }
            .fullScreenCover(item: $shown) { value in
                AppConfirmDialog(
                    title: title(value),
                    message: message(value),
                    actions: actions(value),
                    cancelTitle: cancelTitle,
                    onDismiss: {
                        present(nil)
                        item = nil
                    }
                )
                .presentationBackground(.clear)
            }
    }

    private func present(_ value: Item?) {
        guard shown?.id != value?.id else { return }
        guard let value else {
            withoutPresentationAnimation { shown = nil }
            return
        }
        Task { @MainActor in
            await AppDialogPresentation.waitUntilFree()
            guard item?.id == value.id, shown?.id != value.id else { return }
            withoutPresentationAnimation { shown = value }
        }
    }
}

/// Runs `change` in a transaction that tells SwiftUI to present or dismiss
/// without UIKit's own animation.
private func withoutPresentationAnimation(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
}

/// How many house dialogs are on screen right now.
///
/// A dialog is a `fullScreenCover`, and UIKit will not present a cover onto a
/// controller that is still dismissing another one — it drops the second one
/// on the floor without raising anything. That is exactly how «Выйти из
/// аккаунта» came to do nothing at all: its confirm opened a SECOND dialog
/// («что сделать с публичными поездками?»), the present was dropped, and with
/// it the entire sign-out.
///
/// Merging such a pair into one question is the better call site (and what
/// that screen does now), but a modal that vanishes silently is too quiet a
/// failure to leave to discipline. A presenter that finds another dialog on
/// screen therefore WAITS for it rather than asking UIKit for the impossible.
@MainActor
enum AppDialogPresentation {
    private(set) static var openCount = 0

    static func opened() { openCount += 1 }
    static func closed() { openCount = max(0, openCount - 1) }

    /// Suspends until no dialog is on screen. Bounded at ~2s: a card that
    /// somehow never closes must not wedge every later dialog forever — after
    /// the wait we try anyway, which is no worse than the old behaviour.
    static func waitUntilFree() async {
        var attempts = 0
        while openCount > 0 && attempts < 40 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
    }
}
