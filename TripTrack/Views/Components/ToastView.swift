import SwiftUI

// MARK: - Toast Data Model

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let message: String
    var undoLabel: String = "Undo"
    var undoAction: (() -> Void)?

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }

    enum ToastType {
        case success
        case error
        case info
        case undo

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .undo: return "arrow.uturn.backward.circle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .success: return AppTheme.green
            case .error: return AppTheme.red
            case .info: return AppTheme.blue
            case .undo: return AppTheme.accent
            }
        }

        var autoDismissDelay: TimeInterval {
            switch self {
            case .undo: return 3.5
            default: return 2.5
            }
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let item: ToastItem
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(spacing: 10) {
            Image(systemName: item.type.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.type.iconColor)

            Text(item.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.text)
                .lineLimit(1)

            if item.type == .undo, item.undoAction != nil {
                Spacer(minLength: 4)
                Button {
                    Haptics.action()
                    item.undoAction?()
                    onDismiss()
                } label: {
                    Text(item.undoLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(c.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var item: ToastItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = item {
                    ToastView(item: toast, onDismiss: { dismiss() })
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(999)
                        .padding(.top, 8)
                        .task(id: toast.id) {
                            try? await Task.sleep(for: .seconds(toast.type.autoDismissDelay))
                            dismiss()
                        }
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onEnded { value in
                                    if value.translation.height < -10 {
                                        dismiss()
                                    }
                                }
                        )
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: item?.id)
    }

    private func dismiss() {
        item = nil
    }
}

extension View {
    func toast(item: Binding<ToastItem?>) -> some View {
        modifier(ToastModifier(item: item))
    }
}
