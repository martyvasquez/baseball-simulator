import Foundation

enum Level: String, CaseIterable, Identifiable, Sendable {
    case ll, u14, hs

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ll: "Little League"
        case .u14: "13U / 14U"
        case .hs: "High School"
        }
    }

    /// Short name for tight spaces like a segmented control.
    var shortName: String {
        switch self {
        case .ll: "LL"
        case .u14: "13U/14U"
        case .hs: "HS"
        }
    }

    var detail: String {
        switch self {
        case .ll: "60' bases · 46' mound · 200' fence"
        case .u14: "80' bases · 54' mound · ~300' fence"
        case .hs: "90' bases · 60'6\" mound · 330' lines, 390' center"
        }
    }

    // Field sizes. `ofDepth` is how deep outfielders play as a fraction of the fence.
    // `doubleCut`: big enough field that gap balls need a relay man AND a trail man.
    var bases: Double { switch self { case .ll: 60; case .u14: 80; case .hs: 90 } }
    var mound: Double { switch self { case .ll: 46; case .u14: 54; case .hs: 60.5 } }
    var line: Double { switch self { case .ll: 200; case .u14: 290; case .hs: 330 } }
    var center: Double { switch self { case .ll: 200; case .u14: 310; case .hs: 390 } }
    var ofDepth: Double { switch self { case .ll: 0.8; case .u14, .hs: 0.84 } }
    var doubleCut: Bool { self != .ll }
    var ruleID: String { switch self { case .ll: "D1"; case .u14: "D2"; case .hs: "D3" } }
}

enum Position: String, CaseIterable, Identifiable, Sendable {
    case p = "P", c = "C", first = "1B", second = "2B", ss = "SS", third = "3B", lf = "LF", cf = "CF", rf = "RF"

    var id: String { rawValue }
    var label: String { rawValue }

    var name: String {
        switch self {
        case .p: "Pitcher"
        case .c: "Catcher"
        case .first: "First Baseman"
        case .second: "Second Baseman"
        case .ss: "Shortstop"
        case .third: "Third Baseman"
        case .lf: "Left Fielder"
        case .cf: "Center Fielder"
        case .rf: "Right Fielder"
        }
    }
}

enum Base: String, CaseIterable, Sendable {
    case first = "1", second = "2", third = "3", home = "H"

    var name: String {
        switch self {
        case .first: "1st"
        case .second: "2nd"
        case .third: "3rd"
        case .home: "home"
        }
    }

    /// "home" or "to 2nd" — for "throw ___".
    var throwPhrase: String { self == .home ? "home" : "to \(name)" }

    /// Running order index (home as the starting point is 0).
    var order: Int {
        switch self {
        case .home: 0
        case .first: 1
        case .second: 2
        case .third: 3
        }
    }
}

enum HitKind: Sendable { case ground, bunt, fly, single, gap }

struct Hit: Identifiable, Hashable, Sendable {
    let id: String
    let kind: HitKind
    let fielder: Position?
    let leftSide: Bool
    let group: String
    let label: String
    let text: String

    static let all: [Hit] = [
        Hit(id: "gb_P", kind: .ground, fielder: .p, leftSide: false, group: "Ground ball", label: "P", text: "Ground ball back to the pitcher"),
        Hit(id: "gb_1B", kind: .ground, fielder: .first, leftSide: false, group: "Ground ball", label: "1B", text: "Ground ball to first base"),
        Hit(id: "gb_2B", kind: .ground, fielder: .second, leftSide: false, group: "Ground ball", label: "2B", text: "Ground ball to second base"),
        Hit(id: "gb_SS", kind: .ground, fielder: .ss, leftSide: false, group: "Ground ball", label: "SS", text: "Ground ball to shortstop"),
        Hit(id: "gb_3B", kind: .ground, fielder: .third, leftSide: false, group: "Ground ball", label: "3B", text: "Ground ball to third base"),
        Hit(id: "bunt", kind: .bunt, fielder: nil, leftSide: false, group: "Bunt", label: "Bunt", text: "Bunt down the third-base line"),
        Hit(id: "fly_LF", kind: .fly, fielder: .lf, leftSide: false, group: "Fly ball (caught)", label: "LF", text: "Fly ball to left field"),
        Hit(id: "fly_CF", kind: .fly, fielder: .cf, leftSide: false, group: "Fly ball (caught)", label: "CF", text: "Fly ball to center field"),
        Hit(id: "fly_RF", kind: .fly, fielder: .rf, leftSide: false, group: "Fly ball (caught)", label: "RF", text: "Fly ball to right field"),
        Hit(id: "single_LF", kind: .single, fielder: .lf, leftSide: false, group: "Base hit (single)", label: "LF", text: "Base hit to left field"),
        Hit(id: "single_CF", kind: .single, fielder: .cf, leftSide: false, group: "Base hit (single)", label: "CF", text: "Base hit to center field"),
        Hit(id: "single_RF", kind: .single, fielder: .rf, leftSide: false, group: "Base hit (single)", label: "RF", text: "Base hit to right field"),
        Hit(id: "gap_LC", kind: .gap, fielder: .cf, leftSide: true, group: "Gap hit (double)", label: "Left-center", text: "Double into the left-center gap"),
        Hit(id: "gap_RC", kind: .gap, fielder: .cf, leftSide: false, group: "Gap hit (double)", label: "Right-center", text: "Double into the right-center gap"),
    ]

    static func named(_ id: String) -> Hit { all.first { $0.id == id }! }

    /// Hits grouped in display order.
    static var groups: [(name: String, hits: [Hit])] {
        var order: [String] = []
        var map: [String: [Hit]] = [:]
        for h in all {
            if map[h.group] == nil { order.append(h.group) }
            map[h.group, default: []].append(h)
        }
        return order.map { ($0, map[$0]!) }
    }
}

enum JobType: String, Sendable {
    case field, cover, cutoff, backup, other
}

struct Assignment: Sendable {
    var to: Pt
    var job: String
    var type: JobType
}

struct RunnerMove: Identifiable, Sendable {
    var id: String
    var from: Base
    var to: Base
    var out = false
    var note = ""
    var endPt: Pt?
}

struct Situation: Hashable, Sendable {
    var level: Level = .ll
    var hitID: String = "gb_SS"
    var outs = 0
    /// Runners on 1st, 2nd, 3rd.
    var runners: [Bool] = [false, false, false]

    var hit: Hit { Hit.named(hitID) }
    func on(_ b: Int) -> Bool { runners[b - 1] }
}

struct Solution: Sendable {
    var assignments: [Position: Assignment] = [:]
    var ball: Pt = .zero
    var throwPath: [Pt] = []
    var altThrows: [[Pt]] = []
    var carry = false
    var runners: [RunnerMove] = []
    var target: Base?
    var played: [String] = []
    var headline = ""
    var why = ""
    var tips: [String] = []
    var rules: [String] = []
    var dp = false
}
