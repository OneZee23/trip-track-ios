import SwiftUI

/// Заглушка до Task 4 (карточка места, история проездов, направления).
struct PlaceDetailView: View {
    let placeId: UUID
    let onOpenTrip: (UUID, TripFocus) -> Void

    var body: some View {
        Text(placeId.uuidString)
            .toolbar(.hidden, for: .navigationBar)
    }
}
