import SwiftUI
import OSLog

private let reportLog = Logger(subsystem: "com.triptrack", category: "social.report")

enum ReportTarget {
    case user(UUID)
    case trip(UUID)

    var type: String {
        switch self {
        case .user: return "user"
        case .trip: return "trip"
        }
    }
    var id: UUID {
        switch self {
        case .user(let id): return id
        case .trip(let id): return id
        }
    }
}

struct ReportSheet: View {
    let target: ReportTarget

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: ReportReason?
    @State private var notes: String = ""
    @State private var isSending = false
    @State private var submitted = false
    @State private var errorMessage: String?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if submitted {
                        successCard(c, isRu: isRu)
                            .padding(.top, 40)
                    } else {
                        intro(c, isRu: isRu)
                        reasonList(c, isRu: isRu)
                        notesField(c, isRu: isRu)
                        submitButton(c, isRu: isRu)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(16)
            }
            .background(c.bg)
            .navigationTitle(isRu ? "Пожаловаться" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
        }
    }

    // MARK: - Sections

    private func intro(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Text(isRu
             ? "Мы рассматриваем жалобы на недопустимый контент в течение 24 часов и можем удалить контент или заблокировать пользователя-нарушителя."
             : "We review reports of objectionable content within 24 hours and may remove content or suspend offending accounts.")
            .font(.system(size: 13))
            .foregroundStyle(c.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func reasonList(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(ReportReason.allCases) { reason in
                Button {
                    Haptics.selection()
                    selectedReason = reason
                } label: {
                    HStack {
                        Text(reason.label(lang.language))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(c.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: selectedReason == reason ? "circle.inset.filled" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(selectedReason == reason ? AppTheme.accent : c.textTertiary)
                    }
                    .padding(14)
                    .surfaceCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func notesField(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isRu ? "Комментарий (необязательно)" : "Additional details (optional)")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
            TextEditor(text: $notes)
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .padding(10)
                .surfaceCard(cornerRadius: 12)
        }
    }

    private func submitButton(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.action()
            Task { await submit() }
        } label: {
            ZStack {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Text(isRu ? "Отправить" : "Submit")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedReason == nil ? c.textTertiary.opacity(0.3) : AppTheme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(selectedReason == nil || isSending)
    }

    private func successCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(isRu ? "Жалоба отправлена" : "Report sent")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(c.text)
            Text(isRu
                 ? "Спасибо. Мы рассмотрим её в ближайшие 24 часа."
                 : "Thank you. We'll review it within 24 hours.")
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text(isRu ? "Готово" : "Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Submit

    private func submit() async {
        guard let selectedReason else { return }
        isSending = true
        defer { isSending = false }
        do {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let req = SocialReportRequest(
                targetType: target.type,
                targetId: target.id,
                reason: selectedReason.rawValue,
                notes: trimmedNotes.isEmpty ? nil : String(trimmedNotes.prefix(500))
            )
            let _: SocialReportResponse = try await APIClient.shared.post(
                APIEndpoint.socialReport, body: req)
            submitted = true
            Haptics.success()
        } catch let e as APIError {
            errorMessage = String(describing: e)
            reportLog.error("report failed: \(String(describing: e))")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
