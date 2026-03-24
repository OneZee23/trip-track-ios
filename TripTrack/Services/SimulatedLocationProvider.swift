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
    
    private var lastUpdateTime: Date?
    
    var locationPublisher: AnyPublisher<LocationUpdate, Never> {
        locationSubject.eraseToAnyPublisher()
    }
    
    /// Инициализация с начальной позицией (реальная GPS на момент старта)
    init(startingFrom initialLocation: CLLocationCoordinate2D) {
        self.simulatedCoordinate = initialLocation
        
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
        
        let deltaTime = now.timeIntervalSince(lastTime)
        lastUpdateTime = now
        
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
        if simulatedSpeed > 0.1 { // Минимальный порог движения
            let distance = simulatedSpeed * deltaTime
            let courseRadians = simulatedCourse * .pi / 180
            
            // Смещение в градусах (приблизительно)
            let latOffset = (distance * cos(courseRadians)) / 111_111
            let lonOffset = (distance * sin(courseRadians)) / (111_111 * cos(simulatedCoordinate.latitude * .pi / 180))
            
            simulatedCoordinate = CLLocationCoordinate2D(
                latitude: simulatedCoordinate.latitude + latOffset,
                longitude: simulatedCoordinate.longitude + lonOffset
            )
        }
        
        // Публикуем обновление
        let update = LocationUpdate(
            coordinate: simulatedCoordinate,
            speed: simulatedSpeed,
            course: simulatedCourse,
            altitude: 0,
            timestamp: now,
            horizontalAccuracy: 5 // Симуляция всегда "точная"
        )
        
        currentLocation = update
        locationSubject.send(update)
    }
}
