import SwiftUI
import Observation
import UIKit

/// Window measurements sampled after UIKit layout. Reading UIWindow from a
/// SwiftUI body can re-enter its layout graph during navigation; consumers
/// read this observable value instead, including inside static chrome helpers.
@Observable
final class WindowLayoutMetrics {
    static let shared = WindowLayoutMetrics()
    private(set) var safeAreaInsets: UIEdgeInsets?
    private(set) var size: CGSize?

    func update(insets: UIEdgeInsets, size: CGSize) {
        if safeAreaInsets != insets { safeAreaInsets = insets }
        if self.size != size { self.size = size }
    }
}

/// Mounted once on the app container. Reads from the actual containing
/// window, so rotation, home-button phones and sheets keep their real insets.
struct WindowLayoutReader: UIViewRepresentable {
    func makeUIView(context: Context) -> ReaderView { ReaderView() }
    func updateUIView(_ uiView: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        private var updatePending = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleMeasurement()
        }
        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            scheduleMeasurement()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleMeasurement()
        }
        private func scheduleMeasurement() {
            guard !updatePending else { return }
            updatePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updatePending = false
                guard let window = self.window else { return }
                WindowLayoutMetrics.shared.update(insets: window.safeAreaInsets, size: window.bounds.size)
            }
        }
    }
}
