import SwiftUI
import CoreLocation

struct DevMenuView: View {
    @ObservedObject var viewModel: MapViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Developer Mode Section
                Section {
                    Toggle("Developer Mode", isOn: Binding(
                        get: { viewModel.locationManager.isDeveloperMode },
                        set: { newValue in
                            if !viewModel.isRecording {
                                viewModel.locationManager.isDeveloperMode = newValue
                            }
                        }
                    ))
                    .disabled(viewModel.isRecording)

                    if viewModel.isRecording {
                        Text("Stop recording to change mode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.locationManager.isDeveloperMode {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Dev mode active")
                                .foregroundStyle(.green)
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Developer Mode")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("In dev mode:")
                        Text("• Joystick controls virtual position")
                        Text("• Real GPS disabled during recording")
                        Text("• Start point = current GPS position")
                        Text("• Joystick appears when recording starts")
                    }
                    .font(.caption)
                }

                // Location Info Section
                Section("Current Location") {
                    if let location = viewModel.locationManager.currentLocation {
                        LocationInfoRow(
                            title: "Latitude",
                            value: String(format: "%.6f", location.coordinate.latitude),
                            icon: "mappin"
                        )
                        LocationInfoRow(
                            title: "Longitude",
                            value: String(format: "%.6f", location.coordinate.longitude),
                            icon: "mappin"
                        )
                        LocationInfoRow(
                            title: "Speed",
                            value: String(format: "%.1f km/h", location.speed * 3.6),
                            icon: "speedometer"
                        )
                        LocationInfoRow(
                            title: "Course",
                            value: String(format: "%.1f°", location.course),
                            icon: "arrow.up"
                        )
                        LocationInfoRow(
                            title: "Accuracy",
                            value: String(format: "%.1f m", location.horizontalAccuracy),
                            icon: "target"
                        )
                        LocationInfoRow(
                            title: "Mode",
                            value: viewModel.locationManager.mode == .simulated ? "Simulated" : "Real GPS",
                            icon: viewModel.locationManager.mode == .simulated ? "gamecontroller" : "location.fill"
                        )
                    } else {
                        Label("No location available", systemImage: "location.slash")
                            .foregroundStyle(.secondary)
                    }
                }

                // Tracking Info Section
                Section("Tracking Status") {
                    LocationInfoRow(
                        title: "Recording",
                        value: viewModel.isRecording ? "Active" : "Inactive",
                        icon: viewModel.isRecording ? "record.circle.fill" : "record.circle",
                        valueColor: viewModel.isRecording ? .red : .secondary
                    )

                    if viewModel.isRecording {
                        LocationInfoRow(
                            title: "Distance",
                            value: String(format: "%.2f km", viewModel.distance),
                            icon: "ruler"
                        )
                        LocationInfoRow(
                            title: "Duration",
                            value: viewModel.duration,
                            icon: "clock"
                        )
                        LocationInfoRow(
                            title: "Track Points",
                            value: "\(viewModel.trackManager.confirmedPoints.count + (viewModel.trackManager.animatedHeadPosition != nil ? 1 : 0))",
                            icon: "point.topleft.down.curvedto.point.bottomright.up"
                        )
                        LocationInfoRow(
                            title: "Smooth Points",
                            value: "\(viewModel.trackManager.smoothDisplayPoints.count)",
                            icon: "waveform.path"
                        )
                    }
                }

                // Speed & Stats Section
                Section("Current Stats") {
                    LocationInfoRow(
                        title: "Current Speed",
                        value: String(format: "%.1f km/h", viewModel.speed),
                        icon: "gauge"
                    )
                    LocationInfoRow(
                        title: "Altitude",
                        value: String(format: "%.0f m", viewModel.altitude),
                        icon: "mountain.2"
                    )
                }

