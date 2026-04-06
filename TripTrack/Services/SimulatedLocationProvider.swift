import Foundation
import CoreLocation
import Combine
import QuartzCore

/// Провайдер симулированной позиции через джойстик
class SimulatedLocationProvider: LocationProviding {
    private let locationSubject = PassthroughSubject<LocationUpdate, Never>()
    private var displayLink: CADisplayLink?
    
    // Текущая симулированная позиция
    private(set) var currentLocation: LocationUpdate?
    
    // Состояние симуляции
    private var simulatedCoordinate: CLLocationCoordinate2D
    private var simulatedSpeed: CLLocationSpeed = 0
    private var simulatedCourse: CLLocationDirection = 0
    
    // Ввод с джойстика (от -1 до 1)
    var joystickInput: CGPoint = .zero {
        didSet {
            updateFromJoystick()
        }
    }
    
    // Настройки симуляции
    var maxSpeed: CLLocationSpeed = 16.67 // 60 км/ч в м/с
    var acceleration: CLLocationSpeed = 5.0 // м/с²
    var deceleration: CLLocationSpeed = 8.0 // м/с² (торможение быстрее)

    // Auto-route: движение по заданным точкам без джойстика
    let autoRoute: [CLLocationCoordinate2D]
    let autoRouteSpeed: CLLocationSpeed
    private var autoRouteIndex: Int = 0
    private var autoRouteProgress: Double = 0

