import Foundation
import Testing
@testable import SituationSim

@MainActor
struct PlaybackTests {
    @Test func scrubbingPausesAndHoldsPosition() {
        let m = SimulatorModel()
        m.reveal()
        #expect(m.isPlaying)
        m.scrub(to: 1500)
        #expect(!m.isPlaying)
        #expect(m.elapsed(at: .now.addingTimeInterval(5)) == 1500)
    }

    @Test func speedScalesTime() {
        let m = SimulatorModel()
        m.reveal()
        m.scrub(to: 0)
        m.setSpeed(0.5)
        m.play()
        let t = m.elapsed(at: .now.addingTimeInterval(1))!
        #expect(abs(t - 500) < 50)
        m.setSpeed(1)
    }

    @Test func playAtTheEndStartsOver() {
        let m = SimulatorModel()
        m.reveal()
        m.scrub(to: SimulatorModel.playDuration)
        m.play()
        #expect(m.elapsed(at: .now)! < 100)
    }

    @Test func scrubIsClamped() {
        let m = SimulatorModel()
        m.reveal()
        m.scrub(to: -500)
        #expect(m.elapsed(at: .now) == 0)
        m.scrub(to: 99_999)
        #expect(m.elapsed(at: .now) == SimulatorModel.playDuration)
    }

    @Test func changingTheSituationClearsThePlay() {
        let m = SimulatorModel()
        m.reveal()
        m.toggleRunner(1)
        #expect(!m.revealed)
        #expect(m.elapsed(at: .now) == nil)
    }
}
