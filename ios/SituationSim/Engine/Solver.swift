import Foundation

/// Works out where every fielder goes, what the runners do, and where the ball
/// is thrown. A line-for-line port of the web version's engine.js; the parity
/// test checks it against that engine's answers for every situation.
enum Engine {
    static func solve(_ sit: Situation) -> Solution {
        let s = Solver(sit)
        return s.run()
    }
}

private final class Solver {
    let G: Field
    let hit: Hit
    let outs: Int
    let r1: Bool, r2: Bool, r3: Bool
    var res = Solution()

    init(_ sit: Situation) {
        G = Field.of(sit.level)
        hit = sit.hit
        outs = sit.outs
        r1 = sit.on(1)
        r2 = sit.on(2)
        r3 = sit.on(3)
    }

    var K: Double { G.k }
    var anyRunners: Bool { r1 || r2 || r3 }
    func B(_ b: Base) -> Pt { G[b] }
    func home(_ p: Position) -> Pt { G.homePos[p]! }

    /// First assignment wins, so specific jobs are set before general ones.
    func set(_ p: Position, _ to: Pt, _ job: String, _ type: JobType) {
        if res.assignments[p] == nil { res.assignments[p] = Assignment(to: to, job: job, type: type) }
    }

    func run() -> Solution {
        let ball = G.ball[hit.id]!
        res.ball = ball
        switch hit.kind {
        case .ground: ground(ball)
        case .bunt: bunt(ball)
        case .fly: fly(ball)
        case .single: single(ball)
        case .gap: gap(ball)
        }
        var seen = Set<String>()
        res.rules = ([G.level.ruleID] + res.rules).filter { seen.insert($0).inserted }
        for p in Position.allCases { set(p, home(p), "Stay ready in your spot", .other) }

        var played = res.runners.filter { m in res.target != nil && m.to == res.target && !m.out }
        // Several runners heading home: the throw is for the trailing one.
        if res.target == .home && played.count > 1 {
            played = [played.dropFirst().reduce(played[0]) { a, b in a.from.rawValue < b.from.rawValue ? a : b }]
        }
        res.played = played.map(\.id)
        if res.dp { res.played.append("B") }
        return res
    }

    // Who covers a base on an infield ground ball fielded by F.
    func infieldCoverer(_ base: Base, _ F: Position) -> Position {
        switch base {
        case .first: return F == .first ? .p : .first
        case .second:
            if F == .p { return .ss }
            return F == .ss || F == .third ? .second : .ss
        case .third: return .third
        case .home: return .c
        }
    }

    // MARK: - Ground balls

