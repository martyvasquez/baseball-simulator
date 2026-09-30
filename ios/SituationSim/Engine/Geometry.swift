import Foundation

/// A point on the field in feet. Home plate is (0,0), +x toward first base /
/// right field, +y toward center field.
struct Pt: Hashable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static let zero = Pt(0, 0)

    static func + (a: Pt, b: Pt) -> Pt { Pt(a.x + b.x, a.y + b.y) }
    static func - (a: Pt, b: Pt) -> Pt { Pt(a.x - b.x, a.y - b.y) }
    static func * (a: Pt, k: Double) -> Pt { Pt(a.x * k, a.y * k) }

    var length: Double { (x * x + y * y).squareRoot() }

    var unit: Pt {
        let l = length
        return self * (1 / (l == 0 ? 1 : l))
    }

    func distance(to b: Pt) -> Double { (self - b).length }

    /// Point `d` feet from self toward `b`.
    func toward(_ b: Pt, _ d: Double) -> Pt { self + (b - self).unit * d }

    /// Linear interpolation.
    func lerp(_ b: Pt, _ t: Double) -> Pt { Pt(x + (b.x - x) * t, y + (b.y - y) * t) }
}

/// Point `d` feet from `a` toward `b`.
func along(_ a: Pt, _ b: Pt, _ d: Double) -> Pt { a.toward(b, d) }

/// Point `d` feet past `to`, continuing the line from `from` (where a backup stands).
func beyond(_ from: Pt, _ to: Pt, _ d: Double) -> Pt { to + (to - from).unit * d }

private let deg = Double.pi / 180

/// Point at an angle in degrees from the center-field line (negative = left field).
func polar(_ degrees: Double, _ r: Double) -> Pt { Pt(r * sin(degrees * deg), r * cos(degrees * deg)) }

/// Angle of a point in degrees from the center-field line.
func angleOf(_ p: Pt) -> Double { atan2(p.x, p.y) / deg }

/// Point at fraction `t` along a polyline.
func point(alongPath path: [Pt], at t: Double) -> Pt {
    guard let first = path.first else { return .zero }
    guard path.count > 1 else { return first }
    var segs: [Double] = []
    var total = 0.0
    for i in 1..<path.count {
        let d = path[i - 1].distance(to: path[i])
        segs.append(d)
        total += d
    }
    var want = t * total
    for i in segs.indices {
        if want <= segs[i] || i == segs.count - 1 {
            let f = segs[i] > 0 ? min(1, max(0, want / segs[i])) : 1
            return path[i].lerp(path[i + 1], f)
        }
        want -= segs[i]
    }
    return path[path.count - 1]
}
