import UIKit
import LinkPresentation

/// One way to hand a link to the system share sheet.
///
/// Two things kept going wrong with the hand-rolled call sites:
///
/// 1. **«Copy» copied nothing.** A bare `URL` in `activityItems` leaves every
///    activity to guess the type from the object, and the pasteboard activity
///    can end up with a placeholder instead of the link. Declaring the item
///    through `UIActivityItemSource` — with `public.url` as its data type and
///    the URL returned for EVERY activity — is what makes Copy, Messages and
///    Safari all receive the same thing.
/// 2. **Nothing opened at all.** The sheet is raised from an action that ran
///    while a popover was still dismissing, and UIKit drops a `present` onto a
///    controller in that state silently. So we WAIT for a controller that can
///    actually present rather than guessing at a delay.
enum ShareLinkPresenter {
    /// Presents the share sheet for `url`, waiting up to ~1.6s for the
    /// topmost controller to finish whatever transition it is in.
    @MainActor
    static func present(url: URL, title: String) async {
        for _ in 0..<20 {
            if let top = topPresentedViewController(),
               !top.isBeingDismissed,
               top.presentedViewController == nil {
                let item = LinkActivityItem(url: url, title: title)
                let av = UIActivityViewController(activityItems: [item], applicationActivities: nil)
                // iPad has no sheet to fall back on; without an anchor the
                // popover presentation traps.
                av.popoverPresentationController?.sourceView = top.view
                av.popoverPresentationController?.sourceRect = CGRect(
                    x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1
                )
                top.present(av, animated: true)
                return
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }

    /// The profile is often on screen inside a sheet (Discover, the inbox),
    /// and asking the root controller to present over one drops the activity
    /// sheet on the floor.
    @MainActor
    static func topPresentedViewController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

/// The link, spelled out for the share sheet: same URL for every activity, a
/// subject line for mail, and metadata so the sheet draws the rich link card
/// instead of a bare string.
final class LinkActivityItem: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    /// Without this the pasteboard activity has to infer a type from the
    /// placeholder; saying `public.url` outright is what the Copy activity
    /// reads to decide it is copying a link.
    func activityViewController(
        _ controller: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "public.url"
    }

    func activityViewControllerLinkMetadata(
        _ controller: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        return metadata
    }
}