    func ground(_ ball: Pt) {
        let F = hit.fielder!
        let f2 = r1, f3 = r1 && r2, fH = r1 && r2 && r3
        var target: Base
        var dp = false

        if outs == 2 {
            var opts: [Base] = [.first]
            if f2 { opts.append(.second) }
            if f3 { opts.append(.third) }
            if fH { opts.append(.home) }
            target = opts.dropFirst().reduce(opts[0]) { a, b in ball.distance(to: B(b)) < ball.distance(to: B(a)) ? b : a }
            res.why = opts.count > 1
                ? "Two outs — you only need ONE out to end the inning. Take the closest force play: \(target.name)."
                : "Two outs — throw the batter out at 1st to end the inning."
        } else if fH {
            target = .home
            dp = true
            res.why = "Bases loaded with less than 2 outs — get the force at home to stop the run. The catcher then throws to 1st for a double play."
        } else if f2 {
            target = .second
            dp = true
            res.why = "Runner on 1st with less than 2 outs — turn two! Get the lead runner at 2nd, then throw to 1st."
        } else {
            target = .first
            res.why = r2 || r3
                ? "The only force play is at 1st. Look the runner back to their base first (freeze them with your eyes), then throw to 1st."
                : "Nobody on base — field it cleanly and throw the batter out at 1st."
        }
        res.target = target
        res.dp = dp
        res.rules += [outs == 2 ? "G1" : fH ? "G3" : f2 ? "G2" : "G4", "G5"]
        if F == .first || F == .second { res.rules.append("G6") }
        if F == .third && r2 { res.rules.append("G7") }
        if !r2 && !r3 { res.rules.append("G8") }
        res.rules.append("G9")
        if anyRunners { res.rules.append("G10") }

        let tName = target.name
        let cov = infieldCoverer(target, F)
        let selfPlay = cov == F
        var fieldJob = selfPlay ? "Field it and step on \(tName) yourself" : "Field the grounder and throw \(target.throwPhrase)"
        if dp { fieldJob += " — start the double play!" }
        set(F, selfPlay ? G.coverPt(target) : ball, fieldJob, .field)

        res.throwPath = [ball, B(target)]
        res.carry = selfPlay
        if !selfPlay {
            set(cov, G.coverPt(target), dp ? "Cover \(tName), get the force, then throw to 1st" : "Cover \(tName) and catch the throw", .cover)
        }
        if dp { res.throwPath.append(B(.first)) }

        let c1: Position = F == .first ? .p : .first
        set(c1, G.coverPt(.first), F == .first ? "Sprint over and cover 1st base!" : "Cover 1st base", .cover)
        set(infieldCoverer(.second, F), G.coverPt(.second), "Cover 2nd base", .cover)
        if F == .third {
            if r2 { set(.ss, G.coverPt(.third), "Cover 3rd — the third baseman left the bag", .cover) }
            else { set(.ss, beyond(B(.home), ball, 22 * K), "Back up the third baseman", .backup) }
        } else {
            set(.third, G.coverPt(.third), "Cover 3rd base", .cover)
        }

        if !r2 && !r3 { set(.c, beyond(ball, B(.first), 18 * K), "Run down the line and back up the throw to 1st", .backup) }
        else { set(.c, G.coverPt(.home), "Stay home — protect the plate", .cover) }

        if F == .second { set(.p, along(home(.p), B(.first), 40 * K), "Break toward 1st on any ball hit to your left", .other) }
        set(.p, along(home(.p), B(target), 12 * K), "Get off the mound and be ready to help", .other)

        if F == .first { set(.second, along(home(.second), B(.first), 45 * K), "Move toward 1st in case the pitcher is late", .other) }
        if F == .p { set(.second, beyond(ball, B(.second), 18 * K), "Back up the shortstop at 2nd", .backup) }

        let p = res.throwPath
        let src1 = p[p.count - 1] == B(.first) ? p[p.count - 2] : ball
        set(.rf, beyond(src1, B(.first), 42 * K), "Back up 1st base in case of an overthrow", .backup)
        set(.cf, along(B(.second), home(.cf), 45 * K),
            [.p, .ss, .second].contains(F) ? "Charge in — back up the ball up the middle and 2nd base" : "Back up 2nd base", .backup)
        if F == .third || F == .ss { set(.lf, beyond(B(.home), ball, 55 * K), "Charge in and back up the \(F.name.lowercased())", .backup) }
        else { set(.lf, beyond(ball, B(.third), 40 * K), "Back up 3rd base", .backup) }

        // Runners
        res.runners.append(RunnerMove(id: "B", from: .home, to: .first))
        if r1 { res.runners.append(RunnerMove(id: "R1", from: .first, to: .second)) }
        if r2 {
            let go = f3 || outs == 2 || F == .first || F == .second
            res.runners.append(RunnerMove(id: "R2", from: .second, to: go ? .third : .second, note: go ? "" : "Holds — ball hit in front of them"))
        }
        if r3 {
            let go = fH || outs == 2
            res.runners.append(RunnerMove(id: "R3", from: .third, to: go ? .home : .third, note: go ? "" : "Holds — not forced"))
        }

        res.headline = selfPlay ? "Step on \(tName)!" : dp ? "Throw \(target.throwPhrase), then 1st — double play!" : "Throw \(target.throwPhrase)!"
        if r3 && !fH && outs < 2 { res.tips.append("If the infield is playing in to stop the run, throw home to get the runner from 3rd instead.") }
        if F == .first && target == .first { res.tips.append("If you are close to the bag, just step on it yourself. If not, flip to the pitcher covering.") }
        if dp && G.level == .ll { res.tips.append("Little League double plays are hard — the must-have out is the lead runner. Get that one first, then try for two.") }
        if outs == 2 { res.tips.append("With 2 outs, every runner takes off on contact.") }
    }

