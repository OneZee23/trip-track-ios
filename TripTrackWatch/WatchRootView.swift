import SwiftUI

/// Switches between idle ("tap to start") and recording (live speed +
/// pause/stop) based on the phone's published trip state. Two views
/// instead of one branchy body keeps each crowd-pleaser focused — the
/// recording screen needs a different visual hierarchy entirely.
struct WatchRootView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        Group {
            if session.isRecording {
                WatchRecordingView()
            } else {
                WatchIdleView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isRecording)
    }
}

struct WatchIdleView: View {
    @EnvironmentObject private var session: WatchSessionManager

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "car.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("TripTrack")
                .font(.headline)
            Button {
                session.send(action: "start")
            } label: {
                Label("Start trip", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!session.isReachable)
            if !session.isReachable {
                Text("Open TripTrack on iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 8)
    }
}

struct WatchRecordingView: View {
    @EnvironmentObject private var session: WatchSessionManager

    /// Те же числа теми же символами, что на телефоне и на локскрине: считает
    /// и подписывает общий `LiveActivityFormat` из `TripTrackShared`. До 0.6.7
    /// здесь стояло `String(format: "%.1f km")` — точка в любом языке и
    /// английское слово на русском циферблате.
    private var distance: LiveActivityFormat.Parts {
        LiveActivityFormat.distanceParts(
            km: session.distanceKm, unit: session.distanceUnit, code: session.language)
    }

    private var speed: LiveActivityFormat.Parts {
        LiveActivityFormat.speedParts(
            kmh: session.speedKmh, unit: session.distanceUnit, code: session.language)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(speed.value)
                .font(.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.orange)
            Text(speed.unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("\(distance.value) \(distance.unit)")
                Text(timeString(session.elapsedSeconds))
                    .monospacedDigit()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(session.isPaused ? .secondary : .primary)
            HStack(spacing: 8) {
                Button {
                    session.send(action: session.isPaused ? "resume" : "pause")
                } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
                Button(role: .destructive) {
                    session.send(action: "stop")
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.top, 4)
            if session.isPaused {
                Text("Paused")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 6)
    }

    private func timeString(_ s: Int) -> String {
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}
