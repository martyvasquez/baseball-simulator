import SwiftUI

/// Maps field coordinates (feet) to view coordinates, fitting the whole field.
struct FieldFrame {
    let field: Field
    let scale: CGFloat
    let home: CGPoint

    init(field: Field, size: CGSize) {
        self.field = field
        let d = field.dot
        let halfW = field.line * 0.5.squareRoot() + 30 * d
        let top = field.center + 16 * d
        let bottom = 55 * d
        scale = min(size.width / (2 * halfW), size.height / (top + bottom))
        home = CGPoint(x: size.width / 2, y: (size.height - (top + bottom) * scale) / 2 + top * scale)
    }

    func v(_ p: Pt) -> CGPoint { CGPoint(x: home.x + p.x * scale, y: home.y - p.y * scale) }
    func ft(_ c: CGPoint) -> Pt { Pt((c.x - home.x) / scale, (home.y - c.y) / scale) }
    /// Size of one unit of the dot artwork (dots are drawn at a fixed size, scaled to the field).
    var u: CGFloat { field.dot * scale }
}

/// The field with players, runners, and the ball, animated through a play.
struct FieldView: View {
    @Bindable var model: SimulatorModel

    var body: some View {
        GeometryReader { geo in
            let frame = FieldFrame(field: model.field, size: geo.size)
            TimelineView(.animation(paused: !model.isAnimating)) { timeline in
                let scene = FieldScene(
                    field: model.field,
                    situation: model.situation,
                    solution: model.solution,
                    t: model.elapsed(at: timeline.date),
                    focus: model.focus,
                    guess: model.guess
                )
                Canvas { ctx, _ in
                    FieldPainter(frame: frame, scene: scene).paint(&ctx)
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if model.isGuessing { model.guess = frame.ft(value.location) }
                    }
                    .onEnded { value in
                        if !model.isGuessing { tap(frame.ft(value.location)) }
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(model.isGuessing ? "Drag to place where your player should go." : "")
    }

    private func tap(_ p: Pt) {
        let f = model.field
        if let solution = model.solution {
            // Tap a player to focus on them.
            let t = model.elapsed(at: .now) ?? 0
            let hit = Position.allCases.min { a, b in
                FieldScene.fielderPos(a, solution, f, t).distance(to: p) < FieldScene.fielderPos(b, solution, f, t).distance(to: p)
            }
            if let hit, FieldScene.fielderPos(hit, solution, f, t).distance(to: p) < 12 * f.dot {
                model.toggleFocus(hit)
            }
            return
        }
        // Tap a base to toggle a runner.
        for (i, b) in [Base.first, .second, .third].enumerated() where f[b].distance(to: p) < 14 * f.dot {
            model.toggleRunner(i + 1)
            return
        }
    }

    private var accessibilityText: String {
        var s = "\(model.situation.level.name) field. \(model.runnersText), \(model.situation.outs) out\(model.situation.outs == 1 ? "" : "s"). \(model.situation.hit.text)."
        if let sol = model.solution { s += " \(sol.headline)" }
        return s
    }
}

/// Everything needed to draw one frame.
struct FieldScene {
    let field: Field
    let situation: Situation
    let solution: Solution?
    /// Milliseconds into the reveal animation (nil = before the play).
    let t: Double?
    let focus: Position?
    let guess: Pt?

    static let baseOrder: [Base] = [.home, .first, .second, .third, .home]

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func ease(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

    static func fielderPos(_ p: Position, _ s: Solution, _ f: Field, _ t: Double) -> Pt {
        let u = ease(clamp01((t - 150) / 1850))
        return f.homePos[p]!.lerp(s.assignments[p]!.to, u)
    }

    var finished: Bool { (t ?? 0) >= SimulatorModel.playDuration }

    /// Runner paths: through each base, and off toward the dugout after scoring
    /// (except the runner being thrown at, who stays at the plate).
    func runnerPaths(_ s: Solution) -> [(move: RunnerMove, path: [Pt])] {
        var scored = 0
        return s.runners.map { m in
            if let end = m.endPt { return (m, [field.runnerPt(m.from), end]) }
            let i = m.from == .home ? 0 : m.from.order
            let j = m.to == .home ? 4 : m.to.order
            var path: [Pt] = []
            if i <= j { for k in i...j { path.append(field.runnerPt(Self.baseOrder[k])) } }
            if m.to == .home && m.from != .home && !s.played.contains(m.id) {
                path.append(Pt((-16 - 12 * Double(scored)) * field.dot, -14 * field.dot))
                scored += 1
            }
            return (m, path)
        }
    }

    /// Runners on base before the play: the batter plus anyone on.
    var startingRunners: [(id: String, base: Base)] {
        var list: [(String, Base)] = [("B", .home)]
        for (i, b) in [Base.first, .second, .third].enumerated() where situation.runners[i] { list.append(("R\(i + 1)", b)) }
        return list
    }
}

struct FieldPainter {
    let frame: FieldFrame
    let scene: FieldScene

    private var f: Field { frame.field }
    private var u: CGFloat { frame.u }

    func paint(_ ctx: inout GraphicsContext) {
        drawField(&ctx)
        guard let s = scene.solution, let t = scene.t else {
            drawStatic(&ctx)
            return
        }
        drawPlay(&ctx, s, t)
    }

    // MARK: - Field

    private func arcPath(_ radius: (Double) -> Double) -> Path {
        var p = Path()
        p.move(to: frame.v(.zero))
        for deg in stride(from: -45.0, through: 45.0, by: 3) { p.addLine(to: frame.v(polar(deg, radius(deg)))) }
        p.closeSubpath()
        return p
    }

    private func drawField(_ ctx: inout GraphicsContext) {
        let k = f.k, d = f.dot
        let bounds = CGRect(x: -2000, y: -2000, width: 6000, height: 6000)
        ctx.fill(Path(bounds), with: .color(Theme.foulGrass))

        ctx.fill(arcPath { f.fenceAt($0) }, with: .color(Theme.track))
        let grass = arcPath { f.fenceAt($0) - 11 * d }
        ctx.drawLayer { layer in
            layer.clip(to: grass)
            layer.fill(grass, with: .color(Theme.grass))
            // Mowing stripes
            let w = 12 * d * frame.scale
            layer.translateBy(x: frame.home.x, y: frame.home.y)
            layer.rotate(by: .degrees(45))
            for i in stride(from: -60, through: 60, by: 1) {
                let x = CGFloat(i) * 2 * w
                layer.fill(Path(CGRect(x: x, y: -3000, width: w, height: 6000)), with: .color(Theme.grassStripe))
            }
        }

        var fence = Path()
        for (i, deg) in stride(from: -45.0, through: 45.0, by: 3).enumerated() {
            let p = frame.v(polar(deg, f.fenceAt(deg)))
            if i == 0 { fence.move(to: p) } else { fence.addLine(to: p) }
        }
        ctx.stroke(fence, with: .color(.white.opacity(0.9)), lineWidth: 2 * u)

        for deg in [-45.0, 0, 45] {
            // Center label sits above the fence; corner labels sit just inside the foul pole, above the line.
            let text = Text("\(Int(f.fenceAt(deg).rounded()))'").font(.system(size: 8 * u, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            if deg == 0 {
                ctx.draw(text, at: frame.v(polar(0, f.fenceAt(0) + 9 * d)))
            } else {
                let p = frame.v(polar(deg, f.fenceAt(deg)))
                ctx.draw(text, at: CGPoint(x: p.x - (deg > 0 ? 1 : -1) * 24 * u, y: p.y - 16 * u))
            }
        }

        // Infield dirt, kept to fair territory plus a strip for the bags.
        let a = 16 * k
        var wedge = Path()
        wedge.move(to: frame.v(Pt(0, -a)))
        wedge.addLine(to: frame.v(Pt(-1000, 1000 - a)))
        wedge.addLine(to: frame.v(Pt(1000, 1000 - a)))
        wedge.closeSubpath()
        let mound = frame.v(f.mound)
        let dirtR = 95 * k * frame.scale
        ctx.drawLayer { layer in
            layer.clip(to: wedge)
            layer.fill(Path(ellipseIn: CGRect(x: mound.x - dirtR, y: mound.y - dirtR, width: 2 * dirtR, height: 2 * dirtR)), with: .color(Theme.dirt))
        }
        var diamond = Path()
        diamond.addLines([Pt(0, 15 * k), Pt(50 * k, 63.6 * k), Pt(0, 112 * k), Pt(-50 * k, 63.6 * k)].map(frame.v))
        diamond.closeSubpath()
        ctx.fill(diamond, with: .color(Theme.grass))
        circle(&ctx, frame.v(.zero), 13 * k * frame.scale, Theme.dirt)
        circle(&ctx, mound, 9 * k * frame.scale, Theme.dirt)
        ctx.fill(Path(CGRect(x: mound.x - 3 * k * frame.scale, y: mound.y - 0.6 * frame.scale, width: 6 * k * frame.scale, height: 1.2 * frame.scale)), with: .color(.white))

        let corner = polar(45, f.line)
        for sgn in [-1.0, 1.0] {
            var line = Path()
            line.move(to: frame.v(.zero))
            line.addLine(to: frame.v(Pt(sgn * corner.x, corner.y)))
            ctx.stroke(line, with: .color(.white), lineWidth: 1.2 * u)
        }
        var plate = Path()
        plate.addLines([Pt(0, -4), Pt(3, -1), Pt(3, 2), Pt(-3, 2), Pt(-3, -1)].map { frame.v($0 * d) })
        plate.closeSubpath()
        ctx.fill(plate, with: .color(.white))

        for b in [Base.first, .second, .third] {
            let c = frame.v(f[b])
            let s = 3.5 * u
            var bag = Path()
            bag.addLines([CGPoint(x: c.x, y: c.y - s * 1.41), CGPoint(x: c.x + s * 1.41, y: c.y), CGPoint(x: c.x, y: c.y + s * 1.41), CGPoint(x: c.x - s * 1.41, y: c.y)])
            bag.closeSubpath()
            ctx.fill(bag, with: .color(.white))
        }
    }

    // MARK: - Actors

    private func circle(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    private func fielder(_ ctx: inout GraphicsContext, _ p: Position, at pt: Pt, ring: Color, dim: Bool) {
        let c = frame.v(pt)
        let r = 8.5 * u
        var layer = ctx
        layer.opacity = dim ? 0.3 : 1
        layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 2 * u, y: 1 * u))
        circle(&layer, c, r, Theme.player)
        layer.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(ring), lineWidth: 2 * u)
        layer.draw(Text(p.label).font(.system(size: (p.label.count > 1 ? 6.5 : 7.5) * u, weight: .bold, design: .rounded)).foregroundStyle(.white), at: c)
    }

    private func runner(_ ctx: inout GraphicsContext, _ id: String, at pt: Pt, dim: Bool = false) {
        let c = frame.v(pt)
        let r = 6.5 * u
        var layer = ctx
        layer.opacity = dim ? 0.4 : 1
        circle(&layer, c, r, Theme.runner)
        layer.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white), lineWidth: 1.5 * u)
        layer.draw(Text(id).font(.system(size: 5 * u, weight: .bold, design: .rounded)).foregroundStyle(.white), at: c)
    }

    private func tag(_ ctx: inout GraphicsContext, _ text: String, above pt: Pt) {
        let c = frame.v(pt)
        var layer = ctx
        layer.addFilter(.shadow(color: .black.opacity(0.9), radius: 1.5))
        layer.draw(Text(text).font(.system(size: 7 * u, weight: .heavy, design: .rounded)).foregroundStyle(.white), at: CGPoint(x: c.x, y: c.y - 11 * u))
    }

    private func ball(_ ctx: inout GraphicsContext, _ pt: Pt, radius: Double) {
        let c = frame.v(pt)
        let r = radius * u
        circle(&ctx, c, r, .white)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.red.opacity(0.8)), lineWidth: 0.8 * u)
    }