                // Joystick Info (only in dev mode)
                if viewModel.locationManager.isDeveloperMode {
                    Section("Joystick Control") {
                        let joystick = viewModel.locationManager.joystickInput
                        let magnitude = sqrt(joystick.x * joystick.x + joystick.y * joystick.y)
                        let angle = atan2(joystick.x, joystick.y) * 180 / .pi

                        LocationInfoRow(
                            title: "Input X",
                            value: String(format: "%.2f", joystick.x),
                            icon: "arrow.left.right"
                        )
                        LocationInfoRow(
                            title: "Input Y",
                            value: String(format: "%.2f", joystick.y),
                            icon: "arrow.up.down"
                        )
                        LocationInfoRow(
                            title: "Magnitude",
                            value: String(format: "%.2f", magnitude),
                            icon: "waveform"
                        )
                        LocationInfoRow(
                            title: "Direction",
                            value: String(format: "%.1f°", angle >= 0 ? angle : angle + 360),
                            icon: "arrow.triangle.2.circlepath"
                        )

                        if viewModel.isRecording {
                            Text("Joystick active on map")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Start recording to activate joystick")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Dev Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Location Info Row

struct LocationInfoRow: View {
    let title: String
    let value: String
    let icon: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Joystick (used on map overlay too)

struct JoystickView: View {
    let onDirectionChange: (CGVector) -> Void
    var radius: CGFloat = 70

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray5).opacity(0.6))
                .frame(width: radius * 2, height: radius * 2)

            VStack {
                Image(systemName: "chevron.up").offset(y: -8)
                Spacer()
                Image(systemName: "chevron.down").offset(y: 8)
            }
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.4))
            .frame(height: radius * 2 - 20)

            HStack {
                Image(systemName: "chevron.left").offset(x: -8)
                Spacer()
                Image(systemName: "chevron.right").offset(x: 8)
            }
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.4))
            .frame(width: radius * 2 - 20)

            Circle()
                .fill(.blue)
                .frame(width: 44, height: 44)
                .shadow(color: .blue.opacity(0.3), radius: 8)
                .offset(dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let vector = CGSize(
                                width: value.translation.width,
                                height: value.translation.height
                            )
                            let distance = sqrt(vector.width * vector.width + vector.height * vector.height)
                            if distance <= radius {
                                dragOffset = vector
                            } else {
                                let scale = radius / distance
                                dragOffset = CGSize(width: vector.width * scale, height: vector.height * scale)
                            }
                            let nx = dragOffset.width / radius
                            let ny = -dragOffset.height / radius
                            onDirectionChange(CGVector(dx: nx, dy: ny))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3)) {
                                dragOffset = .zero
                            }
                            onDirectionChange(.zero)
                        }
                )
        }
    }
}

struct JoystickViewNoReturn: View {
    @Binding var value: CGPoint
    var currentCourse: Double = 0

    let size: CGFloat = 120
    let knobSize: CGFloat = 50

    @State private var knobOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            Path { path in
                let center = size / 2
                path.move(to: CGPoint(x: center, y: 10))
                path.addLine(to: CGPoint(x: center, y: size - 10))
                path.move(to: CGPoint(x: 10, y: center))
                path.addLine(to: CGPoint(x: size - 10, y: center))
            }
            .stroke(.white.opacity(0.3), lineWidth: 1.5)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-currentCourse), anchor: .center)

            VStack(spacing: 0) {
                Text("N")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: -size/2 + 18)
                Spacer()
                Text("S")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: size/2 - 18)
            }
            .frame(height: size)
            .rotationEffect(.degrees(-currentCourse), anchor: .center)

            HStack(spacing: 0) {
                Text("W")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(x: -size/2 + 18)
                Spacer()
                Text("E")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(x: size/2 - 18)
            }
            .frame(width: size)
            .rotationEffect(.degrees(-currentCourse), anchor: .center)

            Image(systemName: "arrow.up")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.orange.opacity(0.8))
                .offset(y: -size/2 + 25)
                .rotationEffect(.degrees(-currentCourse), anchor: .center)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .offset(knobOffset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        let maxOffset = (size - knobSize) / 2
                        let vector = CGSize(
                            width: gesture.translation.width,
                            height: gesture.translation.height
                        )
                        let distance = sqrt(vector.width * vector.width + vector.height * vector.height)

                        if distance <= maxOffset {
                            knobOffset = vector
                        } else {
                            let scale = maxOffset / distance
                            knobOffset = CGSize(
                                width: vector.width * scale,
                                height: vector.height * scale
                            )
                        }

                        value = CGPoint(
                            x: knobOffset.width / maxOffset,
                            y: -knobOffset.height / maxOffset
                        )
                    }
            )
        }
    }
}
