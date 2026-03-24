import SwiftUI

/// Swipe-to-reveal delete button in iOS Notes style — rounded pill behind the card
struct SwipeToDeleteCard<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var revealed = false

    private let buttonWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button behind — rounded pill, vertically centered
            if offset < -5 {
                Button {
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.red, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.trailing, 4)
                .transition(.identity)
            }

            // Main content — slides left
            content()
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            guard h > v * 1.8 else { return }

                            let drag = value.translation.width
                            if revealed {
                                let newOffset = -buttonWidth + drag
                                offset = max(min(newOffset, 0), -buttonWidth - 20)
                            } else {
                                offset = min(max(drag, -buttonWidth - 20), 0)
                            }
                        }
                        .onEnded { value in
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)

                            guard h > v else {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    offset = revealed ? -buttonWidth : 0
                                }
                                return
                            }

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if revealed {
                                    if value.translation.width > 30 {
                                        offset = 0
                                        revealed = false
                                    } else {
                                        offset = -buttonWidth
                                    }
                                } else {
                                    if offset < -30 {
                                        offset = -buttonWidth
                                        revealed = true
                                    } else {
                                        offset = 0
                                    }
                                }
                            }
                        }
                )
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) {
            offset = 0
            revealed = false
        }
    }
}