    /// Demo route: Shibuya → Harajuku → Shinjuku (Tokyo)
    static let tokyoDemoRoute: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7004), // Shibuya crossing
        CLLocationCoordinate2D(latitude: 35.6604, longitude: 139.7009),
        CLLocationCoordinate2D(latitude: 35.6620, longitude: 139.7016),
        CLLocationCoordinate2D(latitude: 35.6640, longitude: 139.7020),
        CLLocationCoordinate2D(latitude: 35.6662, longitude: 139.7023), // Meiji-dori
        CLLocationCoordinate2D(latitude: 35.6685, longitude: 139.7030),
        CLLocationCoordinate2D(latitude: 35.6702, longitude: 139.7046), // Harajuku
        CLLocationCoordinate2D(latitude: 35.6718, longitude: 139.7062),
        CLLocationCoordinate2D(latitude: 35.6735, longitude: 139.7055),
        CLLocationCoordinate2D(latitude: 35.6755, longitude: 139.7040),
        CLLocationCoordinate2D(latitude: 35.6778, longitude: 139.7028),
        CLLocationCoordinate2D(latitude: 35.6800, longitude: 139.7015),
        CLLocationCoordinate2D(latitude: 35.6825, longitude: 139.7010),
        CLLocationCoordinate2D(latitude: 35.6850, longitude: 139.7003),
        CLLocationCoordinate2D(latitude: 35.6875, longitude: 139.6995),
        CLLocationCoordinate2D(latitude: 35.6900, longitude: 139.6985),
        CLLocationCoordinate2D(latitude: 35.6920, longitude: 139.6988), // Shinjuku Gyoen
        CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7003),
        CLLocationCoordinate2D(latitude: 35.6950, longitude: 139.7020),
        CLLocationCoordinate2D(latitude: 35.6958, longitude: 139.7035), // Shinjuku Station
    ]

    private var lastUpdateTime: Date?
    
    var locationPublisher: AnyPublisher<LocationUpdate, Never> {
        locationSubject.eraseToAnyPublisher()
    }
    
    /// Инициализация с начальной позицией и опциональным автомаршрутом
    init(startingFrom initialLocation: CLLocationCoordinate2D,
         autoRoute: [CLLocationCoordinate2D] = [],
         autoRouteSpeed: CLLocationSpeed = 11.0) {
        self.simulatedCoordinate = initialLocation
        self.autoRoute = autoRoute
        self.autoRouteSpeed = autoRouteSpeed
        
        // Создаём начальный LocationUpdate
        self.currentLocation = LocationUpdate(
            coordinate: initialLocation,
            speed: 0,
            course: 0,
            altitude: 0,
            timestamp: Date(),
            horizontalAccuracy: 5
        )
    }
    
    func start() {
        lastUpdateTime = Date()

        let proxy = DisplayLinkProxy { [weak self] in self?.tick() }
        displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit {
        displayLink?.invalidate()
    }
    
    private func updateFromJoystick() {
        // Джойстик определяет направление
        if joystickInput != .zero {
            // Вычисляем угол направления (0 = север, 90 = восток)
            let angle = atan2(Double(joystickInput.x), Double(joystickInput.y))
            simulatedCourse = angle * 180 / .pi
            if simulatedCourse < 0 {
                simulatedCourse += 360
            }
        }
    }
    
    private func tick() {
        let now = Date()
        guard let lastTime = lastUpdateTime else {
            lastUpdateTime = now
            return
        }

        let deltaTime = min(now.timeIntervalSince(lastTime), 0.1) // cap at 100ms to prevent teleporting after background
        lastUpdateTime = now

        if !autoRoute.isEmpty {
            tickAutoRoute(deltaTime: deltaTime, now: now)
        } else {
            tickJoystick(deltaTime: deltaTime, now: now)
        }
    }

    private func tickAutoRoute(deltaTime: Double, now: Date) {
        guard autoRoute.count >= 2 else { return }

        // Wrap index if at the end
        if autoRouteIndex >= autoRoute.count - 1 {
            autoRouteIndex = 0
            autoRouteProgress = 0
        }

        let from = autoRoute[autoRouteIndex]
        let to = autoRoute[autoRouteIndex + 1]

        // Distance between waypoints
        let segLat = to.latitude - from.latitude
        let segLon = to.longitude - from.longitude
        let segDistMeters = sqrt(
            pow(segLat * 111_320, 2) +
            pow(segLon * 111_320 * cos(from.latitude * .pi / 180), 2)
        )

        // How much progress per tick
        let metersThisTick = autoRouteSpeed * deltaTime
        let progressThisTick = segDistMeters > 0 ? metersThisTick / segDistMeters : 1.0
        autoRouteProgress += progressThisTick

        // Advance to next segment(s) if needed
        while autoRouteProgress >= 1.0 && autoRoute.count >= 2 {
            autoRouteProgress -= 1.0
            autoRouteIndex += 1
            if autoRouteIndex >= autoRoute.count - 1 {
                autoRouteIndex = 0
                autoRouteProgress = 0
            }
        }

        // Interpolate position
        let currentFrom = autoRoute[autoRouteIndex]
        let currentTo = autoRoute[autoRouteIndex + 1]
        let t = autoRouteProgress

        simulatedCoordinate = CLLocationCoordinate2D(
            latitude: currentFrom.latitude + (currentTo.latitude - currentFrom.latitude) * t,
            longitude: currentFrom.longitude + (currentTo.longitude - currentFrom.longitude) * t
        )

        // Course
        let dLon = currentTo.longitude - currentFrom.longitude
        let dLat = currentTo.latitude - currentFrom.latitude
        simulatedCourse = atan2(dLon, dLat) * 180 / .pi
        if simulatedCourse < 0 { simulatedCourse += 360 }

        simulatedSpeed = autoRouteSpeed

        let update = LocationUpdate(
            coordinate: simulatedCoordinate,
            speed: simulatedSpeed,
            course: simulatedCourse,
            altitude: 35,
            timestamp: now,
            horizontalAccuracy: 5
        )
        currentLocation = update
        locationSubject.send(update)
    }

    private func tickJoystick(deltaTime: Double, now: Date) {
        // Magnitude джойстика определяет целевую скорость
        let joystickMagnitude = min(1.0, sqrt(
            Double(joystickInput.x * joystickInput.x) +
            Double(joystickInput.y * joystickInput.y)
        ))

        let targetSpeed = maxSpeed * joystickMagnitude

        // Плавное изменение скорости (ускорение/торможение)
        if targetSpeed > simulatedSpeed {
            simulatedSpeed = min(targetSpeed, simulatedSpeed + acceleration * deltaTime)
        } else {
            simulatedSpeed = max(targetSpeed, simulatedSpeed - deceleration * deltaTime)
        }

        // Перемещение позиции
        if simulatedSpeed > 0.1 {
            let distance = simulatedSpeed * deltaTime
            let courseRadians = simulatedCourse * .pi / 180

            let latOffset = (distance * cos(courseRadians)) / 111_320
            let lonOffset = (distance * sin(courseRadians)) / (111_320 * cos(simulatedCoordinate.latitude * .pi / 180))

            simulatedCoordinate = CLLocationCoordinate2D(
                latitude: simulatedCoordinate.latitude + latOffset,
                longitude: simulatedCoordinate.longitude + lonOffset
            )
        }

        let update = LocationUpdate(
            coordinate: simulatedCoordinate,
            speed: simulatedSpeed,
            course: simulatedCourse,
            altitude: 0,
            timestamp: now,
            horizontalAccuracy: 5
        )
        currentLocation = update
        locationSubject.send(update)
    }
}
