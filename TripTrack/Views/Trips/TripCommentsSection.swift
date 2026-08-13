import SwiftUI

/// «Обсуждение · N» — the discussion of a trip, in two shapes.
///
/// On the detail screen it is a TEASER of constant height: the two freshest
/// messages, a centred «Всё обсуждение · N ›» pill, and a row that looks like
/// a composer but is a door — tapping it opens the sheet with the keyboard
/// already up. Writing happens in one place, with the whole thread in view.
///
/// The same view with `isPreview: false` IS that sheet.
struct TripCommentsSection: View {
    let tripId: UUID
    /// Viewer owns the trip → may delete ANY comment (server enforces the
    /// same rule; this only drives the affordance).
    let isTripOwner: Bool
    /// Server-known total (feed DTO `commentCount`) shown in the header
    /// until the first page tells us better. 0 on the own-trip screen —
    /// the local Trip model carries no comment total.
    var initialCount: Int = 0
    /// Social screen only: called when a signed-OUT viewer taps the
    /// composer — parent presents its SignInPromptSheet. nil on the
    /// own-trip screen (composing there implies an account already).
    var onGuestInputTap: (() -> Void)? = nil
    /// Raise the keyboard as soon as the sheet is up — set when the user came
    /// in by tapping the write row.
    var startFocused: Bool = false
    /// Error surface — parents route the message into their toast host.
    var onError: (String) -> Void
    /// Opened from that comment's notification: page until it's loaded,
    /// scroll to it, then flash it so the user can see WHICH sentence the
    /// notification meant.
    var highlightCommentId: UUID? = nil
    /// Detail screens embed the PREVIEW (canon 549:129 shows three rows
    /// under a «Комментарии · 5» header — the block is a teaser, not the
    /// thread). The full-thread sheet renders the same view with this off,
    /// which is where replying lives.
    var isPreview: Bool = true

