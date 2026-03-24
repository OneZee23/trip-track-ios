import SwiftUI

struct GPSIndicatorView: View {
    let accuracy: Double // meters
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var showTooltip = false
    @State private var autoDismissTask: DispatchWorkItem?

    private var isGood: Bool { accuracy <= 10 }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isGood ? AppTheme.green : AppTheme.accent)
                .frame(width: 7, height: 7)
                .modifier(GPSBlinkModifier())

            Text("±\(Int(accuracy))\(AppStrings.m(lang.language))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .glassPill()
        .onTapGesture {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showTooltip.toggle()
            }
            scheduleAutoDismiss()
        }
        .overlay(alignment: .top) {
            if showTooltip {
                tooltipCard
                    .offset(y: 44)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }

    private var tooltipCard: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(isGood ? AppTheme.green : AppTheme.accent)
                Text(AppStrings.gpsAccuracyTitle(lang.language))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showTooltip = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(c.cardAlt, in: Circle())
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(isGood ? AppTheme.green : AppTheme.accent)
                    .frame(width: 8, height: 8)
                Text("±\(Int(accuracy))\(AppStrings.m(lang.language))")
                    .font(.system(size: 20, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isGood ? AppTheme.green : AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                legendRow(color: AppTheme.green, label: isRu ? "≤10м — отличная" : "≤10m — excellent")
                legendRow(color: AppTheme.accent, label: isRu ? ">10м — средняя" : ">10m — moderate")
            }

            Text(isRu
                 ? "Влияет на точность записи маршрута. На открытой местности точность выше."
                 : "Affects route recording precision. Open areas provide better accuracy.")
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(c.card)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(c.border, lineWidth: 1)
        )
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        guard showTooltip else { return }
        let task = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) { showTooltip = false }
        }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.colors(for: scheme).textSecondary)
        }
    }
}

private struct GPSBlinkModifier: ViewModifier {
    @State private var blink = false

    func body(content: Content) -> some View {
        content
            .opacity(blink ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    blink = true
                }
            }
    }
}
