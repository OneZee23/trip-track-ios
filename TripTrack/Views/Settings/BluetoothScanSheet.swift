import SwiftUI

struct BluetoothScanSheet: View {
    let vehicleId: UUID

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var bluetoothDetector = AutoTripService.shared.bluetoothDetector
    @ObservedObject private var audioRouteDetector = AutoTripService.shared.audioRouteDetector
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Current audio output (classic BT — e.g. car stereo already playing)
                    audioOutputCard(c: c, l: l)

                    // BLE scan results
                    nearbyDevicesCard(c: c, l: l)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(c.bg)
            .navigationTitle(AppStrings.linkStereo(l))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppStrings.done(l)) { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .task {
                bluetoothDetector.startScanning()
            }
        }
    }

    // MARK: - Audio Output Card

    @ViewBuilder
    private func audioOutputCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if let audioDevice = audioRouteDetector.currentBluetoothOutput(),
           !settings.savedBluetoothDevices.contains(where: { $0.name == audioDevice }) {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(AppStrings.currentAudioOutput(l))
                        .font(.system(size: 15, weight: .semibold))
                } icon: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(AppTheme.accent)
                }

                Button {
                    saveDevice(name: audioDevice, uuid: "audio-\(audioDevice)")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "car.rear.and.tire.marks")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audioDevice)
                                .font(.system(size: 15))
                            Text(AppStrings.bluetoothAudio(l))
                                .font(.system(size: 12))
                                .foregroundStyle(c.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
    }

    // MARK: - Nearby Devices Card

    private func nearbyDevicesCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(AppStrings.nearbyDevices(l))
                        .font(.system(size: 15, weight: .semibold))
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
                if bluetoothDetector.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        bluetoothDetector.startScanning()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }

            if bluetoothDetector.discoveredDevices.isEmpty {
                if bluetoothDetector.isScanning {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            ProgressView()
                            Text(AppStrings.scanningDevices(l))
                                .font(.system(size: 13))
                                .foregroundStyle(c.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.title3)
                                .foregroundStyle(c.textTertiary)
                            Text(AppStrings.noDevicesFound(l))
                                .font(.system(size: 13))
                                .foregroundStyle(c.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            } else {
                let sorted = bluetoothDetector.discoveredDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                ForEach(sorted) { device in
                    let saved = settings.savedBluetoothDevices.contains { $0.uuid == device.id || $0.name == device.name }
                    DeviceRow(
                        name: device.name,
                        rssi: device.rssi,
                        saved: saved,
                        scheme: scheme
                    ) {
                        saveDevice(name: device.name, uuid: device.id)
                    }
                }
            }

            Text(AppStrings.scanHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Actions

    private func saveDevice(name: String, uuid: String) {
        let saved = SavedBluetoothDevice(uuid: uuid, name: name, vehicleId: vehicleId)
        settings.addBluetoothDevice(saved)
        AutoTripService.shared.startIfNeeded()
        dismiss()
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let name: String
    let rssi: Int
    let saved: Bool
    let scheme: ColorScheme
    let onAdd: () -> Void

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            guard !saved else { return }
            onAdd()
        } label: {
            HStack(spacing: 10) {
                signalBars
                Text(name)
                    .font(.system(size: 15))
                    .foregroundStyle(saved ? c.textTertiary : AppTheme.textPrimary)
                Spacer()
                if saved {
                    Text("Added")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(saved)
    }

    private var signalBars: some View {
        let strength = signalStrength(rssi: rssi)
        let color: Color = switch strength {
        case 3: .green
        case 2: .orange
        default: .red
        }

        return HStack(spacing: 1.5) {
            ForEach(1...3, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= strength ? color : color.opacity(0.2))
                    .frame(width: 4, height: CGFloat(4 + bar * 4))
            }
        }
        .frame(width: 20, height: 16, alignment: .bottom)
    }

    private func signalStrength(rssi: Int) -> Int {
        switch rssi {
        case -50...0: return 3
        case -70...(-51): return 2
        default: return 1
        }
    }
}
