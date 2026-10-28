import Foundation
import Testing
@testable import SituationSim

@MainActor
struct PlayChatTests {
    /// Answers with a fixed reply and keeps the request it was sent.
    final class Scripted: LLMClient, @unchecked Sendable {
        let reply: Result<String, Error>
        private(set) var requests: [LLMRequest] = []

        init(_ reply: Result<String, Error>) { self.reply = reply }

        func complete(_ request: LLMRequest, onText: @escaping @Sendable (String) -> Void) async throws -> String {
            requests.append(request)
            let text = try reply.get()
            onText(String(text.prefix(3)))
            return text
        }
    }

    func waitForAnswer(_ chat: PlayChat) async {
        for _ in 0..<200 where chat.isAnswering { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func contextDescribesTheSituationAndEveryJob() {
        let s = Situation(level: .hs, hitID: "gap_LC", outs: 1, runners: [true, false, false])
        let solution = Engine.solve(s)
        let text = PlayChat.context(s, solution, focus: .ss, grade: .close)
        #expect(text.contains("Field: High School"))
        #expect(text.contains("Outs: 1"))
        #expect(text.contains("Runners: 1st"))
        #expect(text.contains(s.hit.text))
        #expect(text.contains(solution.headline))
        for p in Position.allCases {
            #expect(text.contains("\(p.name) (\(p.label))"), "missing \(p.name)")
            #expect(text.contains(solution.assignments[p]!.job))
        }
        for id in solution.rules {
            #expect(text.contains(SourceNotes.shared.notes[id]!.note), "missing source note \(id)")
        }
        #expect(text.contains("practicing the Shortstop position"))
        #expect(text.contains("close, but not quite"))
    }

    @Test func conversationCarriesEarlierTurns() async {
        let m = SimulatorModel()
        m.reveal()
        let client = Scripted(.success("Because it's the closest out."))
        m.chat.ask("Why first?", about: m.solution!, focus: nil, grade: nil, client: client)
        await waitForAnswer(m.chat)
        m.chat.ask("And with two outs?", about: m.solution!, focus: nil, grade: nil, client: client)
        await waitForAnswer(m.chat)

        #expect(m.chat.messages.map(\.text) == ["Why first?", "Because it's the closest out.", "And with two outs?", "Because it's the closest out."])
        let last = client.requests.last!
        #expect(last.messages.map(\.role) == [.user, .assistant, .user])
        #expect(last.system.contains(m.solution!.headline))
    }

    @Test func newSituationStartsANewChatButReplayKeepsIt() async {
        let m = SimulatorModel()
        m.reveal()
        m.chat.ask("Why?", about: m.solution!, focus: nil, grade: nil, client: Scripted(.success("Because.")))
        await waitForAnswer(m.chat)
        #expect(m.chat.messages.count == 2)

        m.reveal()
        #expect(m.chat.messages.count == 2)
        m.focus = .cf
        #expect(m.chat.messages.count == 2)

        m.situation.outs = (m.situation.outs + 1) % 3
        #expect(m.chat.messages.isEmpty)
        #expect(m.chat.situation == m.situation)
    }

    @Test func failedQuestionCanBeAskedAgain() async {
        let m = SimulatorModel()
        m.reveal()
        m.chat.ask("Why?", about: m.solution!, focus: nil, grade: nil, client: Scripted(.failure(ChatGPTClient.ClientError.usageLimit)))
        await waitForAnswer(m.chat)
        #expect(m.chat.messages.isEmpty)
        #expect(m.chat.error == ChatGPTClient.ClientError.usageLimit.localizedDescription)
    }
}
