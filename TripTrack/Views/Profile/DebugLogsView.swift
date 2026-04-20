import SwiftUI

struct DebugLogsView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var showWarning = true
    @State private var errorMessage: String?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    hero(c, isRu: isRu)

                    warningCard(c, isRu: isRu)

                    exportCard(c, isRu: isRu)

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(c.bg)
            .navigationTitle(isRu ? "Логи" : "Debug logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isRu ? "Готово" : "Done") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private func hero(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text(isRu ? "Отправить логи разработчику" : "Send debug logs")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
            Text(isRu
                 ? "Поможет быстрее разобраться с проблемой"
                 : "Helps us investigate issues faster")
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func warningCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.yellow)
                .frame(width: 24, alignment: .center)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            VStack(alignment: .leading, spacing: 6) {
                Text(isRu ? "Важно" : "Important")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Text(isRu
                     ? "В логах могут быть Ваши данные: даты поездок, регионы, тип устройства, версия приложения. Делитесь логами с разработчиком или третьими лицами на свой страх и риск."
                     : "Logs may include your data: trip dates, regions, device type, app version. Share with the developer or third parties at your own risk.")
                    .font(.system(size: 13))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }

    private func exportCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 10) {
            if let url = exportURL {
                ShareLink(item: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text(isRu ? "Поделиться файлом" : "Share file")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.accent))
                }

                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)

                Button {
                    Task { await generate() }
                } label: {
                    Text(isRu ? "Собрать заново" : "Regenerate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
            } else {
                Button {
                    Task { await generate() }
                } label: {
                    HStack(spacing: 8) {
                        if isExporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "doc.text.fill")
                        }
                        Text(isExporting
                             ? (isRu ? "Собираю…" : "Collecting…")
                             : (isRu ? "Собрать логи за 48ч" : "Collect last 48h logs"))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.accent))
                }
                .disabled(isExporting)
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }

    // MARK: - Export

    private func generate() async {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }
        do {
            let url = try await DebugLogExporter.exportRecentLogs()
            exportURL = url
        } catch {
            errorMessage = "\(error.localizedDescription)"
        }
    }
}
