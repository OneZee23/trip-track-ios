import SwiftUI
import MapKit

struct LocationTrackingButton: View {
    let mode: MKUserTrackingMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .glassBackground(cornerRadius: 12)
        }
    }

    private var iconName: String {
        switch mode {
        case .none:
            return "location"
        case .follow:
            return "location.fill"
        case .followWithHeading:
            return "location.north.line.fill"
        @unknown default:
            return "location"
        }
    }

    private var iconColor: Color {
        switch mode {
        case .none:
            return AppTheme.textPrimary
        case .follow, .followWithHeading:
            return AppTheme.accent
        @unknown default:
            return AppTheme.textPrimary
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        LocationTrackingButton(mode: .none, action: {})
        LocationTrackingButton(mode: .follow, action: {})
        LocationTrackingButton(mode: .followWithHeading, action: {})
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
