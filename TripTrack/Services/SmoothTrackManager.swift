import Foundation
import SwiftUI
import MapKit
import Combine
import QuartzCore

/// Менеджер плавной анимации трека
class SmoothTrackManager: ObservableObject {
    // Подтверждённые точки трека
    @Published private(set) var confirmedPoints: [CLLocationCoordinate2D] = [] {
        didSet { updateHeadSegment() }
    }

    // Анимированная "голова" линии
    @Published private(set) var animatedHeadPosition: CLLocationCoordinate2D?

    /// Last N confirmed points + animated head — for the glowing head overlay
    @Published private(set) var headSegmentPoints: [CLLocationCoordinate2D] = []

    /// Хвост трека. Только он и рисуется — линия целиком идёт мимо, прямо из
    /// `confirmedPoints`, и сглаживания не просит.
    ///
    /// Здесь раньше жила вторая, сглаженная копия всего трека. Её пересчитывал
    /// и переопубликовывал каждый кадр `animationTick`, то есть до шестидесяти
    /// раз в секунду, и на каждом кадре копировался ВЕСЬ трек, помноженный на
    /// пять точек сглаживания: на третьем часу записи это под мегабайт на кадр,
    /// десятки мегабайт в секунду — на экране, который открыт всю поездку.
    /// Читала эту копию одна строка в отладочном меню.
    ///
    /// Убрано в 0.6.5 не за компанию: версия и так поднимает частоту точек, а
    /// цена этого места росла вместе с длиной поездки — то есть больнее всего
    /// било по самым долгим.
    private func updateHeadSegment() {
        let tailCount = min(5, confirmedPoints.count)
        var head = Array(confirmedPoints.suffix(tailCount))
        if let animHead = animatedHeadPosition {
            head.append(animHead)
        }
        headSegmentPoints = head
    }

    // Анимация
    private var displayLink: CADisplayLink?
    private var targetPosition: CLLocationCoordinate2D?
    private var animationStartPosition: CLLocationCoordinate2D?
    private var animationStartTime: Date?
    private let animationDuration: TimeInterval = 0.15

    func startAnimation() {
        let proxy = DisplayLinkProxy { [weak self] in self?.animationTick() }
        displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit {
        displayLink?.invalidate()
    }

    func reset() {
        confirmedPoints = []
        animatedHeadPosition = nil
        targetPosition = nil
        headSegmentPoints = []
    }

    /// Добавить новую точку (вызывается при обновлении позиции)
    func addPoint(_ coordinate: CLLocationCoordinate2D) {
        // Если это первая точка
        if confirmedPoints.isEmpty {
            confirmedPoints.append(coordinate)
            animatedHeadPosition = coordinate
            return
        }

        // Подтверждаем предыдущую анимированную позицию
        if let currentHead = animatedHeadPosition, let lastConfirmed = confirmedPoints.last {
            let distanceFromLast = distance(from: lastConfirmed, to: currentHead)
            if distanceFromLast > 1 { // > 1 метра
                confirmedPoints.append(currentHead)
            }
        }

        // Начинаем анимацию к новой точке
        animationStartPosition = animatedHeadPosition ?? coordinate
        targetPosition = coordinate
        animationStartTime = Date()
    }

    private func animationTick() {
        guard let target = targetPosition,
              let startPos = animationStartPosition,
              let startTime = animationStartTime else {
            return
        }

        let elapsed = -startTime.timeIntervalSinceNow
        let progress = min(elapsed / animationDuration, 1.0)
        let easedProgress = easeOutQuad(progress)

        let newLat = startPos.latitude + (target.latitude - startPos.latitude) * easedProgress
        let newLon = startPos.longitude + (target.longitude - startPos.longitude) * easedProgress

        // Skip publish if position barely changed (< ~0.1m)
        if let current = animatedHeadPosition,
           abs(current.latitude - newLat) < 0.000001,
           abs(current.longitude - newLon) < 0.000001 {
            if progress >= 1.0 { animationStartTime = nil }
            return
        }

        animatedHeadPosition = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
        updateHeadSegment()

        if progress >= 1.0 {
            animationStartTime = nil
        }
    }

    private func easeOutQuad(_ t: Double) -> Double {
        1 - (1 - t) * (1 - t)
    }

    private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2)
    }
}

// MARK: - Weak proxy for CADisplayLink to avoid retain cycles

final class DisplayLinkProxy {
    private let callback: () -> Void

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    @objc func tick() {
        callback()
    }
}
