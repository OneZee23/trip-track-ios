import SwiftUI
import MapKit

/// Full-screen, interactive route viewer presented from both TripDetailView
/// and SocialTripDetailView when the user wants to see the route bigger
/// than the fixed 45%-of-screen map slot. Carries no business logic — just
/// RouteMapView pinned to the edges plus a close button over the top-left.
struct FullscreenMapSheet: View {
    let coordinates: [CLLocationCoordinate2D]
    var speeds: [Double] = []
    var fogCutoffDate: Date?
    /// Social trips pass `true` — their preview polyline is sparsely sampled
    /// and the gap-splitting in RouteMapView would zero out the bounds.
    var treatAsPreview: Bool = false

    @Environment(\.dismiss) private var dismiss

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 47
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RouteMapView(
                coordinates: coordinates,
                speeds: speeds,
                isInteractive: true,
                fogCutoffDate: fogCutoffDate,
                treatAsPreview: treatAsPreview
            )
            .ignoresSafeArea()

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(.top, safeAreaTop)
            .padding(.leading, 16)
        }
    }
}
