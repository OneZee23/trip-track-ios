import Foundation
import SwiftUI
import MapKit
import Combine
import QuartzCore

/// Менеджер плавной анимации трека
class SmoothTrackManager: ObservableObject {
    // Подтверждённые точки трека
    @Published private(set) var confirmedPoints: [CLLocationCoordinate2D] = [] {
        didSet {
            cachedSmoothedPrefix = nil // invalidate cache when confirmed points change
            updateSmoothPoints()
        }
    }

    // Анимированная "голова" линии
    @Published private(set) var animatedHeadPosition: CLLocationCoordinate2D?

    // Сглаженные точки для отображения (публичное для SwiftUI)
    @Published private(set) var smoothDisplayPoints: [CLLocationCoordinate2D] = []

    /// Last N confirmed points + animated head — for the glowing head overlay
    @Published private(set) var headSegmentPoints: [CLLocationCoordinate2D] = []

    // Cache for smoothed confirmed points (invalidated only when confirmedPoints change)
    private var cachedSmoothedPrefix: [CLLocationCoordinate2D]?

    // Обновление сглаженных точек — uses cached prefix + recomputes only the tail
    private func updateSmoothPoints() {
        let confirmed = confirmedPoints
        guard confirmed.count >= 2 else {
            smoothDisplayPoints = confirmed
            if let head = animatedHeadPosition {
                smoothDisplayPoints.append(head)
            }
            updateHeadSegment()
            return
        }

        // Cache the smoothed prefix (all confirmed points except last 2)
        if cachedSmoothedPrefix == nil && confirmed.count > 3 {
            let prefixPoints = Array(confirmed.dropLast(2))
            cachedSmoothedPrefix = PathSmoother.smooth(points: prefixPoints, segmentsPerPoint: 5)
        }

        // Only smooth the tail (last 3 confirmed + animated head)
        let tailStart = max(0, confirmed.count - 3)
        var tailPoints = Array(confirmed[tailStart...])
        if let head = animatedHeadPosition {
            tailPoints.append(head)
        }
        let smoothedTail = tailPoints.count >= 2
            ? PathSmoother.smooth(points: tailPoints, segmentsPerPoint: 5)
            : tailPoints

        if let prefix = cachedSmoothedPrefix {
            smoothDisplayPoints = prefix + smoothedTail
        } else {
            // Few points — smooth everything
            var allPoints = confirmed
            if let head = animatedHeadPosition {
                allPoints.append(head)
            }
            smoothDisplayPoints = PathSmoother.smooth(points: allPoints, segmentsPerPoint: 5)
        }

        updateHeadSegment()
    }

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
        smoothDisplayPoints = []
        headSegmentPoints = []
        cachedSmoothedPrefix = nil
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
        updateSmoothPoints()

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