    @StateObject private var store = TripCommentsStore()
    /// Currently spotlighted comment — set on arrival, cleared after the
    /// flash so the row settles back to normal.
    @State private var spotlightId: UUID?
    @State private var draft = ""
    /// Comment being replied to. Drives the composer chip and is passed to
    /// the store so the server can thread it.
    @State private var replyTarget: TripComment?
    /// Full-thread sheet, opened from «Все ›» or by tapping a row.
    @State private var showAllComments = false
    /// Whether the sheet should open with the keyboard up — true when the user
    /// tapped the write row rather than the «Всё обсуждение» pill.
    @State private var openSheetFocused = false
    @State private var commentToDelete: TripComment?
    @FocusState private var composerFocused: Bool
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.colorScheme) private var scheme

    /// Header N: server total while the list hasn't loaded; once loaded,
    /// the live row count — except when more pages exist, where the server
    /// total (if known) is the honest figure. A FAILED first page taught us
    /// nothing — keep trusting the feed-DTO count instead of flipping a
    /// commented trip to «· 0».
    /// The teaser shows the two freshest messages; everything else lives in
    /// the sheet. Two is what keeps the block a constant ~180pt on the detail
    /// screen instead of a section that grows with the conversation.
    private static let previewLimit = 2

    /// Newest-first list; the preview keeps the freshest few.
    private var visibleComments: [TripComment] {
        isPreview ? Array(store.comments.prefix(Self.previewLimit)) : store.comments
    }

    private var displayCount: Int {
        guard store.hasLoadedOnce, !store.loadFailed else {
            return max(initialCount, store.comments.count)
        }
        if store.nextCursor != nil { return max(initialCount, store.comments.count) }
        return store.comments.count
    }

    var body: some View {
        // Backend without the comments module (route 404) — hide the whole
        // card rather than render a composer that can never succeed.
        if store.unavailable && store.comments.isEmpty {
            Color.clear
                .frame(height: 0)
                .task(id: tripId) { await store.load(tripId: tripId) }
        } else {
            content
        }
    }

    private var content: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(text: AppStrings.commentsTitleN(lang.language, displayCount))

            VStack(spacing: 0) {
                // Canon 545:520: an empty public thread invites rather than
                // showing a bare composer under a heading. The composer alone
                // read as a section that had failed to load its contents.
                // …but on the DETAIL that invitation is the composer row
                // itself, which already says «Написать первое сообщение…» —
                // stacking a second grey sentence above it produced two
                // muted lines in a row where neither looked tappable. In
                // the full-thread sheet the composer is pinned at the
                // bottom, far from the empty space it explains, so there
                // the line stays.
                if visibleComments.isEmpty, !isPreview {
                    Text(AppStrings.noCommentsYet(lang.language))
                        .font(.system(size: 14))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                    Rectangle()
                        .fill(c.border)
                        .frame(height: 1)
                }

                ForEach(visibleComments) { comment in
                    commentRow(comment, c: c)
                        .id(comment.id)
                    Rectangle()
                        .fill(c.border)
                        .frame(height: 1)
                }

                // The preview never paginates — the pill below is the way in.
                if !isPreview, store.nextCursor != nil {
                    showMoreButton
                }

                // On the detail the composer is a doorway, not a field: tapping
                // it opens the sheet with the keyboard already up, so writing
                // happens in one place with the whole thread in view.
                if isPreview {
                    Button {
                        Haptics.tap()
                        guard !(onGuestInputTap != nil && !auth.isSignedIn) else {
                            onGuestInputTap?()
                            return
                        }
                        openSheetFocused = true
                        showAllComments = true
                    } label: {
                        // Dressed as the text field it stands in for: a
                        // filled, bordered pill with a send glyph at the
                        // end. As a bare row of grey text it was
                        // indistinguishable from the empty-state line above
                        // it, so nothing on the section looked writable.
                        HStack(spacing: 10) {
                            Circle()
                                .fill(AppTheme.accent.opacity(0.12))
                                .frame(width: 30, height: 30)
                                .overlay { Text(settings.avatarEmoji).font(.system(size: 15)) }
                            Text(store.comments.isEmpty
                                 ? AppStrings.writeFirstMessage(lang.language)
                                 : AppStrings.commentPlaceholder(lang.language))
                                .font(.system(size: 14))
                                .foregroundStyle(c.textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(c.cardAlt)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(c.border, lineWidth: 1)
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discussion_cta_row")
                } else {
                    composerRow(c)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(c.card)
                    .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
            }

            if isPreview, displayCount > Self.previewLimit {
                Button {
                    Haptics.tap()
                    openSheetFocused = false
                    showAllComments = true
                } label: {
                    HStack(spacing: 4) {
                        Text(AppStrings.discussionSeeAllPill(lang.language, displayCount))
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(AppTheme.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("discussion_see_all")
            }
        }
        .task(id: tripId) {
            await store.load(tripId: tripId)
            await spotlightIfRequested()
        }
        .task {
            guard startFocused, !isPreview else { return }
            // A beat, so the sheet has finished presenting before the keyboard
            // is asked for — otherwise iOS drops the focus request.
            try? await Task.sleep(for: .milliseconds(350))
            composerFocused = true
        }
        .sheet(isPresented: $showAllComments) {
            TripCommentsScreen(
                tripId: tripId,
                isTripOwner: isTripOwner,
                initialCount: displayCount,
                startFocused: openSheetFocused,
                onError: onError
            )
            .environmentObject(lang)
        }
        .confirmationDialog(
            AppStrings.deleteCommentConfirm(lang.language),
            isPresented: Binding(
                get: { commentToDelete != nil },
                set: { if !$0 { commentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete(lang.language), role: .destructive) {
                guard let comment = commentToDelete else { return }
                commentToDelete = nil
                Haptics.action()
                Task {
                    if let err = await store.delete(
                        commentId: comment.id, language: lang.language) {
                        onError(err)
                    }
                }
            }
            Button(AppStrings.cancel(lang.language), role: .cancel) {}
        }
    }

    // MARK: - Spotlight

    /// Page forward until the target comment is loaded (bounded), then let
    /// the enclosing ScrollViewReader put it on screen and flash it.
    /// Bounded at 5 pages: past that the thread is huge and jumping the user
    /// hundreds of comments deep is worse than landing on the section.
    private func spotlightIfRequested() async {
        guard let target = highlightCommentId else { return }
        var pagesLoaded = 0
        while !store.comments.contains(where: { $0.id == target }),
              store.nextCursor != nil,
              pagesLoaded < 5 {
            await store.loadMore()
            pagesLoaded += 1
        }
        guard store.comments.contains(where: { $0.id == target }) else { return }
        // Let the rows lay out before scrolling, then hold the highlight
        // long enough to read the comment (2.4s) and fade it out.
        try? await Task.sleep(nanoseconds: 550_000_000)
        withAnimation(.easeOut(duration: 0.4)) { spotlightId = target }
        try? await Task.sleep(nanoseconds: 2_400_000_000)
        withAnimation(.easeInOut(duration: 0.7)) { spotlightId = nil }
    }

    // MARK: - Rows

    private func commentRow(_ comment: TripComment, c: AppTheme.Colors) -> some View {
        let canDelete = comment.isMine || isTripOwner
        let isSpotlit = spotlightId == comment.id
        let isReply = comment.parentId != nil
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(c.cardAlt)
                .frame(width: 34, height: 34)
                .overlay { Text(comment.user.avatarEmoji ?? "🚗").font(.system(size: 17)) }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(comment.user.displayName
                         ?? (lang.language == .ru ? "Без имени" : "No name"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text("· \(Self.relativeAge(of: comment.createdAt, lang: lang.language))")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                if isReply, let name = comment.replyToName {
                    // Named, not just indented: a reply can be paged in
                    // without its parent, and indentation alone then says
                    // nothing about WHO it answers.
                    Text(AppStrings.commentReplyingTo(lang.language, name))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                }
                Text(comment.text)
                    .font(.system(size: 14))
                    .lineSpacing(4.5)
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Reply lives in the full thread only: canon's preview is
                // three clean rows, and a «Ответить» under each one turned
                // the teaser into a wall of links.
                if !isPreview, !isGuestComposer {
                    Button {
                        Haptics.tap()
                        replyTarget = comment
                        composerFocused = true
                    } label: {
                        Text(AppStrings.commentReply(lang.language))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        // One step of indentation for replies — deeper nesting is what makes
        // phone threads unreadable, so the server keeps them all at depth 1.
        .padding(.leading, isReply ? 28 : 0)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Spotlight: arriving from «X прокомментировал» tints the row and
        // rides an accent rail down its leading edge for a couple of
        // seconds, so the sentence the notification meant is unmistakable
        // in a thread of similar-looking rows.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSpotlit ? AppTheme.accent.opacity(0.10) : Color.clear)
                .padding(.horizontal, 6)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isSpotlit ? AppTheme.accent : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, 6)
        }
        .contentShape(Rectangle())
        // Long-press delete for own comments (+ everything on own trips).
        // ScrollView has no swipeActions — context menu is the affordance.
        .contextMenu {
            if canDelete {
                Button(role: .destructive) {
                    commentToDelete = comment
                } label: {
                    Label(AppStrings.delete(lang.language), systemImage: "trash")
                }
            }
        }
    }

    private var showMoreButton: some View {
        Button {
            Haptics.tap()
            Task { await store.loadMore() }
        } label: {
            HStack(spacing: 6) {
                if store.isLoadingMore {
                    ProgressView().controlSize(.mini)
                }
                Text(AppStrings.showMoreComments(lang.language))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isLoadingMore)
    }

    // MARK: - Composer

    private func composerRow(_ c: AppTheme.Colors) -> some View {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGuest = onGuestInputTap != nil && !auth.isSignedIn
        return VStack(alignment: .leading, spacing: 6) {
            if let target = replyTarget {
                replyChip(target, c: c)
            }
            HStack(spacing: 8) {
            Circle()
                .fill(AppTheme.accent.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay { Text(settings.avatarEmoji).font(.system(size: 15)) }

            TextField(AppStrings.commentPlaceholder(lang.language), text: $draft, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .lineLimit(1...4)
                .focused($composerFocused)
                .onSubmit { sendDraft() }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 38)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 999))

            // A round «↑», grey until there is something to send. The word
            // «Отправить» is gone from the product: the arrow is the same
            // control everywhere, and it never has to be translated or
            // squeezed next to a growing field.
            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(
                            trimmed.isEmpty || store.isPosting
                                ? c.textTertiary.opacity(0.35)
                                : AppTheme.accent
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmed.isEmpty || store.isPosting)
            .accessibilityLabel(AppStrings.send(lang.language))
            .accessibilityIdentifier("discussion_send")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Guests read comments but can't compose — a tap anywhere on the
        // row surfaces the sign-in sheet instead of focusing the field.
        .overlay {
            if isGuest {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.tap()
                        onGuestInputTap?()
                    }
            }
        }
    }

    /// «В ответ N» above the field, with a way out. Without the cancel the
    /// only escape from reply mode is to send something.
    private func replyChip(_ target: TripComment, c: AppTheme.Colors) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            Text(AppStrings.commentReplyingTo(
                lang.language,
                target.user.displayName ?? (lang.language == .ru ? "Пользователь" : "User")
            ))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(c.textSecondary)
            .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                replyTarget = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(c.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .padding(.vertical, 4)
        .background(AppTheme.accentBg, in: Capsule())
        .padding(.leading, 38)
    }

    /// Guests read but can't compose — also hides the per-row «Ответить».
    private var isGuestComposer: Bool {
        onGuestInputTap != nil && !auth.isSignedIn
    }

    private func sendDraft() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !store.isPosting else { return }
        Haptics.action()
        draft = ""
        let target = replyTarget
        replyTarget = nil
        Task {
            if let err = await store.post(
                text: text, replyTo: target, language: lang.language) {
                onError(err)
                // Give the text back so the user can fix/retry instead of
                // retyping (only if they haven't started something new).
                if draft.isEmpty { draft = text }
            }
        }
    }

    // MARK: - Relative age

    /// Compact «2 ч» / "2 h" age used by the row header. Days cap the
    /// scale — comment feeds don't need week/month granularity.
    static func relativeAge(of date: Date, lang: LanguageManager.Language) -> String {
        let delta = max(0, Date().timeIntervalSince(date))
        if delta < 60 { return AppStrings.relTimeNow(lang) }
        if delta < 3600 { return AppStrings.relTimeMinutes(lang, Int(delta / 60)) }
        if delta < 86_400 { return AppStrings.relTimeHours(lang, Int(delta / 3600)) }
        return AppStrings.relTimeDays(lang, Int(delta / 86_400))
    }
}