    // MARK: - Outfield throws

    enum OFKind { case fly, single, gap }

    // Ball in front of the outfielder: one cutoff man lines up. Ball past them
    // (gap/wall): a relay man goes out, plus a trail man on big fields.
    @discardableResult
    func ofPlay(_ F: Position, _ src: Pt, _ target: Base, doThrow: Bool, kind: OFKind, relay: Bool = false) -> Pt {
        let T = B(target)
        let d = src.distance(to: T)
        if relay {
            let left = src.x <= 0
            let lead: Position = left ? .ss : .second
            let other: Position = left ? .second : .ss
            let trail = G.doubleCut
            let leadPt = along(src, T, 0.4 * d)
            set(lead, leadPt, "Relay man — run out toward the ball, arms up, and yell!", .cutoff)
            if trail { set(other, along(leadPt, T, 32 * K), "Trail the relay man by ~30 feet — catch a bad throw and yell where it goes", .cutoff) }
            set(.c, G.coverPt(.home), "Cover home", .cover)
            if target == .home {
                // 1B is the cutoff in front of home on every field size — it can cut the
                // relay throw and get the batter trying to take an extra base.
                let cut = along(B(.home), leadPt, 48 * K)
                set(.first, cut, "Watch the batter touch 1st, then hustle to the cutoff spot in front of home", .cutoff)
                if !trail { set(other, G.coverPt(.second), "Cover 2nd base", .cover) }
                res.throwPath = [src, leadPt, cut, B(.home)]
                set(.third, G.coverPt(.third), "Cover 3rd base", .cover)
                let split = beyond(Pt(0, G.level.bases / 2.0.squareRoot()), B(.third) * 0.5, 30 * K)
                set(.p, split, "Go halfway between 3rd and home in foul territory — read the throw, then back up that base", .backup)
            } else {
                set(.third, G.coverPt(.third), "Cover 3rd — keep the batter from a triple", .cover)
                if trail {
                    set(.first, G.coverPt(.second), "Watch the batter touch 1st, then follow them to 2nd and cover it (both middle infielders are out on the relay)", .cover)
                } else {
                    set(other, G.coverPt(.second), "Cover 2nd base", .cover)
                    set(.first, along(along(B(.first), B(.second), 0.55 * G.level.bases), G.mound, 6 * K),
                        "Watch the batter touch 1st, then trail them toward 2nd — be ready to help in a rundown", .other)
                }
                set(.p, beyond(leadPt, T, 28 * K), "Back up \(target.name) base", .backup)
                res.throwPath = [src, leadPt, T]
            }
            res.target = target
            return leadPt
        }

        let cut: Pt
        switch target {
        case .home:
            cut = along(B(.home), src, 48 * K)
            if F == .lf {
                set(.third, cut, "Cutoff for the throw home — line up between the ball and home", .cutoff)
                set(.ss, G.coverPt(.third), "Cover 3rd (the third baseman is the cutoff)", .cover)
                set(.second, G.coverPt(.second), "Cover 2nd base", .cover)
                set(.first, G.coverPt(.first), "Cover 1st — make sure the batter touches the bag", .cover)
            } else {
                set(.first, cut, "Cutoff for the throw home — line up between the ball and home", .cutoff)
                set(.second, G.coverPt(.first), "Cover 1st (the first baseman is the cutoff)", .cover)
                set(.ss, G.coverPt(.second), "Cover 2nd base", .cover)
                set(.third, G.coverPt(.third), "Cover 3rd base", .cover)
            }
            set(.c, G.coverPt(.home), "Cover home — yell \"Cut!\" or let it come through", .cover)
            set(.p, beyond(cut, B(.home), 26 * K), "Back up home plate", .backup)
        case .third:
            cut = along(T, src, min(60 * K, 0.45 * d))
            set(.ss, cut, "Cutoff for the throw to 3rd — line up and raise your arms", .cutoff)
            set(.third, G.coverPt(.third), "Cover 3rd and catch the throw", .cover)
            set(.second, G.coverPt(.second), "Cover 2nd base", .cover)
            set(.first, G.coverPt(.first), "Cover 1st — make sure the batter touches the bag", .cover)
            set(.p, beyond(cut, T, 28 * K), "Back up 3rd base", .backup)
            set(.c, G.coverPt(.home), "Cover home", .cover)
        default:
            let cutter: Position = F == .rf ? .second : .ss
            let cov: Position = cutter == .second ? .ss : .second
            cut = along(T, src, min(50 * K, 0.4 * d))
            set(cutter, cut, doThrow ? "Go out toward the ball — be the cutoff for the throw to 2nd" : "Go out toward the ball in case it gets dropped", .cutoff)
            set(cov, G.coverPt(.second), "Cover 2nd base", .cover)
            set(.first, G.coverPt(.first), "Cover 1st — make sure the batter touches the bag", .cover)
            set(.third, G.coverPt(.third), "Cover 3rd base", .cover)
            set(.p, beyond(cut, T, 24 * K), "Back up the throw to 2nd", .backup)
            if kind == .single && !anyRunners { set(.c, Pt(74, 50) * K, "Follow the batter down the line — back up 1st", .backup) }
            set(.c, G.coverPt(.home), "Cover home", .cover)
        }
        if doThrow {
            res.throwPath = [src, cut, T]
            res.target = target
        }
        return cut
    }

