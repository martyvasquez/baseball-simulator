import Foundation
import Observation

/// App state: the situation being set up, the answer once revealed, and quiz mode.
@Observable
@MainActor
final class SimulatorModel {
    /// Length of the reveal animation, in milliseconds.
    nonisolated static let playDuration = 3600.0
    /// When the thrown ball reaches its target during the animation.
    nonisolated static let throwArrival = 3300.0

    var situation: Situation {
        didSet {
            guard oldValue != situation else { return }
            if oldValue.level != situation.level { UserDefaults.standard.set(situation.level.rawValue, forKey: "level") }
            guess = nil
            reset()
        }
    }

    private(set) var solution: Solution?
    /// Where the play is, in milliseconds (as of `anchorDate` while playing).
    private(set) var playhead = 0.0
    private(set) var isPlaying = false
    private var anchorDate: Date?
    /// Playback speed: 1 = normal, 0.25 = quarter speed.
    private(set) var speed: Double
    /// Bumped when a throw lands, to fire a haptic.
    private(set) var throwLandings = 0
    private var playID = 0

    static let speeds: [Double] = [0.25, 0.5, 1, 2]

    /// Quiz mode: the position the kid is playing.
    var focus: Position? {
        didSet {
            if solution == nil { guess = nil }
        }
    }

    /// Quiz mode: where the kid thinks their player should go.
    var guess: Pt?

    init() {
        let saved = UserDefaults.standard.string(forKey: "level").flatMap(Level.init(rawValue:)) ?? .ll
        situation = Situation(level: saved)
        let savedSpeed = UserDefaults.standard.double(forKey: "speed")
        speed = Self.speeds.contains(savedSpeed) ? savedSpeed : 1
    }

    var revealed: Bool { solution != nil }
    var isGuessing: Bool { focus != nil && !revealed }
    var isAnimating: Bool { isPlaying }
    var field: Field { Field.of(situation.level) }

    /// Milliseconds into the play, or nil before the play is revealed.
    func elapsed(at date: Date) -> Double? {
        guard revealed else { return nil }
        guard isPlaying, let anchorDate else { return playhead }
        return min(Self.playDuration, playhead + date.timeIntervalSince(anchorDate) * 1000 * speed)
    }

    /// Solve the situation and play it from the start.
    func reveal() {
        solution = Engine.solve(situation)
        playhead = 0
        play()
    }

    func play() {
        guard revealed else { return }
        if playhead >= Self.playDuration { playhead = 0 }
        anchorDate = .now
        isPlaying = true
        schedule()
    }

    func pause() {
        guard isPlaying else { return }
        playhead = elapsed(at: .now) ?? 0
        isPlaying = false
        anchorDate = nil
        playID += 1
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    /// Jump to a point in the play (pauses playback).
    func scrub(to ms: Double) {
        pause()
        playhead = min(Self.playDuration, max(0, ms))
    }

    func step(by ms: Double) {
        scrub(to: (elapsed(at: .now) ?? 0) + ms)
    }

    func setSpeed(_ newSpeed: Double) {
        let now = elapsed(at: .now) ?? 0
        speed = newSpeed
        UserDefaults.standard.set(newSpeed, forKey: "speed")
        if isPlaying {
            playhead = now
            anchorDate = .now
            schedule()
        }
    }

    /// Fire the throw haptic and stop at the end, timed for the current speed.
    private func schedule() {
        playID += 1
        let id = playID
        let start = playhead
        let rate = speed
        let hasThrow = (solution?.throwPath.count ?? 0) > 1
        Task { @MainActor in
            var at = start
            if hasThrow && start < Self.throwArrival {
                try? await Task.sleep(for: .milliseconds(Int((Self.throwArrival - start) / rate)))
                guard id == playID else { return }
                throwLandings += 1
                at = Self.throwArrival
            }
            try? await Task.sleep(for: .milliseconds(Int((Self.playDuration - at) / rate)))
            guard id == playID else { return }
            playhead = Self.playDuration
            isPlaying = false
            anchorDate = nil
        }
    }

    /// What's happening at a point in the play, for the scrubber label.
    static func phase(at ms: Double) -> String {
        switch ms {
        case ..<750: "Ball in play"
        case ..<1900: "Everyone moves"
        case ..<playDuration: "The throw"
        default: "Done"
        }
    }

    func reset() {
        playID += 1
        solution = nil
        playhead = 0
        isPlaying = false
        anchorDate = nil
    }

    func toggleRunner(_ base: Int) {
        situation.runners[base - 1].toggle()
    }

    func randomize() {
        var s = situation
        s.runners = (0..<3).map { _ in Double.random(in: 0..<1) < 0.4 }
        s.outs = Int.random(in: 0...2)
        s.hitID = Hit.all.randomElement()!.id
        situation = s
    }

    func toggleFocus(_ p: Position) {
        focus = focus == p ? nil : p
    }

    // MARK: - Quiz grading

    enum Grade {
        case rightOn, close, notQuite

        var title: String {
            switch self {
            case .rightOn: "Right on!"
            case .close: "Close!"
            case .notQuite: "Not quite — watch where you go."
            }
        }

        var symbol: String {
            switch self {
            case .rightOn: "target"
            case .close: "hand.thumbsup.fill"
            case .notQuite: "arrow.triangle.turn.up.right.circle"
            }
        }
    }

    var grade: Grade? {
        guard let focus, let guess, let a = solution?.assignments[focus] else { return nil }
        // Allow more slop on bigger fields.
        let tol = 25 * (situation.level.center / 300)
        let d = guess.distance(to: a.to)
        return d < tol ? .rightOn : d < 2.2 * tol ? .close : .notQuite
    }

    // MARK: - Text

    var runnersText: String {
        let on = (1...3).filter { situation.on($0) }
        if on.isEmpty { return "Bases empty" }
        if on.count == 3 { return "Bases loaded" }
        let names = on.map { [Base.first, .second, .third][$0 - 1].name }.joined(separator: " & ")
        return "Runner\(on.count > 1 ? "s" : "") on \(names)"
    }
}
