import SwiftUI
import CoreLocation

/// Auto-record settings (Figma 535:119). All toggle/mode/timeout logic is
/// ported 1:1 from the old bluetoothCard in VehicleDetailView — same
/// bindings, same side effects.
struct AutoRecordSettingsView: View {
    let vehicleId: UUID

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var settings = SettingsManager.shared

    @State private var showBluetoothScan = false
    @State private var permissionLocationManager: CLLocationManager?

    /// Canon «Завершить через 1–10 мин». Stated once so the disabled states of
    /// − / + and the clamps in their actions cannot drift apart.
    private static let timeoutRange = 1...10

    /// A bicycle or a moped pairs with no car stereo, so there is nothing for
    /// auto-record to key off. VehicleDetailView already hides the row that
    /// opens this screen; this is the second lock on the same door, and it
    /// also catches the vehicle being deleted or retyped while it is open.
    private var supportsAutoRecord: Bool {
        settings.vehicles.first { $0.id == vehicleId }?.type.supportsAutoRecord ?? false
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(l: l)
            if supportsAutoRecord {
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
            } else {
                // The nav row stays: a sheet with no controls AND no way back
                // is worse than one that is merely empty.
                Spacer()
            }
        }
        .background(c.bg)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showBluetoothScan) {
            BluetoothScanSheet(vehicleId: vehicleId)
                .environmentObject(lang)
        }
    }

    // MARK: - Nav Row

    /// The app's own bar, not a local copy of one.
    ///
    /// This row was hand-built too: a bare chevron in a 34pt frame under a
    /// 16pt title. The vehicle card that opens this sheet is one tap away and
    /// now carries `CustomNavBar` — two bars that close together cannot
    /// disagree. The shared bar also brings the 44pt hit area the bare glyph
    /// never had.
    private func navRow(l: LanguageManager.Language) -> some View {
        CustomNavBar(title: AppStrings.autoRecord(l))
            // Presented as a sheet from the vehicle card, and this screen asks
            // for the drag indicator — so the bar has to clear the grabber
            // UIKit draws over its first 10pt.
            .environment(\.navBarInSheet, true)
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
            Text(AppStrings.autoStopRowLabel(l))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            stepperButton(
                systemImage: "minus",
                enabled: settings.autoStopTimeout > Self.timeoutRange.lowerBound,
                c: c
            ) {
                settings.autoStopTimeout = max(
                    Self.timeoutRange.lowerBound, settings.autoStopTimeout - 1
                )
            }
            Text(AppStrings.autoStopMinutes(l, minutes: settings.autoStopTimeout))
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(c.text)
                .frame(width: 54)
            stepperButton(
                systemImage: "plus",
                enabled: settings.autoStopTimeout < Self.timeoutRange.upperBound,
                c: c
            ) {
                settings.autoStopTimeout = min(
                    Self.timeoutRange.upperBound, settings.autoStopTimeout + 1
                )
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
