import SwiftUI

/// Stereo scan sheet (Figma 539:119, BT-off state 547:126).
/// Scan/save logic is unchanged from the pre-redesign sheet.
struct BluetoothScanSheet: View {
    let vehicleId: UUID

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @ObservedObject private var bluetoothDetector = AutoTripService.shared.bluetoothDetector
    @ObservedObject private var audioRouteDetector = AutoTripService.shared.audioRouteDetector
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            header(c: c, l: l)
            if bluetoothDetector.isBluetoothAvailable {
                scanContent(c: c, l: l)
            } else {
                bluetoothOffState(c: c, l: l)
            }
        }
        .background(c.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            bluetoothDetector.startScanning()
        }
    }

    // MARK: - Header

    private func header(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // Figma 539:119/547:126: leading title, trailing close.
        HStack {
            Text(AppStrings.linkStereo(l))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(c.text)
            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Bluetooth Off (Figma 547:126)

    private func bluetoothOffState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(c.cardAlt)
                    .frame(width: 72, height: 72)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32))
                    .foregroundStyle(c.textSecondary)
            }
            Text(AppStrings.btOffTitle(l))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
            Text(AppStrings.btOffSheetBody(l))
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(AppStrings.openSettings(l))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scan Content

    private func scanContent(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                audioOutputSection(c: c, l: l)
                nearbySection(c: c, l: l)
                Text(AppStrings.scanHint(l))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Current Audio Output (classic BT — e.g. stereo already playing)

    @ViewBuilder
    private func audioOutputSection(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if let audioDevice = audioRouteDetector.currentBluetoothOutput(),
           !settings.savedBluetoothDevices.contains(where: { $0.name == audioDevice }) {
            VStack(alignment: .leading, spacing: 8) {
                GarageSectionLabel(text: AppStrings.currentAudioOutput(l))
                    .padding(.horizontal, 2)

                Button {
                    saveDevice(name: audioDevice, uuid: "audio-\(audioDevice)")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.accent)
                        // Long stereo names truncate first so the trailing + never falls off
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audioDevice)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(c.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(AppStrings.bluetoothAudio(l))
                                .font(.system(size: 12))
                                .foregroundStyle(c.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(c.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(c.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Nearby Devices

    private func nearbySection(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GarageSectionLabel(text: AppStrings.nearbyDevices(l))
                Spacer()
                if !bluetoothDetector.isScanning {
                    Button {
                        bluetoothDetector.startScanning()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                if bluetoothDetector.isScanning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppTheme.accent)
                        Text(AppStrings.scanningDevices(l))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(c.textSecondary)
                        Spacer()
                    }
                    .padding(14)

                    if !bluetoothDetector.discoveredDevices.isEmpty {
                        rowDivider(c: c)
                    }
                }

                if bluetoothDetector.discoveredDevices.isEmpty {
                    if !bluetoothDetector.isScanning {
                        VStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.title3)
                                .foregroundStyle(c.textTertiary)
                            Text(AppStrings.noDevicesFound(l))
                                .font(.system(size: 13))
                                .foregroundStyle(c.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    let sorted = bluetoothDetector.discoveredDevices.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, device in
                        let saved = settings.savedBluetoothDevices.contains {
                            $0.uuid == device.id || $0.name == device.name
                        }
                        DeviceRow(
                            name: device.name,
                            rssi: device.rssi,
                            saved: saved,
                            scheme: scheme
                        ) {
                            saveDevice(name: device.name, uuid: device.id)
                        }
                        if index < sorted.count - 1 {
                            rowDivider(c: c)
                        }
                    }
                }
            }
            .background(c.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(c.border, lineWidth: 1)
            )
        }
    }

    private func rowDivider(c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.cardAlt)
            .frame(height: 1)
            .padding(.leading, 14)
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
                // Figma 539:119 draws a filled blue device disc before the name.
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.blue, in: Circle())
                // Long device names truncate first so the trailing badge stays visible
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(saved ? c.textTertiary : c.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if saved {
                    Text(AppStrings.added(LanguageManager.currentLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.green.opacity(0.14), in: Capsule())
                } else {
                    signalBars(c: c)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(saved)
    }

    private func signalBars(c: AppTheme.Colors) -> some View {
        let strength = signalStrength(rssi: rssi)
        let unfilled = scheme == .dark
            ? c.border
            : Color(red: 204/255, green: 204/255, blue: 209/255)

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= strength ? AppTheme.accent : unfilled)
                    .frame(width: 3, height: CGFloat(3 + bar * 3))
            }
        }
    }

    private func signalStrength(rssi: Int) -> Int {
        if rssi >= -50 { return 4 }
        if rssi >= -60 { return 3 }
        if rssi >= -70 { return 2 }
        return 1
    }
}