    func outfieldBackups(_ F: Position, _ ball: Pt) {
        func behind(_ o: Position) -> Pt {
            var p = ball + ball.unit * (25 * K)
            p = p + (home(o) - ball).unit * (16 * K)
            return G.inFence(p, 8 * G.dot)
        }
        switch F {
        case .cf:
            set(.lf, behind(.lf), "Back up the center fielder", .backup)
            set(.rf, behind(.rf), "Back up the center fielder", .backup)
        case .lf:
            set(.cf, behind(.cf), "Back up the left fielder", .backup)
            set(.rf, beyond(ball, B(.second), 30 * K), "Back up 2nd — line up behind the bag on the throw from left", .backup)
            if res.target != .second { res.altThrows.append([ball, B(.second)]) }
        case .rf:
            set(.cf, behind(.cf), "Back up the right fielder", .backup)
            if res.target == .second {
                set(.lf, beyond(ball, B(.second), 30 * K), "Come in behind 2nd — back up the throw from right", .backup)
            } else {
                set(.lf, beyond(ball, B(.third), 35 * K), "Come in and back up 3rd base", .backup)
                if res.target != .third { res.altThrows.append([ball, B(.third)]) }
            }
        default: break
        }
    }

    // MARK: - Fly balls (caught)

    func fly(_ ball: Pt) {
        let F = hit.fielder!
        res.rules += ["S7", "S8"]
        let batterOut = RunnerMove(id: "B", from: .home, to: .first, out: true, endPt: along(B(.home), B(.first), 0.55 * G.level.bases))
        if outs == 2 {
            set(F, ball, "Catch it — that's the 3rd out!", .field)
            res.headline = "Catch it — inning over!"
            res.why = "Two outs: runners take off on contact, but a catch ends the inning. Everyone else still backs up and covers — just in case it's dropped."
            ofPlay(F, ball, .second, doThrow: false, kind: .fly)
            res.runners.append(batterOut)
            if r1 { res.runners.append(RunnerMove(id: "R1", from: .first, to: .second)) }
            if r2 { res.runners.append(RunnerMove(id: "R2", from: .second, to: .third)) }
            if r3 { res.runners.append(RunnerMove(id: "R3", from: .third, to: .home)) }
        } else {
            let r2tags = r2 && F != .lf
            let target: Base = r3 ? .home : r2tags ? .third : .second
            res.rules.append("S6")
            if target == .home { res.rules.append("S4") }
            set(F, ball, "Catch it, then throw \(target.throwPhrase) — hit the cutoff man", .field)
            res.headline = "Catch it, throw \(target.throwPhrase)!"
            switch target {
            case .home: res.why = "Less than 2 outs with a runner on 3rd — they will TAG UP and try to score after the catch. Catch it moving toward home and throw through the cutoff."
            case .third: res.why = "The runner on 2nd can tag up and take 3rd on a fly to center or right. Throw to 3rd through the cutoff."
            default: res.why = "After the catch, get the ball back to the infield quickly — throw to 2nd so nobody sneaks an extra base."
            }
            ofPlay(F, ball, target, doThrow: true, kind: .fly)
            res.runners.append(batterOut)
            if r1 { res.runners.append(RunnerMove(id: "R1", from: .first, to: .first, note: "Tags up and holds")) }
            if r2 { res.runners.append(RunnerMove(id: "R2", from: .second, to: r2tags ? .third : .second, note: r2tags ? "Tags up, goes to 3rd" : "Tags up and holds")) }
            if r3 { res.runners.append(RunnerMove(id: "R3", from: .third, to: .home, note: "Tags up and tries to score")) }
            res.tips.append("Runners: on a fly ball with less than 2 outs, go back and TAG your base. Leave when the ball is caught.")
        }
        outfieldBackups(F, ball)
    }

