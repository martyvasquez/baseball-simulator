import Foundation
import Testing
@testable import SituationSim

/// The Swift engine must give the same answer as the web engine (engine.js) for
/// every situation: 14 plays × 8 runner setups × 3 out counts × 3 field sizes.
/// fixtures.json is exported from engine.js.
struct EngineParityTests {
    struct Fixture: Decodable {
        struct A: Decodable { let to: [Double]; let job: String; let type: String }
        struct Move: Decodable { let id: String; let from: String; let to: String; let out: Bool; let note: String; let endPt: [Double]? }
        let level: String
        let hit: String
        let outs: Int
        let runners: [Bool]
        let ball: [Double]
        let assignments: [String: A]
        let throwPath: [[Double]]
        let altThrows: [[[Double]]]
        let carry: Bool
        let runnerMoves: [Move]
        let target: String?
        let played: [String]
        let headline: String
        let why: String
        let tips: [String]
        let rules: [String]
    }

    static let fixtures: [Fixture] = {
        let url = Bundle(for: BundleToken.self).url(forResource: "fixtures", withExtension: "json")!
        return try! JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }()

    private final class BundleToken {}

    func close(_ p: Pt, _ a: [Double], _ label: String) {
        #expect(abs(p.x - a[0]) < 0.01 && abs(p.y - a[1]) < 0.01, "\(label): got (\(p.x), \(p.y)), expected (\(a[0]), \(a[1]))")
    }

    @Test func fixtureCount() {
        #expect(Self.fixtures.count == 1008)
    }

    @Test func everySituationMatchesTheWebEngine() {
        for f in Self.fixtures {
            let sit = Situation(level: Level(rawValue: f.level)!, hitID: f.hit, outs: f.outs, runners: f.runners)
            let s = Engine.solve(sit)
            let tag = "\(f.level) \(f.hit) outs:\(f.outs) runners:\(f.runners)"

            close(s.ball, f.ball, "\(tag) ball")
            for p in Position.allCases {
                guard let want = f.assignments[p.rawValue], let got = s.assignments[p] else {
                    Issue.record("\(tag) missing \(p.rawValue)")
                    continue
                }
                close(got.to, want.to, "\(tag) \(p.rawValue) spot")
                #expect(got.job == want.job, "\(tag) \(p.rawValue) job")
                #expect(got.type.rawValue == want.type, "\(tag) \(p.rawValue) type")
            }
            #expect(s.throwPath.count == f.throwPath.count, "\(tag) throw path length")
            for (a, b) in zip(s.throwPath, f.throwPath) { close(a, b, "\(tag) throw") }
            #expect(s.altThrows.count == f.altThrows.count, "\(tag) possible throws")
            for (pa, pb) in zip(s.altThrows, f.altThrows) {
                #expect(pa.count == pb.count, "\(tag) possible throw length")
                for (a, b) in zip(pa, pb) { close(a, b, "\(tag) possible throw") }
            }
            #expect(s.carry == f.carry, "\(tag) carry")
            #expect(s.runners.count == f.runnerMoves.count, "\(tag) runner count")
            for (m, w) in zip(s.runners, f.runnerMoves) {
                #expect(m.id == w.id && m.from.rawValue == w.from && m.to.rawValue == w.to && m.out == w.out && m.note == w.note, "\(tag) runner \(w.id)")
                if let e = w.endPt, let g = m.endPt { close(g, e, "\(tag) runner \(w.id) end") }
                #expect((m.endPt == nil) == (w.endPt == nil), "\(tag) runner \(w.id) endPt presence")
            }
            #expect(s.target?.rawValue == f.target, "\(tag) target")
            #expect(s.played == f.played, "\(tag) played")
            #expect(s.headline == f.headline, "\(tag) headline")
            #expect(s.why == f.why, "\(tag) why")
            #expect(s.tips == f.tips, "\(tag) tips")
            #expect(s.rules == f.rules, "\(tag) rules")
        }
    }

    @Test func everyRuleHasASourceNote() throws {
        let notes = SourceNotes.shared.notes
        for f in Self.fixtures {
            for id in f.rules { #expect(notes[id] != nil, "no source note for \(id)") }
        }
    }
}
