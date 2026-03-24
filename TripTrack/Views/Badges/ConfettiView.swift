import SwiftUI

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var startTime: Date = .now

    static let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink,
        AppTheme.accent, AppTheme.teal
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startTime)

            Canvas { context, size in
                for particle in particles {
                    let age = elapsed - particle.delay
                    guard age > 0 else { continue }

                    let progress = age / particle.lifetime
                    guard progress < 1.0 else { continue }

                    // Position
                    let x = particle.startX * size.width + particle.driftX * CGFloat(age)
                    let gravity: CGFloat = 400
                    let y = -20 + particle.speedY * CGFloat(age) + 0.5 * gravity * CGFloat(age * age)

                    guard y < size.height + 20 else { continue }

                    // Opacity: fade out in last 30%
                    let opacity = progress > 0.7 ? (1.0 - progress) / 0.3 : 1.0

                    // Rotation
                    let angle = Angle.degrees(particle.rotation + particle.rotationSpeed * age)

                    let rect = CGRect(
                        x: x - particle.width / 2,
                        y: y - particle.height / 2,
                        width: particle.width,
                        height: particle.height
                    )

                    context.opacity = opacity
                    context.fill(
                        Path(rect).rotation(angle, anchor: UnitPoint(x: 0.5, y: 0.5)).path(in: rect),
                        with: .color(particle.color)
                    )
                }
            }
        }
        .onAppear {
            startTime = .now
            particles = (0..<45).map { _ in ConfettiParticle.random() }
        }
        .allowsHitTesting(false)
    }
}

private struct ConfettiParticle {
    let startX: CGFloat       // 0...1 fraction of width
    let speedY: CGFloat       // initial downward speed
    let driftX: CGFloat       // horizontal drift
    let width: CGFloat
    let height: CGFloat
    let color: Color
    let rotation: Double
    let rotationSpeed: Double
    let delay: Double
    let lifetime: Double

    static func random() -> ConfettiParticle {
        ConfettiParticle(
            startX: CGFloat.random(in: 0.05...0.95),
            speedY: CGFloat.random(in: 80...200),
            driftX: CGFloat.random(in: -60...60),
            width: CGFloat.random(in: 6...12),
            height: CGFloat.random(in: 4...8),
            color: ConfettiView.colors.randomElement() ?? .orange,
            rotation: Double.random(in: 0...360),
            rotationSpeed: Double.random(in: 100...400),
            delay: Double.random(in: 0...0.5),
            lifetime: Double.random(in: 2.5...4.0)
        )
    }
}
