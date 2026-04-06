import SwiftUI

struct SlideToStartView: View {
    let onStartTrip: () -> Void
    @EnvironmentObject private var lang: LanguageManager

    @State private var dragOffset: CGFloat = 0

    private let thumbSize: CGFloat = 48
    private let trackHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 16
    private let threshold: CGFloat = 0.85

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - thumbSize - 8  // 4pt padding each side
            let progress = min(dragOffset / maxOffset, 1.0)

            ZStack {
                // Track background
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppTheme.accent.opacity(0.15))

                // Shimmer hint text
                Text(AppStrings.slideToStart(lang.language))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4 * (1 - progress)))

                // Thumb
                HStack {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: AppTheme.accent.opacity(0.4), radius: 8)
                        .offset(x: dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = max(0, min(value.translation.width, maxOffset))
                                }
                                .onEnded { _ in
                                    if progress >= threshold {
                                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                        dragOffset = 0
                                        onStartTrip()
                                    } else {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            dragOffset = 0
                                        }
                                    }
                                }
                        )

                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(height: trackHeight)
    }
}
