import SwiftUI
import OSLog

/// «Журнал» (Figma 6.1.0 frame 3) — on-screen log journal + export CTA.
/// Entry point unchanged: the ProfileView «Отправить логи» dev row presents
/// this as a sheet (the journal is not drawn on the account frame — it stays
/// a hidden/dev surface).
struct DebugLogsView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// nil = still reading OSLogStore (slow) — show the loader.
    @State private var entries: [DebugLogExporter.LogEntryRow]?
    @State private var loadFailed = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(c: c, l: l)
            ScrollView {
                VStack(spacing: 16) {
                    journalCard(c: c, l: l)

                    ctaBlock(c: c, l: l)

                    if let err = errorMessage {
                        Text(err)
                            .font(.inter(13))
                            .foregroundStyle(AppTheme.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("logs_screen")
        .task {
            // OSLogStore reads are slow — loaded off the main actor by the
            // async exporter helper while PixelCarLoader spins.
            do {
                // Figma frame 3 draws newest-first; the exporter returns
                // oldest-first (export-file order).
                entries = Array(try await DebugLogExporter.recentEntries().reversed())
            } catch {
                // A diagnostics screen must not claim "no entries" when the
                // store READ failed — that misleads the bug-report flow.
                entries = []
                loadFailed = true
            }
        }
    }

    // MARK: - Nav row

    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack {
            // Sheet root — chevron acts as close (GarageView precedent).
            GarageCircleNavButton(systemImage: "chevron.left") { dismiss() }
            Spacer()
            Text(AppStrings.logsJournalTitle(l))
                .font(.inter(16, weight: .bold))
                .foregroundStyle(c.text)
            Spacer()
            GarageCircleNavButton(systemImage: "square.and.arrow.up") {
                Task { await generate() }
            }
            .disabled(isExporting)
            .accessibilityIdentifier("logs_export_nav")
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
        .padding(.horizontal, 14)
    }

    // MARK: - Journal card

    @ViewBuilder
    private func journalCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if let entries {
            if entries.isEmpty {
                Text(loadFailed ? AppStrings.logsLoadFailed(l) : AppStrings.logsEmpty(l))
                    .font(.inter(13))
                    .foregroundStyle(loadFailed ? AppTheme.red : c.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else {
                // >20 rows (capped at 100) → LazyVStack per project rule.
                LazyVStack(spacing: 0) {
                    ForEach(entries) { row in
                        journalRow(row, c: c)
                        if row.id != entries.last?.id {
                            Rectangle()
                                .fill(c.border)
                                .frame(height: 1)
                        }
                    }
                }
                .padding(12)
                .surfaceCard(cornerRadius: 16)
            }
        } else {
            PixelCarLoader(label: nil, height: 100)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    private func journalRow(_ row: DebugLogExporter.LogEntryRow, c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: row.date))
                .font(.inter(11, weight: .medium).monospacedDigit())
                .foregroundStyle(c.textTertiary)

            Circle()
                .fill(severityColor(row.level, c: c))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            Text("\(row.category): \(row.message)")
                .font(.inter(11.5))
                .foregroundStyle(c.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("logs_row")
    }

    /// F9: Figma draws only green/yellow dots; the mapping keeps the app
    /// palette — green = debug/info/notice, yellow = error, red = fault
    /// (invented but palette-consistent).
    private func severityColor(_ level: OSLogEntryLog.Level, c: AppTheme.Colors) -> Color {
        switch level {
        case .debug, .info, .notice: return AppTheme.green
        case .error:                 return AppTheme.yellow
        case .fault:                 return AppTheme.red
        default:                     return c.textTertiary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - CTA block

    private func ctaBlock(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 10) {
            if let url = exportURL {
                // File is ready — the CTA becomes the actual share action
                // (same two-stage flow as before the redesign).
                ShareLink(item: url) {
                    ctaLabel(text: AppStrings.logsShareFile(l))
                }
                .accessibilityIdentifier("logs_send_cta")

                Text(url.lastPathComponent)
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
            } else {
                Button {
                    Task { await generate() }
                } label: {
                    ctaLabel(text: AppStrings.logsSendCTA(l), showsProgress: isExporting)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
                .accessibilityIdentifier("logs_send_cta")
            }

            // F7: truthful caption — the export header embeds account_id and
            // entries may contain trip metadata, so no "no personal data"
            // claims; the user can inspect the file in the share preview.
            Text(AppStrings.logsPrivacyCaption(l))
                .font(.inter(12))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ctaLabel(text: String, showsProgress: Bool = false) -> some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(text)
                .font(.inter(14, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.accent))
        .shadow(color: AppTheme.accent.opacity(0.3), radius: 3, y: 1)
    }

    // MARK: - Export (existing flow kept)

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
