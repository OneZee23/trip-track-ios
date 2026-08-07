import SwiftUI

/// Sharing SOMEONE ELSE'S trip (canon «Поделиться» compact sheet): a row
/// with the route thumbnail, the trip's name, whose it is and when, plus the
/// link — then «Поделиться» / «Скопировать».
///
/// Deliberately NOT the poster studio: that sheet exports a card with your
/// numbers on it, which is yours to publish. Passing on someone else's trip
/// is a link, so the sheet is about the link.
struct SharedTripLinkSheet: View {
    let trip: SocialFeedTrip
    let shareUrl: String?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var linkCopied = false
    /// Bottom edge of the content in the sheet's own space — the detent is
    /// sized from it, so there's no slab of empty background under the
    /// buttons and no guessed constant to drift.
    @State private var contentBottom: CGFloat = 0

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(AppStrings.share(lang.language))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(c.text)
                Spacer(minLength: 8)
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    NavCircleIcon(systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.closeSheet(lang.language))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            tripRow(c, isRu: isRu)
                .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    shareLink()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text(AppStrings.share(lang.language))
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    copyLink()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(linkCopied ? AppTheme.green : c.text)
                        Text(linkCopied
                             ? (isRu ? "Скопировано" : "Copied")
                             : (isRu ? "Скопировать" : "Copy"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(c.text)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(c.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(shareUrl == nil)
                .opacity(shareUrl == nil ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: LinkSheetHeightKey.self,
                        value: geo.frame(in: .named(Self.space)).maxY
                    )
                }
            )
        }
        .coordinateSpace(name: Self.space)
        .background(c.bg)
        .presentationCornerRadius(22)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .onPreferenceChange(LinkSheetHeightKey.self) { contentBottom = $0 }
    }

    private static let space = "linkShareContent"

    /// Exactly the content, plus a hair of breathing room.
    ///
    /// No home-indicator inset added on purpose: iOS floats a short sheet as
    /// a card above the indicator, so reserving that strip inside it just
    /// left dead space under the buttons and made the card look like it had
    /// lost its bottom half.
    private var sheetHeight: CGFloat {
        guard contentBottom > 0 else { return 250 }
        return contentBottom + 8
    }

    private func tripRow(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 12) {
            // Route thumbnail — the same vector art the poster uses, so the
            // sheet shows the trip you're passing on, not a generic icon.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(c.cardAlt)
                if trip.previewCoordinates.count > 1 {
                    GeometryReader { geo in
                        SharePosterRoute(
                            points: SharePosterView.project(
                                trip.previewCoordinates, in: geo.size, inset: 12
                            ),
                            lineWidth: 3.5
                        )
                    }
                    .padding(6)
                }
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(TripAutoTitle.localized(
                    trip.title, startDate: trip.startDate, language: lang.language
                ) ?? (isRu ? "Поездка" : "Trip"))
                    .font(.inter(15, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(2)

                Text(subtitle(isRu: isRu))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)

                if let shareUrl {
                    Text(shareUrl.replacingOccurrences(of: "https://", with: ""))
                        .font(.inter(12))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(c.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    private func subtitle(isRu: Bool) -> String {
        let raw = trip.author.displayName?.trimmingCharacters(in: .whitespaces) ?? ""
        let name = raw.isEmpty ? (isRu ? "Водитель" : "Driver") : raw
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        return "\(name) · \(when)"
    }

    private func shareLink() {
        guard let shareUrl, let url = URL(string: shareUrl) else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        topPresentedViewController()?.present(av, animated: true)
    }

    private func copyLink() {
        guard let shareUrl else { return }
        UIPasteboard.general.string = shareUrl
        linkCopied = true
        Haptics.success()
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { linkCopied = false }
        }
    }

    private func topPresentedViewController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }
}

/// Bottom edge of the link sheet's content, in the sheet's own space.
private struct LinkSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
