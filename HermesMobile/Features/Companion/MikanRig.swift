import SwiftUI

/// Every animatable pose value in one vector so SwiftUI can interpolate whole poses.
struct MikanRig: VectorArithmetic {
    enum Slot: Int {
        case headTilt, headDY, earDroop, earTwitch, eyeOpen, happyEyes, sadLid, look, faceDX
        case browThink, browSad, mouthOpen, mouthFrown, mouthHmm
        case lElbowX, lElbowY, lHandX, lHandY, rElbowX, rElbowY, rHandX, rHandY
        case tail, tailDroop, bodyRot, leftLift, rightLift, tear, leftArmOver, rightArmOver
        case browAngry, angryLid
        case laptop, lookY
    }

    private var v = SIMD64<Double>()

    subscript(_ slot: Slot) -> Double {
        get { v[slot.rawValue] }
        set { v[slot.rawValue] = newValue }
    }

    static var zero: MikanRig { MikanRig() }
    static func + (a: MikanRig, b: MikanRig) -> MikanRig { var r = a; r.v += b.v; return r }
    static func - (a: MikanRig, b: MikanRig) -> MikanRig { var r = a; r.v -= b.v; return r }
    mutating func scale(by rhs: Double) { v *= rhs }
    var magnitudeSquared: Double { (v * v).sum() }

    func point(_ x: Slot, _ y: Slot) -> CGPoint { CGPoint(x: self[x], y: self[y]) }

    private mutating func setArms(left: (CGPoint, CGPoint), right: (CGPoint, CGPoint)) {
        self[.lElbowX] = left.0.x; self[.lElbowY] = left.0.y
        self[.lHandX] = left.1.x; self[.lHandY] = left.1.y
        self[.rElbowX] = right.0.x; self[.rElbowY] = right.0.y
        self[.rHandX] = right.1.x; self[.rHandY] = right.1.y
    }

    /// The resting pose for a state. `.happy` points at the newest message, toward `pointing`.
    static func pose(for state: CompanionState, pointing: CompanionSide = .left) -> MikanRig {
        var r = MikanRig()
        r[.eyeOpen] = 1
        r.setArms(left: (CGPoint(x: 36, y: 62), CGPoint(x: 36, y: 70)),
                  right: (CGPoint(x: 64, y: 62), CGPoint(x: 64, y: 70)))
        switch state {
        case .idle:
            break
        case .thinking:
            r[.headTilt] = -8
            r[.look] = -1.4
            r[.browThink] = 1
            r[.mouthHmm] = 1
            r[.tail] = -8
            r.setArms(left: (CGPoint(x: 38, y: 64), CGPoint(x: 47, y: 47)),
                      right: (CGPoint(x: 63, y: 64), CGPoint(x: 56, y: 68)))
            r[.leftArmOver] = 1
        case .happy:
            // Leans and points up-left at the message that just finished; other paw on hip.
            r[.mouthOpen] = 1
            r[.headTilt] = -7
            r[.headDY] = -1
            r[.faceDX] = -2.5
            r[.look] = -1.6
            r[.bodyRot] = -3
            r[.tail] = -14
            r.setArms(left: (CGPoint(x: 32, y: 44), CGPoint(x: 22, y: 35)),
                      right: (CGPoint(x: 69, y: 60), CGPoint(x: 61, y: 68)))
            r[.leftArmOver] = 1
            if pointing == .right { r.mirror() }
        case .sad:
            r[.earDroop] = 55
            r[.sadLid] = 1
            r[.browSad] = 1
            r[.mouthFrown] = 1
            r[.headDY] = 2
            r[.headTilt] = 4
            r[.tailDroop] = 1
            r[.tear] = 1
            r.setArms(left: (CGPoint(x: 38, y: 64), CGPoint(x: 40, y: 72)),
                      right: (CGPoint(x: 62, y: 64), CGPoint(x: 60, y: 72)))
        case .working:
            // Standing at a cardboard box, both paws on the laptop keyboard, eyes on the screen.
            r[.laptop] = 1
            r[.lookY] = 1.2
            r[.mouthHmm] = 1
            r[.headDY] = 1.5
            r[.tail] = -6
            r.setArms(left: (CGPoint(x: 36, y: 60), CGPoint(x: 45, y: 64.5)),
                      right: (CGPoint(x: 64, y: 60), CGPoint(x: 55, y: 64.5)))
            r[.leftArmOver] = 1
            r[.rightArmOver] = 1
        case .annoyed:
            // Ears pinned, arms crossed, side-eye.
            r[.earDroop] = 32
            r[.angryLid] = 1
            r[.browAngry] = 1
            r[.mouthFrown] = 1
            r[.headTilt] = 5
            r[.faceDX] = 1.5
            r[.look] = 1.5
            r[.tail] = -20
            r.setArms(left: (CGPoint(x: 36, y: 64), CGPoint(x: 57, y: 61)),
                      right: (CGPoint(x: 64, y: 64), CGPoint(x: 43, y: 61)))
        }
        return r
    }