    // MARK: - Singles

    func single(_ ball: Pt) {
        let F = hit.fielder!
        let r1to: Base = F == .lf ? .second : .third
        let target: Base = r2 ? .home : r1 ? r1to : .second
        res.rules.append(target == .home ? "S4" : target == .third ? "S2" : r1 ? "S3" : "S1")
        if !anyRunners { res.rules.append("S5") }
        res.rules += ["S7", "S8"]
        let holdAt2 = F == .lf && r1 && !r2
        if holdAt2 {
            set(F, ball, "Charge the ball — throw to 2nd, or to 3rd through the cutoff only if it’s a sure out", .field)
            res.headline = "Throw to 2nd — unless there’s a sure out at 3rd"
        } else {
            set(F, ball, "Charge the ball and throw \(target.throwPhrase) — hit the cutoff man", .field)
            res.headline = "Throw \(target.throwPhrase) through the cutoff!"
        }
        if target == .home {
            res.why = "The runner from 2nd will try to score. Throw home through the cutoff — if there's no play at home, the cutoff catches it and gets the batter trying for 2nd."
        } else if target == .third {
            res.why = "The runner from 1st will try to go first-to-third. Throw to 3rd through the shortstop (the cutoff) to stop them."
        } else if r1 {
            res.why = "On a single to left, the runner from 1st usually stops at 2nd. The shortstop still lines up to 3rd in case they go — but unless you have a sure out at 3rd, throw to 2nd to keep the batter at 1st."
        } else if r3 {
            res.why = "The runner from 3rd scores easily — don't waste a throw home. Throw to 2nd to keep the batter at 1st."
        } else {
            res.why = "Nobody in scoring position. Throw to 2nd to keep the batter at 1st — no extra bases!"
        }
        if holdAt2 {
            let cut = ofPlay(F, ball, .third, doThrow: false, kind: .single)
            res.throwPath = [ball, B(.second)]
            res.target = .second
            res.altThrows.append([ball, cut, B(.third)])
        } else {
            ofPlay(F, ball, target, doThrow: true, kind: .single)
        }
        outfieldBackups(F, ball)
        res.runners.append(RunnerMove(id: "B", from: .home, to: .first, note: "Rounds 1st, looks to take 2nd on a throw home"))
        if r1 { res.runners.append(RunnerMove(id: "R1", from: .first, to: r1to)) }
        if r2 { res.runners.append(RunnerMove(id: "R2", from: .second, to: .home)) }
        if r3 { res.runners.append(RunnerMove(id: "R3", from: .third, to: .home)) }
        res.tips.append("Outfielders: throw it low and hard to the cutoff man’s chest — never to the wrong base.")
    }

    // MARK: - Gap doubles

