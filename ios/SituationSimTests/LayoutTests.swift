import Testing
@testable import SituationSim

/// No two fielders should finish a play on top of each other (dots are 17 units
/// across, scaled by the field's dot size).
struct LayoutTests {
    @Test func fieldersNeverOverlap() {
        for level in Level.allCases {
            let minGap = 17 * Field.of(level).dot
            for hit in Hit.all {
                for mask in 0..<8 {
                    for outs in 0..<3 {
                        let sit = Situation(level: level, hitID: hit.id, outs: outs, runners: [mask & 1 != 0, mask & 2 != 0, mask & 4 != 0])
                        let a = Engine.solve(sit).assignments
                        let ps = Position.allCases
                        for i in ps.indices {
                            for j in ps.indices where j > i {
                                let d = a[ps[i]]!.to.distance(to: a[ps[j]]!.to)
                                #expect(d >= minGap, "\(level) \(hit.id) runners:\(mask) outs:\(outs): \(ps[i].rawValue) and \(ps[j].rawValue) are \(Int(d)) ft apart")
                            }
                        }
                    }
                }
            }
        }
    }
}
