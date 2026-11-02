// MARK: - Wire Format

enum Wire {
    static let floatsPerInstance = 16      // 4 x float4
    static let bytesPerInstance = 64       // 16-byte aligned, no implicit padding
}

enum Kind: Float {
    case toast = 0
    case toaster = 1
    case star = 3
}

/// The whole flock drifts on one shared vector, all objects banked at one angle,
/// exactly like the original screensaver: parallel, down and to the left.
enum Flight {
    static let direction = SIMD2<Float>(-0.87, -0.49)
    static let tilt: Float = 0.25
}

// MARK: - Simulation Types

struct Toast {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var size: Float
    var color: SIMD3<Float>

    mutating func advance(dt: Float) {
        position += velocity * dt
        if position.x < -1.7 || position.y < -1.7 {
            respawn()
        }
    }

    mutating func respawn() {
        enterFromUpRight(&position)
        velocity = Flight.direction * Float.random(in: 0.30...0.42)
        size = Float.random(in: 0.045...0.075)
        color = SIMD3(1, 1, 1)
    }
}

struct FlyingToaster {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var size: Float
    var phase: Float
    var flapSpeed: Float

    mutating func advance(dt: Float) {
        position += velocity * dt
        if position.x < -1.7 || position.y < -1.7 {
            respawn()
        }
    }

    mutating func respawn() {
        enterFromUpRight(&position)
        velocity = Flight.direction * Float.random(in: 0.26...0.36)
        // The sprite contains the body *and* both wings, so the quad is a little
        // larger than the toaster it draws.
        size = Float.random(in: 0.088...0.118)
        phase = Float.random(in: 0...(Float.pi * 2))
        flapSpeed = Float.random(in: 3.0...5.0)
    }
}

struct Star {
    var position: SIMD2<Float>
    var size: Float
    var brightness: Float
    var phase: Float
    var speed: Float
}

/// Places a recycled object just off the top or right edge so the flow stays even.
func enterFromUpRight(_ position: inout SIMD2<Float>) {
    if Float.random(in: 0..<1) < 0.5 {
        position = SIMD2(Float.random(in: -1.5...1.7), 1.40)
    } else {
        position = SIMD2(1.55, Float.random(in: -1.6...1.4))
    }
}