    func gap(_ ball: Pt) {
        let left = hit.leftSide
        let corner: Position = left ? .lf : .rf
        let target: Base = anyRunners ? .home : .third
        res.rules += ["R1", "R2", target == .home ? "R3" : "R4", "R5", "S8"]

        set(.cf, ball, "Chase it down and throw to the relay man", .field)
        // Back up from the side (the ball is near the fence, so there's no room behind).
        let side = along(ball, home(corner), 24 * G.dot)
        set(corner, G.inFence(side + ball.unit * (6 * G.dot), 8 * G.dot), "Back up the center fielder", .backup)
        let leadPt = ofPlay(.cf, ball, target, doThrow: true, kind: .gap, relay: true)
        if left {
            set(.rf, beyond(leadPt, B(.second), 30 * K), "Back up 2nd — line up behind the bag in case the relay man throws behind the batter (dotted line)", .backup)
            res.altThrows.append([leadPt, B(.second)])
        } else {
            set(.lf, beyond(leadPt, B(.third), 38 * K), "Come in and back up 3rd base", .backup)
            if target != .third { res.altThrows.append([leadPt, B(.third)]) }
        }

        if target == .home {
            res.headline = "Relay it home!"
            res.why = "Runners will try to score on a ball in the gap. Use the relay: outfielder → relay man → home. Two short, strong throws beat one long, bouncing one."
        } else {
            res.headline = "Relay it to 3rd!"
            res.why = "Nobody on, so the batter is thinking triple. Relay the ball to 3rd to hold them at 2nd."
        }
        if G.doubleCut {
            res.tips.append("Big field = double cut. The relay man lines up with the outfielder, and the trail man ~30 feet behind shouts \"Home! Home!\" or \"Three! Three!\"")
        } else {
            res.tips.append("Small field = one relay man is enough — no trail man. The other middle infielder stays at 2nd so the batter can’t just walk into it.")
        }

        res.runners.append(RunnerMove(id: "B", from: .home, to: .second))
        if r1 { res.runners.append(RunnerMove(id: "R1", from: .first, to: .home)) }
        if r2 { res.runners.append(RunnerMove(id: "R2", from: .second, to: .home)) }
        if r3 { res.runners.append(RunnerMove(id: "R3", from: .third, to: .home)) }
    }

    // MARK: - Bunts

    func bunt(_ ball: Pt) {
        // Runner on 2nd: 3B holds near the bag for a play at 3rd; pitcher takes the 3B-line bunt.
        let thirdStays = r2
        let F: Position = thirdStays ? .p : .third
        res.rules.append("B1")
        if thirdStays { res.rules.append(r1 ? "B2" : "B3") }
        res.rules.append("B4")
        set(F, ball, "Field the bunt and throw to 1st for the sure out", .field)
        set(.first, Pt(36, 40) * K, "Charge the bunt — then get out of the way", .other)
        set(.second, G.coverPt(.first), "Cover 1st base! (1B is charging)", .cover)
        if thirdStays {
            set(.third, G.coverPt(.third), r1 ? "Read the bunt — if the pitcher can get it, stay at 3rd for the force" : "Read the bunt — if the pitcher can get it, stay at 3rd for the tag play", .cover)
            set(.ss, G.coverPt(.second), "Cover 2nd base", .cover)
        } else {
            set(.p, Pt(12, 34) * K, "Come off the mound — field it if it comes to you", .other)
            set(.ss, G.coverPt(.second), "Cover 2nd base", .cover)
        }
        set(.c, G.coverPt(.home), "Yell who should field it, then cover home", .cover)
        set(.rf, beyond(ball, B(.first), 42 * K), "Back up 1st base", .backup)
        set(.cf, along(B(.second), home(.cf), 40 * K), "Back up 2nd base", .backup)
        set(.lf, beyond(B(.home), B(.third), 35 * K), "Back up 3rd base", .backup)

        res.throwPath = [ball, B(.first)]
        res.target = .first
        res.headline = "Get the sure out at 1st!"
        res.why = "On a bunt, the corners crash in and someone MUST cover 1st (the second baseman). Unless you have an easy play on the lead runner, take the out at 1st."
        if r3 && outs < 2 { res.tips.append("Runner on 3rd — watch for the squeeze! If they break for home, flip it to the catcher.") }

        res.runners.append(RunnerMove(id: "B", from: .home, to: .first))
        if r1 { res.runners.append(RunnerMove(id: "R1", from: .first, to: .second)) }
        if r2 { res.runners.append(RunnerMove(id: "R2", from: .second, to: .third)) }
        if r3 { res.runners.append(RunnerMove(id: "R3", from: .third, to: .home)) }
    }
}
