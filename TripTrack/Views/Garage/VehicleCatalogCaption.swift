import SwiftUI

struct VehicleCatalogCaption: View {
    let make: String
    let model: String
    let year: Int
    var bodyType: String = ""
    var modelID: String?
    var generationID: String?
    var variantID: String?
    var showsCapsule = false
    var foreground: Color? = nil

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var variant: CarCatalog.Variant?

    private var revision: String { [modelID, generationID, variantID].compactMap { $0 }.joined(separator: "/") }
    private var modelLine: String {
        let body =
            !showsCapsule || bodyType.isEmpty
            ? "" : AppStrings.avatarStyleName(lang.language, style: bodyType).lowercased(lang.language)
        let modelWithBody =
            !body.isEmpty && !model.localizedCaseInsensitiveContains(body)
            ? [model, body].joined(separator: " ") : model
        var parts = [[make, modelWithBody].filter { !$0.isEmpty }.joined(separator: " ")].filter { !$0.isEmpty }
        if year > 0 { parts.append(String(year)) }
        if !showsCapsule, let hp = variant?.powerHp {
            parts.append(AppStrings.garagePower(lang.language, value: String(hp)))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 10) {
            if !modelLine.isEmpty {
                Text(modelLine)
                    .font(.inter(showsCapsule ? 13 : 12))
                    .foregroundStyle(foreground ?? c.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if showsCapsule, let line = variant?.specLine(lang.language) {
                Text(line)
                    .font(.inter(12, weight: .semibold))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .task(id: revision) {
            variant = await CarCatalog.shared.resolve(
                modelID: modelID, generationID: generationID, variantID: variantID)
        }
    }
}