    mutating func applyFidget(for state: CompanionState) {
        switch state {
        case .idle:
            self[.earTwitch] = 12
            self[.tail] += 8
        case .thinking:
            self[.tail] += 14
            self[.look] -= 0.6
        case .sad:
            self[.tail] += 4
        case .annoyed:
            self[.tail] += 18
        case .working:
            self[.tail] += 12
        case .happy:
            break
        }
    }

    /// This pose mid-stride: face, lean, legs, arms, and tail take the walk; the expression stays.
    func walking(toward direction: CompanionSide, stride: Bool) -> MikanRig {
        var r = self
        let dir: Double = direction == .right ? 1 : -1
        let step: Double = stride ? 1 : -1
        r[.headTilt] = 0
        r[.faceDX] = 4 * dir
        r[.look] = 1.2 * dir
        r[.bodyRot] = 3 * step
        r[.tail] = -8 * step
        r[.tailDroop] = 0
        r[.leftLift] = max(0, step) * 4
        r[.rightLift] = max(0, -step) * 4
        let ls = CGPoint(x: 41, y: 52), rs = CGPoint(x: 59, y: 52)
        let lh = MikanGeometry.rotate(CGPoint(x: 36, y: 70), around: ls, degrees: 20 * step)
        let rh = MikanGeometry.rotate(CGPoint(x: 64, y: 70), around: rs, degrees: 20 * step)
        r.setArms(left: (MikanGeometry.mid(ls, lh), lh), right: (MikanGeometry.mid(rs, rh), rh))
        r[.leftArmOver] = 0
        r[.rightArmOver] = 0
        r[.laptop] = 0
        r[.lookY] = 0
        return r
    }

    /// Flips arms, face, and lean left-to-right around the body's center line (x = 50).
    private mutating func mirror() {
        let left = (point(.lElbowX, .lElbowY), point(.lHandX, .lHandY))
        let right = (point(.rElbowX, .rElbowY), point(.rHandX, .rHandY))
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: 100 - p.x, y: p.y) }
        setArms(left: (flip(right.0), flip(right.1)), right: (flip(left.0), flip(left.1)))
        let leftOver = self[.leftArmOver]
        self[.leftArmOver] = self[.rightArmOver]
        self[.rightArmOver] = leftOver
        for slot in [Slot.headTilt, .faceDX, .look, .bodyRot] {
            self[slot] = -self[slot]
        }
    }
}

/// Point math shared by the rig and the painter (unit space, y points down).
enum MikanGeometry {
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { lerp(a, b, 0.5) }

    static func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// Positive degrees rotate clockwise on screen (y points down).
    static func rotate(_ p: CGPoint, around c: CGPoint, degrees: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        let x = p.x - c.x, y = p.y - c.y
        return CGPoint(x: c.x + x * cos(a) - y * sin(a), y: c.y + x * sin(a) + y * cos(a))
    }

    /// Flat [x0, y0, x1, y1, ...] list to points.
    static func points(_ xy: [CGFloat]) -> [CGPoint] {
        stride(from: 0, to: xy.count, by: 2).map { CGPoint(x: xy[$0], y: xy[$0 + 1]) }
    }
}
