import Foundation

/// Geometry for one level. Infield spots come from a 90-ft template scaled by
/// `k`; outfield spots are fractions of the fence distance.
struct Field: Sendable {
    let level: Level
    let k: Double
    /// Visual size of dots relative to the original 300-ft drawing.
    let dot: Double
    let bases: [Base: Pt]
    let mound: Pt
    let homePos: [Position: Pt]
    let ball: [String: Pt]

    private static let cache: [Level: Field] = Dictionary(uniqueKeysWithValues: Level.allCases.map { ($0, Field(level: $0)) })
    static func of(_ level: Level) -> Field { cache[level]! }

    private init(level L: Level) {
        level = L
        k = L.bases / 90
        let k = self.k
        let b = L.bases / 2.0.squareRoot()
        bases = [.first: Pt(b, b), .second: Pt(0, 2 * b), .third: Pt(-b, b), .home: .zero]
        mound = Pt(0, L.mound)
        dot = (L.line * 0.5.squareRoot() + 30) / 250
        let s = { (x: Double, y: Double) in Pt(x * k, y * k) }
        let fence = { (d: Double) in Field.fenceAt(d, L) }
        let of = { (d: Double, f: Double) in polar(d, f * fence(d)) }
        let flyF = min(L.ofDepth + 0.07, 0.95)
        homePos = [
            .p: Pt(0, L.mound - 2.5 * k), .c: Pt(0, -6), .first: s(70, 88), .second: s(38, 140), .ss: s(-38, 140),
            .third: s(-68, 86), .lf: of(-32, L.ofDepth), .cf: of(0, L.ofDepth), .rf: of(32, L.ofDepth),
        ]
        ball = [
            "gb_P": s(-4, 48), "gb_1B": s(60, 94), "gb_2B": s(30, 128), "gb_SS": s(-30, 128), "gb_3B": s(-60, 94), "bunt": s(-14, 26),
            "fly_LF": of(-32, flyF), "fly_CF": of(0, flyF), "fly_RF": of(32, flyF),
            "single_LF": of(-31, 0.6), "single_CF": of(0, 0.6), "single_RF": of(31, 0.6),
            "gap_LC": of(-21, 0.94), "gap_RC": of(21, 0.94),
        ]
    }

    var bases_ft: Double { level.bases }
    var line: Double { level.line }
    var center: Double { level.center }
    var doubleCut: Bool { level.doubleCut }

    subscript(_ b: Base) -> Pt { bases[b]! }

    private static func fenceAt(_ degrees: Double, _ L: Level) -> Double {
        let a = min(45, abs(degrees))
        return L.line + (L.center - L.line) * cos(2 * a * Double.pi / 180)
    }

    func fenceAt(_ degrees: Double) -> Double { Field.fenceAt(degrees, level) }

    /// Pull a point back inside the fence, `margin` feet short of it.
    func inFence(_ p: Pt, _ margin: Double) -> Pt {
        let r = fenceAt(angleOf(p)) - margin
        return p.length > r ? p.unit * r : p
    }

    /// Where a fielder stands when covering a base (on the bag, nudged toward the infield).
    func coverPt(_ base: Base) -> Pt {
        base == .home ? Pt(0, -3) : along(self[base], mound, 3 * dot)
    }

    /// Where a runner stands on a base (just outside the bag so dots don't overlap).
    func runnerPt(_ base: Base) -> Pt {
        base == .home ? Pt(-13, 3) * dot : beyond(Pt(0, level.bases / 2.0.squareRoot()), self[base], 15 * dot)
    }
}
