import SwiftUI

struct Drive2LinkSheet: View {
    let vehicle: Vehicle
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    @State private var text: String

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        _text = State(initialValue: vehicle.drive2URL ?? "")
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let parsed = Drive2Link(text)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppStrings.garageDrive2Title(l)).font(.inter(19, weight: .bold)).foregroundStyle(c.text)
                Spacer(minLength: 8)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(
                        c.textSecondary
                    ).frame(width: 44, height: 44).background(c.cardAlt, in: Circle())
                }
                .buttonStyle(PressableCardStyle()).accessibilityLabel(AppStrings.close(l))
            }
            Text(AppStrings.garageDrive2Help(l)).font(.inter(14)).foregroundStyle(c.textSecondary)
            HStack(spacing: 8) {
                TextField(AppStrings.garageDrive2Field(l), text: $text, axis: .vertical)
                    .font(.inter(14)).foregroundStyle(c.text).lineLimit(2...3)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("garage_drive2_field")
                PasteButton(payloadType: String.self) { if let value = $0.first { text = value } }
                    .tint(AppTheme.accent).labelStyle(.iconOnly)
            }
            .padding(12).background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
            Group {
                if let parsed {
                    Text(
                        AppStrings.garageDrive2Valid(l, make: parsed.make.capitalized, model: parsed.model.capitalized)
                    ).foregroundStyle(AppTheme.green)
                } else {
                    Text(AppStrings.garageDrive2Hint(l)).foregroundStyle(c.textSecondary)
                }
            }.font(.inter(12))
            Text(
                auth.isSignedIn && settings.cloudSyncEnabled
                    ? AppStrings.garageDrive2PublicNote(l) : AppStrings.garageDrive2LocalNote(l)
            )
            .font(.inter(12)).foregroundStyle(c.textTertiary)
            Button {
                guard let parsed else { return }
                settings.updateVehicleGarage(id: vehicle.id, drive2URL: parsed.url.absoluteString)
                Haptics.success()
                dismiss()
            } label: {
                Text(AppStrings.save(l)).font(.inter(16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(
                        AppTheme.accent.opacity(parsed == nil ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(PressableCardStyle()).disabled(parsed == nil)
            .accessibilityIdentifier("garage_drive2_save")
            if Drive2Link(vehicle.drive2URL ?? "") != nil {
                Button {
                    settings.updateVehicleGarage(id: vehicle.id, drive2URL: "")
                    Haptics.tap()
                    dismiss()
                } label: {
                    Text(AppStrings.garageDrive2Unlink(l)).font(.inter(14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent).frame(maxWidth: .infinity).frame(minHeight: 44)
                }.buttonStyle(PressableCardStyle())
            }
        }
        .padding(20)
        .contentSizedSheet(background: c.card)
    }
}
