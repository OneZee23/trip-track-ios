import SwiftUI
import CoreLocation

/// Auto-record settings (Figma 535:119). All toggle/mode/timeout logic is
/// ported 1:1 from the old bluetoothCard in VehicleDetailView — same
/// bindings, same side effects.
struct AutoRecordSettingsView: View {
    let vehicleId: UUID

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared

    @State private var showBluetoothScan = false
    @State private var permissionLocationManager: CLLocationManager?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(c: c, l: l)
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    toggleCard(c: c, l: l)
                    if settings.autoRecordMode != .off {
                        enabledSections(c: c, l: l)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .background(c.bg)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showBluetoothScan) {
            BluetoothScanSheet(vehicleId: vehicleId)
                .environmentObject(lang)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
    }

    // MARK: - Nav Row

    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            Text(AppStrings.autoRecord(l))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
            HStack {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(c.text)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Toggle Card

    private func toggleCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let isEnabled = settings.autoRecordMode != .off

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(isEnabled ? AppTheme.accent : c.textTertiary)
                Text(AppStrings.autoRecord(l))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer()
                Toggle(AppStrings.autoRecord(l), isOn: Binding(
                    get: { settings.autoRecordMode != .off },
                    set: { newValue in
                        if newValue {
                            settings.autoRecordMode = .remind
                            requestAutoRecordPermissions()
                        } else {
                            settings.autoRecordMode = .off
                        }
                        AutoTripService.shared.startIfNeeded()
                    }
                ))
                .tint(AppTheme.accent)
                .labelsHidden()
            }

            Rectangle().fill(c.border).frame(height: 1)

            Text(AppStrings.autoRecordDescription(l))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Enabled Sections (gated on mode != .off, as before)

    @ViewBuilder
    private func enabledSections(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        GarageSectionLabel(text: AppStrings.stereoSection(l))
            .padding(.top, 6)
            .padding(.horizontal, 2)
        stereoCard(c: c, l: l)

        GarageSectionLabel(text: AppStrings.autoRecordMode(l))
            .padding(.top, 6)
            .padding(.horizontal, 2)
        modeSegment(c: c)
        Text(settings.autoRecordMode == .auto
             ? AppStrings.autoModeDescription(l)
             : AppStrings.remindModeDescription(l))
            .font(.system(size: 12))
            .foregroundStyle(c.textTertiary)
            .padding(.horizontal, 2)

        GarageSectionLabel(text: AppStrings.autoStopTimeout(l))
            .padding(.top, 6)
            .padding(.horizontal, 2)
        timeoutCard(c: c, l: l)
        Text(AppStrings.autoStopDescription(l))
            .font(.system(size: 12))
            .foregroundStyle(c.textTertiary)
            .padding(.horizontal, 2)
    }

    // MARK: - Stereo Card

    private func stereoCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let devices = settings.savedBluetoothDevices.filter { $0.vehicleId == vehicleId }

        return VStack(spacing: 0) {
            ForEach(devices) { device in
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.accent)
                    Text(device.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(AppStrings.linked(l))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.green.opacity(0.14), in: Capsule())
                    // Unlink stays possible even though Figma draws none (fork F15).
                    Button {
                        settings.removeBluetoothDevice(uuid: device.uuid)
                        AutoTripService.shared.startIfNeeded()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(c.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Rectangle().fill(c.cardAlt).frame(height: 1).padding(.leading, 14)
            }

            Button {
                Haptics.tap()
                showBluetoothScan = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text(AppStrings.linkStereo(l))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Mode Segment (custom, Figma style)

    private func modeSegment(c: AppTheme.Colors) -> some View {
        let l = lang.language
        return HStack(spacing: 4) {
            modeSegmentButton(title: AppStrings.autoRecordRemind(l), mode: .remind, c: c)
            modeSegmentButton(title: AppStrings.autoRecordAuto(l), mode: .auto, c: c)
        }
        .padding(3)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
    }

    private func modeSegmentButton(title: String, mode: AutoRecordMode, c: AppTheme.Colors) -> some View {
        let isSelected = settings.autoRecordMode == mode
        return Button {
            Haptics.selection()
            settings.autoRecordMode = mode
            AutoTripService.shared.startIfNeeded()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? c.text : c.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(c.card)
                            .shadow(
                                color: scheme == .dark ? .clear : .black.opacity(0.06),
                                radius: 2,
                                y: 1
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Auto-Stop Timeout

    private func timeoutCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 8) {
            Text(AppStrings.autoStopTimeout(l))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            stepperButton(systemImage: "minus", enabled: settings.autoStopTimeout > 1, c: c) {
                settings.autoStopTimeout = max(1, settings.autoStopTimeout - 1)
            }
            Text(AppStrings.autoStopMinutes(l, minutes: settings.autoStopTimeout))
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(c.text)
                .frame(width: 54)
            stepperButton(systemImage: "plus", enabled: settings.autoStopTimeout < 10, c: c) {
                settings.autoStopTimeout = min(10, settings.autoStopTimeout + 1)
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func stepperButton(systemImage: String, enabled: Bool, c: AppTheme.Colors, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? c.text : c.textTertiary)
                .frame(width: 32, height: 32)
                .background(c.cardAlt, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Permissions (ported verbatim)

    private func requestAutoRecordPermissions() {
        NotificationManager.shared.requestAuthorization { _ in }
        MotionDetector.requestAuthorization { _ in }
        // Must retain CLLocationManager until dialog completes
        let manager = CLLocationManager()
        permissionLocationManager = manager
        manager.requestAlwaysAuthorization()
    }
}
