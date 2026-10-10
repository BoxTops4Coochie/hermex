import SwiftUI

struct MikanFigure: View, Animatable {
    var rig: MikanRig
    var ink: Color

    var animatableData: MikanRig {
        get { rig }
        set { rig = newValue }
    }

    var body: some View {
        Canvas { context, size in
            MikanPainter(rig: rig, ink: ink).draw(in: context, size: size)
        }
    }
}

enum MikanPalette {
    static let fur = Color(hex: 0xF59A3E)
    static let shade = Color(hex: 0xDE7C2C)
    static let stripe = Color(hex: 0xC9621F)
    static let cream = Color(hex: 0xFFF1DC)
    static let pink = Color(hex: 0xF6A2AA)
    static let iris = Color(hex: 0xF6B940)
    static let irisTop = Color(hex: 0xE89A1E)
    static let pupil = Color(hex: 0x2A1A12)
    static let mouth = Color(hex: 0xB23A48)
    static let tongue = Color(hex: 0xF58C98)
    static let tear = Color(hex: 0x8FD0FF)
    static let blush = Color(hex: 0xFF8E9A)
    static let inkDark = Color(hex: 0x24150E)
    static let inkLight = Color(hex: 0x7A4524)
}

private struct MikanPainter {
    let rig: MikanRig
    let ink: Color

    private let baseline: CGFloat = 106
    private let o: CGFloat = 1.3

    func draw(in context: GraphicsContext, size: CGSize) {
        var ctx = context
        let s = min(size.width / 100, size.height / 110)
        ctx.translateBy(x: (size.width - 100 * s) / 2, y: size.height - 110 * s)
        ctx.scaleBy(x: s, y: s)
        ctx.rotate(around: CGPoint(x: 50, y: baseline), degrees: rig[.bodyRot])

        drawTail(ctx)
        drawLegs(ctx)
        drawBody(ctx)
        drawArms(ctx, over: false)
        drawHead(ctx)
        drawArms(ctx, over: true)
    }

    // MARK: Parts

    private func drawTail(_ ctx: GraphicsContext) {
        let up = MikanGeometry.points([61, 84, 80, 88, 86, 66, 76, 56, 72, 51, 76, 46, 80, 48])
        let down = MikanGeometry.points([60, 88, 66, 94, 72, 99, 78, 101, 84, 103, 90, 103, 94, 102])
        let t = CGFloat(rig[.tailDroop])
        let p = zip(up, down).map { MikanGeometry.lerp($0, $1, t) }
        var path = Path()
        path.move(to: p[0])
        path.addCurve(to: p[3], control1: p[1], control2: p[2])
        path.addCurve(to: p[6], control1: p[4], control2: p[5])
        var c = ctx
        c.rotate(around: CGPoint(x: 61, y: 84), degrees: rig[.tail])
        outlined(c, path, width: 6.4, color: MikanPalette.fur, dash: [3, 4.2])
    }

    private func drawLegs(_ ctx: GraphicsContext) {
        for (x, lift) in [(44.5, rig[.leftLift]), (55.5, rig[.rightLift])] {
            var leg = Path()
            leg.move(to: CGPoint(x: x, y: 80))
            leg.addLine(to: CGPoint(x: x, y: baseline - o - 3 - lift))
            outlined(ctx, leg, width: 7.5, color: MikanPalette.fur, dash: [2, 3.5])
            let foot = ellipse(x + rig[.faceDX] * 0.45, baseline - o - 3.4 - lift, 5.8, 3.4)
            fillOutlined(ctx, foot, MikanPalette.cream)
        }
    }