    private func polyline(_ pts: [Pt]) -> Path {
        var p = Path()
        p.addLines(pts.map(frame.v))
        return p
    }

    private func guessMarker(_ ctx: inout GraphicsContext, _ pt: Pt) {
        let c = frame.v(pt)
        let r = 9 * u
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: rect), with: .color(Theme.field.opacity(0.3)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.field), style: StrokeStyle(lineWidth: 1.5 * u, dash: [3 * u, 2 * u]))
        ctx.draw(Text("?").font(.system(size: 9 * u, weight: .heavy, design: .rounded)).foregroundStyle(.white), at: c)
    }

    // MARK: - Before the play

    private func drawStatic(_ ctx: inout GraphicsContext) {
        if let g = scene.guess { guessMarker(&ctx, g) }
        for r in scene.startingRunners { runner(&ctx, r.id, at: f.runnerPt(r.base)) }
        for p in Position.allCases {
            fielder(&ctx, p, at: f.homePos[p]!, ring: p == scene.focus ? Theme.field : .white, dim: false)
        }
    }

    // MARK: - The play

    private func drawPlay(_ ctx: inout GraphicsContext, _ s: Solution, _ t: Double) {
        let finished = scene.finished
        let focus = scene.focus
        let clamp01 = FieldScene.clamp01
        let ease = FieldScene.ease

        // Movement trails once the play is over
        if finished {
            for p in Position.allCases {
                let a = s.assignments[p]!
                let from = f.homePos[p]!
                guard from.distance(to: a.to) >= 4 else { continue }
                let opacity = focus == nil || focus == p ? 0.55 : 0.12
                ctx.stroke(polyline([from, a.to]), with: .color(Theme.color(a.type).opacity(opacity)),
                           style: StrokeStyle(lineWidth: u, dash: [2 * u, 2.5 * u]))
            }
        }

        let paths = scene.runnerPaths(s)
        if finished {
            for (_, path) in paths where path.count > 1 && path[0].distance(to: path[path.count - 1]) > 2 {
                ctx.stroke(polyline(path), with: .color(Theme.runner.opacity(0.6)), style: StrokeStyle(lineWidth: u, dash: [2 * u, 2 * u]))
            }
        }

        // Throws: the one that happens (yellow) and the ones that might (dotted)
        if s.throwPath.count > 1 && t >= 1900 {
            let o = clamp01((t - 1900) / 300)
            for alt in s.altThrows {
                ctx.stroke(polyline(alt), with: .color(.white.opacity(0.7 * o)),
                           style: StrokeStyle(lineWidth: 1.2 * u, lineCap: .round, dash: [0.1, 3 * u]))
            }
            let visible = Array(s.throwPath.dropFirst(s.carry ? 1 : 0))
            if visible.count > 1 {
                ctx.stroke(polyline(visible), with: .color(Theme.field.opacity(o)),
                           style: StrokeStyle(lineWidth: 1.8 * u, lineJoin: .round, dash: [5 * u, 3 * u]))
                arrowhead(&ctx, from: visible[visible.count - 2], to: visible[visible.count - 1], opacity: o)
            }
        }

        if let g = scene.guess, focus != nil { guessMarker(&ctx, g) }

        // Runners
        let ru = ease(clamp01((t - 150) / 2500))
        for (m, path) in paths {
            let pt = point(alongPath: path, at: ru)
            runner(&ctx, m.id, at: pt, dim: finished && m.out)
            if finished {
                if m.out {
                    tag(&ctx, "OUT", above: pt)
                } else if s.played.contains(m.id) {
                    let c = frame.v(pt)
                    let r = 9.5 * u
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.field), lineWidth: 1.2 * u)
                    tag(&ctx, "THROW HERE", above: pt)
                }
            }
        }

        // Fielders
        for p in Position.allCases {
            let a = s.assignments[p]!
            fielder(&ctx, p, at: FieldScene.fielderPos(p, s, f, t), ring: Theme.color(a.type), dim: focus != nil && focus != p)
        }

        // Ball: hit, then thrown
        let isFly = scene.situation.hit.kind == .fly || scene.situation.hit.kind == .gap
        if s.throwPath.count > 1 && t >= 2000 {
            ball(&ctx, point(alongPath: s.throwPath, at: clamp01((t - 2000) / 1300)), radius: 3)
        } else {
            let hb = clamp01(t / 750)
            let pos = Pt.zero.lerp(s.ball, isFly ? hb : ease(hb))
            ball(&ctx, pos, radius: isFly ? 3 + 4 * sin(Double.pi * hb) : 3)
        }
    }

    private func arrowhead(_ ctx: inout GraphicsContext, from a: Pt, to b: Pt, opacity: Double) {
        let tip = frame.v(b)
        let tail = frame.v(a)
        let ang = atan2(tip.y - tail.y, tip.x - tail.x)
        let len = 5 * u, w = 3 * u
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - len * cos(ang) + w * sin(ang), y: tip.y - len * sin(ang) - w * cos(ang)))
        p.addLine(to: CGPoint(x: tip.x - len * cos(ang) - w * sin(ang), y: tip.y - len * sin(ang) + w * cos(ang)))
        p.closeSubpath()
        ctx.fill(p, with: .color(Theme.field.opacity(opacity)))
    }
}