    private func drawBody(_ ctx: GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 42, y: 45))
        body.addCurve(to: CGPoint(x: 38, y: 80), control1: CGPoint(x: 37, y: 54), control2: CGPoint(x: 35, y: 70))
        body.addQuadCurve(to: CGPoint(x: 50, y: 86), control: CGPoint(x: 40, y: 86))
        body.addQuadCurve(to: CGPoint(x: 62, y: 80), control: CGPoint(x: 60, y: 86))
        body.addCurve(to: CGPoint(x: 58, y: 45), control1: CGPoint(x: 65, y: 70), control2: CGPoint(x: 63, y: 54))
        body.closeSubpath()
        ctx.fill(body, with: .color(MikanPalette.fur))

        var inner = ctx
        inner.clip(to: body)
        inner.fill(ellipse(64, 70, 8, 22), with: .color(MikanPalette.shade))
        var bib = Path()
        bib.move(to: CGPoint(x: 42, y: 46))
        bib.addQuadCurve(to: CGPoint(x: 58, y: 46), control: CGPoint(x: 50, y: 52))
        bib.addLine(to: CGPoint(x: 57, y: 60))
        bib.addQuadCurve(to: CGPoint(x: 56, y: 70), control: CGPoint(x: 54, y: 64))
        bib.addQuadCurve(to: CGPoint(x: 44, y: 70), control: CGPoint(x: 50, y: 82))
        bib.addQuadCurve(to: CGPoint(x: 43, y: 60), control: CGPoint(x: 46, y: 64))
        bib.closeSubpath()
        inner.fill(bib, with: .color(MikanPalette.cream))

        ctx.stroke(body, with: .color(ink), style: StrokeStyle(lineWidth: 2 * o, lineJoin: .round))
    }

    private func drawArms(_ ctx: GraphicsContext, over: Bool) {
        let arms: [(CGPoint, CGPoint, CGPoint, Bool)] = [
            (CGPoint(x: 41, y: 52), rig.point(.lElbowX, .lElbowY), rig.point(.lHandX, .lHandY), rig[.leftArmOver] > 0.5),
            (CGPoint(x: 59, y: 52), rig.point(.rElbowX, .rElbowY), rig.point(.rHandX, .rHandY), rig[.rightArmOver] > 0.5),
        ]
        for (shoulder, elbow, hand, isOver) in arms where isOver == over {
            var arm = Path()
            arm.move(to: shoulder)
            arm.addQuadCurve(to: hand, control: elbow)
            outlined(ctx, arm, width: 5.8, color: MikanPalette.fur, dash: [1.8, 3.2])
            ctx.fill(ellipse(hand.x, hand.y, 2.9, 2.9), with: .color(MikanPalette.cream))
        }
    }

    private func drawHead(_ context: GraphicsContext) {
        let hx = 50 + rig[.faceDX] * 0.3
        let hy = 28 + rig[.headDY]
        let fx = hx + rig[.faceDX]
        var ctx = context
        ctx.rotate(around: CGPoint(x: hx, y: hy + 18), degrees: rig[.headTilt])

        let left = ear(side: -1, hx: hx, hy: hy)
        let right = ear(side: 1, hx: hx, hy: hy)
        let head = headPath(hx: hx, hy: hy, left: left, right: right)
        ctx.fill(head, with: .color(MikanPalette.fur))
        ctx.stroke(head, with: .color(ink), style: StrokeStyle(lineWidth: 2 * o, lineJoin: .round))
        for tri in [left.inner, right.inner] {
            let p = polygon(tri)
            ctx.fill(p, with: .color(MikanPalette.pink))
            ctx.stroke(p, with: .color(MikanPalette.pink), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }

        var inner = ctx
        inner.clip(to: head)
        inner.fill(ellipse(hx + 14, hy + 12, 10, 9), with: .color(MikanPalette.shade))
        inner.fill(ellipse(fx, hy + 13, 8.5, 6), with: .color(MikanPalette.cream))
        for dx in [-3.6, 0, 3.6] {
            inner.fill(polygon([CGPoint(x: hx + dx - 1.2, y: hy - 16), CGPoint(x: hx + dx + 1.2, y: hy - 16),
                                CGPoint(x: hx + dx * 1.1, y: hy - 9.5)]), with: .color(MikanPalette.stripe))
        }
        for side in [-1.0, 1.0] {
            for dy in [2.0, 6.0] {
                inner.fill(polygon([CGPoint(x: hx + side * 21, y: hy + dy - 1), CGPoint(x: hx + side * 21, y: hy + dy + 1),
                                    CGPoint(x: hx + side * 15, y: hy + dy + 0.4)]), with: .color(MikanPalette.stripe))
            }
        }

        let ey = hy + 3.5
        for side in [-1.0, 1.0] {
            let ex = fx + side * 7.6
            var blush = ctx
            blush.opacity = 0.4
            blush.fill(ellipse(ex + side * 3, hy + 11, 3, 1.6), with: .color(MikanPalette.blush))
            drawEye(ctx, ex: ex, ey: ey, side: side)
            drawBrows(ctx, ex: ex, by: ey - 7.5, side: side)
        }

        let nose = polygon([CGPoint(x: fx - 1.8, y: hy + 9.6), CGPoint(x: fx + 1.8, y: hy + 9.6), CGPoint(x: fx, y: hy + 11.4)])
        ctx.fill(nose, with: .color(MikanPalette.pink))
        ctx.stroke(nose, with: .color(MikanPalette.pink), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        drawMouth(ctx, mx: fx, my: hy + 11.6)

        var whiskers = ctx
        whiskers.opacity = 0.8
        for side in [-1.0, 1.0] {
            for (dy, dy2) in [(10.5, 9.0), (12.5, 13.0)] {
                var w = Path()
                w.move(to: CGPoint(x: fx + side * 8, y: hy + dy))
                w.addLine(to: CGPoint(x: fx + side * 17, y: hy + dy2))
                whiskers.stroke(w, with: .color(ink), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            }
        }

        if rig[.tear] > 0.01 {
            let x = fx - 10, y = hy + 9
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addQuadCurve(to: CGPoint(x: x, y: y + 4.6), control: CGPoint(x: x + 2.2, y: y + 3.6))
            drop.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 2.2, y: y + 3.6))
            var t = ctx
            t.opacity = rig[.tear]
            t.fill(drop, with: .color(MikanPalette.tear))
        }
    }

    private func drawEye(_ ctx: GraphicsContext, ex: CGFloat, ey: CGFloat, side: CGFloat) {
        let open = rig[.eyeOpen]
        if rig[.happyEyes] > 0.5 {
            arc(ctx, from: CGPoint(x: ex - 4.4, y: ey + 1.6), control: CGPoint(x: ex, y: ey - 4),
                to: CGPoint(x: ex + 4.4, y: ey + 1.6), width: 1.9)
            return
        }
        if open < 0.3 {
            arc(ctx, from: CGPoint(x: ex - 4.6, y: ey), control: CGPoint(x: ex, y: ey + 3),
                to: CGPoint(x: ex + 4.6, y: ey - 0.6 * side), width: 1.7)
            return
        }

        var e = ctx
        e.translateBy(x: 0, y: ey)
        e.scaleBy(x: 1, y: open)
        e.translateBy(x: 0, y: -ey)

        let w: CGFloat = 4.6, h: CGFloat = 5.6
        let outer = ex + side * w, innerX = ex - side * w
        var almond = Path()
        almond.move(to: CGPoint(x: innerX, y: ey + 0.6))
        almond.addCurve(to: CGPoint(x: outer, y: ey), control1: CGPoint(x: innerX, y: ey - h), control2: CGPoint(x: outer, y: ey - h))
        almond.addCurve(to: CGPoint(x: innerX, y: ey + 0.6), control1: CGPoint(x: outer, y: ey + h * 0.95),
                        control2: CGPoint(x: innerX, y: ey + h * 0.95))
        almond.closeSubpath()
        e.fill(almond, with: .color(.white))

        let ix = ex + rig[.look]
        let lid = rig[.sadLid]
        var clipped = e
        clipped.clip(to: almond)
        clipped.fill(ellipse(ix, ey, 4.5, 4.5), with: .color(MikanPalette.iris))
        var top = clipped
        top.opacity = 0.55
        top.fill(ellipse(ix, ey - 2.6, 4.5, 4.5), with: .color(MikanPalette.irisTop))
        clipped.fill(ellipse(ix, ey + 0.2, 2.3, 3.3), with: .color(MikanPalette.pupil))
        clipped.fill(ellipse(ix - 1.4, ey - 1.8, 1.6, 1.6), with: .color(.white))
        clipped.fill(ellipse(ix + 1.5, ey + 1.8, 0.6, 0.6), with: .color(.white))
        let lidLeft = MikanGeometry.mix(ey - 6.5, ey - 1.4 - side * 1.2, lid)
        let lidRight = MikanGeometry.mix(ey - 6.5, ey - 1.4 + side * 1.2, lid)
        if lid > 0.01 {
            clipped.fill(polygon([CGPoint(x: ex - 6, y: ey - 8), CGPoint(x: ex + 6, y: ey - 8),
                                  CGPoint(x: ex + 6, y: lidRight), CGPoint(x: ex - 6, y: lidLeft)]),
                         with: .color(MikanPalette.fur))
        }

        e.stroke(almond, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        var lash = Path()
        if lid > 0.5 {
            lash.move(to: CGPoint(x: ex - 4.6, y: lidLeft + side * 0.1))
            lash.addLine(to: CGPoint(x: ex + 4.6, y: lidRight - side * 0.1))
        } else {
            lash.move(to: CGPoint(x: innerX, y: ey + 0.6))
            lash.addCurve(to: CGPoint(x: outer, y: ey), control1: CGPoint(x: innerX, y: ey - h), control2: CGPoint(x: outer, y: ey - h))
        }
        e.stroke(lash, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func drawBrows(_ ctx: GraphicsContext, ex: CGFloat, by: CGFloat, side: CGFloat) {
        if rig[.browThink] > 0.01 {
            var c = ctx
            c.opacity = rig[.browThink]
            if side < 0 {
                arc(c, from: CGPoint(x: ex - 3.5, y: by + 0.5), control: CGPoint(x: ex, y: by - 2.5),
                    to: CGPoint(x: ex + 3.5, y: by), width: 1.5)
            } else {
                line(c, CGPoint(x: ex - 3.5, y: by + 1.8), CGPoint(x: ex + 3.5, y: by + 1.4), width: 1.5)
            }
        }
        if rig[.browSad] > 0.01 {
            var c = ctx
            c.opacity = rig[.browSad]
            line(c, CGPoint(x: ex + side * 3.6, y: by + 1.8), CGPoint(x: ex - side * 3, y: by - 0.6), width: 1.5)
        }
    }

    private func drawMouth(_ ctx: GraphicsContext, mx: CGFloat, my: CGFloat) {
        let k: CGFloat = 0.85, w: CGFloat = 1.3
        if rig[.mouthOpen] > 0.5 {
            var m = Path()
            m.move(to: CGPoint(x: mx - 4 * k, y: my))
            m.addQuadCurve(to: CGPoint(x: mx + 4 * k, y: my), control: CGPoint(x: mx, y: my + k))
            m.addQuadCurve(to: CGPoint(x: mx, y: my + 6 * k), control: CGPoint(x: mx + 3 * k, y: my + 6 * k))
            m.addQuadCurve(to: CGPoint(x: mx - 4 * k, y: my), control: CGPoint(x: mx - 3 * k, y: my + 6 * k))
            m.closeSubpath()
            ctx.fill(m, with: .color(MikanPalette.mouth))
            ctx.fill(ellipse(mx, my + 4.4 * k, 2 * k, 1.2 * k), with: .color(MikanPalette.tongue))
            ctx.stroke(m, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.8, lineJoin: .round))
        } else if rig[.mouthFrown] > 0.5 {
            arc(ctx, from: CGPoint(x: mx - 3 * k, y: my + 2.4 * k), control: CGPoint(x: mx, y: my - 0.2),
                to: CGPoint(x: mx + 3 * k, y: my + 2.4 * k), width: w)
        } else if rig[.mouthHmm] > 0.5 {
            arc(ctx, from: CGPoint(x: mx - 2.5 * k, y: my + 1.8 * k), control: CGPoint(x: mx, y: my + 0.8 * k),
                to: CGPoint(x: mx + 2.5 * k, y: my + 1.2 * k), width: w)
        } else {
            var m = Path()
            m.move(to: CGPoint(x: mx - 3.4 * k, y: my + 0.4 * k))
            m.addQuadCurve(to: CGPoint(x: mx, y: my), control: CGPoint(x: mx - 1.7 * k, y: my + 2.8 * k))
            m.addQuadCurve(to: CGPoint(x: mx + 3.4 * k, y: my + 0.4 * k), control: CGPoint(x: mx + 1.7 * k, y: my + 2.8 * k))
            ctx.stroke(m, with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Geometry

    private struct Ear {
        var side: CGPoint
        var tip: CGPoint
        var inner: [CGPoint]
    }

    private func ear(side: CGFloat, hx: CGFloat, hy: CGFloat) -> Ear {
        var sidePt = CGPoint(x: hx + side * 17, y: hy - 4)
        var tip = CGPoint(x: hx + side * 20, y: hy - 25)
        let innerPt = CGPoint(x: hx + side * 8, y: hy - 15)
        let pivot = MikanGeometry.mid(sidePt, innerPt)
        let twitch: CGFloat = side > 0 ? CGFloat(rig[.earTwitch]) : 0
        let angle = side * CGFloat(rig[.earDroop]) + twitch
        tip = MikanGeometry.rotate(tip, around: pivot, degrees: angle)
        sidePt = MikanGeometry.rotate(sidePt, around: pivot, degrees: angle * 0.25)
        let center = CGPoint(x: (sidePt.x + tip.x + innerPt.x) / 3, y: (sidePt.y + tip.y + innerPt.y) / 3)
        let inner = [sidePt, tip, innerPt].map { MikanGeometry.lerp(MikanGeometry.lerp(center, $0, 0.55), tip, 0.12) }
        return Ear(side: sidePt, tip: tip, inner: inner)
    }

    private func headPath(hx: CGFloat, hy: CGFloat, left: Ear, right: Ear) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: hx + x, y: hy + y) }
        var path = Path()
        path.move(to: left.side)
        path.addQuadCurve(to: left.tip, control: CGPoint(x: left.tip.x + 1, y: (left.side.y + left.tip.y) / 2))
        path.addQuadCurve(to: p(-8, -15), control: p(-13, -17))
        path.addQuadCurve(to: p(8, -15), control: p(0, -17.5))
        path.addQuadCurve(to: right.tip, control: p(13, -17))
        path.addQuadCurve(to: right.side, control: CGPoint(x: right.tip.x - 1, y: (right.side.y + right.tip.y) / 2))
        path.addCurve(to: p(18.5, 9), control1: p(20, 3), control2: p(20, 7))
        path.addLine(to: p(22, 11.5))
        path.addLine(to: p(16, 13))
        path.addCurve(to: p(0, 20), control1: p(12, 19), control2: p(6, 20))
        path.addCurve(to: p(-16, 13), control1: p(-6, 20), control2: p(-12, 19))
        path.addLine(to: p(-22, 11.5))
        path.addLine(to: p(-18.5, 9))
        path.addCurve(to: left.side, control1: p(-20, 7), control2: p(-20, 3))
        path.closeSubpath()
        return path
    }

    // MARK: Drawing helpers

    private func outlined(_ ctx: GraphicsContext, _ path: Path, width: CGFloat, color: Color, dash: [CGFloat]) {
        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: width + 2 * o, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(MikanPalette.stripe), style: StrokeStyle(lineWidth: width, lineCap: .butt, dash: dash))
    }

    private func fillOutlined(_ ctx: GraphicsContext, _ path: Path, _ color: Color) {
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(ink), lineWidth: 2 * o)
    }

    private func arc(_ ctx: GraphicsContext, from: CGPoint, control: CGPoint, to: CGPoint, width: CGFloat) {
        var p = Path()
        p.move(to: from)
        p.addQuadCurve(to: to, control: control)
        ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func line(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, width: CGFloat) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }
}

private extension GraphicsContext {
    mutating func rotate(around point: CGPoint, degrees: CGFloat) {
        translateBy(x: point.x, y: point.y)
        rotate(by: .degrees(degrees))
        translateBy(x: -point.x, y: -point.y)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
