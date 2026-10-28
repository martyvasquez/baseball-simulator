import Foundation
import Observation

/// Questions and answers about one situation. A new situation starts a new chat (`SimulatorModel` replaces it);
/// replaying the same play keeps it.
@Observable
@MainActor
final class PlayChat {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: LLMMessage.Role
        var text: String
    }

    let situation: Situation
    private(set) var messages: [Message] = []
    private(set) var isAnswering = false
    var error: String?
    private var task: Task<Void, Never>?

    init(situation: Situation) {
        self.situation = situation
    }

    /// Ready-made questions for a kid who doesn't know what to ask.
    static let starters = [
        "Why does the ball go there?",
        "What would happen if we threw somewhere else?",
        "What's the hardest job on this play?",
    ]

    func ask(_ raw: String, about solution: Solution, focus: Position?, grade: SimulatorModel.Grade?, client: any LLMClient = AIService.shared.client()) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        error = nil
        messages.append(Message(role: .user, text: question))
        let history = messages.map { LLMMessage($0.role, $0.text) }
        let request = LLMRequest(model: AIService.shared.modelID,
                                 system: Self.instructions + "\n\n" + Self.context(situation, solution, focus: focus, grade: grade),
                                 messages: history)
        messages.append(Message(role: .assistant, text: ""))
        let replyID = messages[messages.count - 1].id
        isAnswering = true
        task = Task {
            defer { isAnswering = false; task = nil }
            do {
                let reply = try await client.complete(request) { text in
                    Task { @MainActor in self.update(replyID, text) }
                }
                update(replyID, reply)
            } catch {
                // Take back the question too, so it can be asked again without a gap in the chat.
                messages.removeAll { $0.id == replyID }
                if messages.last?.role == .user { messages.removeLast() }
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func update(_ id: UUID, _ text: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }), messages[i].text.count <= text.count else { return }
        messages[i].text = text
    }

    // MARK: - What ChatGPT is told

    static let instructions = """
    You are a friendly, patient baseball coach in an app that teaches young players (about 8 to 14 years old) where \
    to go and what to do on defense. A parent and their kid just watched the play below on the app's field diagram, \
    and they're asking you about it.

    How to answer:
    - The play below is what the app teaches. Explain it and the reasons behind it; don't change or contradict it. \
    If a source note says coaches handle part of it differently, you can say so honestly.
    - Use simple words a kid understands. Keep answers short: usually two to five sentences. Use a short list only \
    when steps happen in order.
    - Talk about this play. For "what if" questions (a different hit, runner, or number of outs), say what usually \
    changes, and suggest setting that situation up in the app to see it.
    - Don't make up rules. If you're not sure, or it depends on the league, say so and suggest asking their coach.
    - If the question isn't about baseball, kindly bring it back to the play.
    - Write plain text. No markdown headings or tables.
    """

    /// The situation and the app's answer, in words.
    static func context(_ s: Situation, _ solution: Solution, focus: Position?, grade: SimulatorModel.Grade?) -> String {
        var lines: [String] = []
        lines.append("THE SITUATION")
        lines.append("Field: \(s.level.name) (\(s.level.detail))")
        lines.append("Outs: \(s.outs)")
        let on = (1...3).filter { s.on($0) }.map { [Base.first, .second, .third][$0 - 1].name }
        lines.append("Runners: \(on.isEmpty ? "none" : on.joined(separator: ", "))")
        lines.append("The ball: \(s.hit.text)")
        lines.append("")
        lines.append("WHAT THE APP SHOWS")
        lines.append("Main idea: \(solution.headline)")
        lines.append("Why: \(solution.why)")
        for tip in solution.tips { lines.append("Tip: \(tip)") }
        if let target = solution.target { lines.append("The throw goes \(target.throwPhrase).") }
        if solution.dp { lines.append("It's a double-play chance.") }
        lines.append("")
        lines.append("Each fielder's job:")
        for p in Position.allCases {
            guard let a = solution.assignments[p] else { continue }
            lines.append("- \(p.name) (\(p.label)), \(jobKind(a.type)): \(a.job)")
        }
        lines.append("")
        lines.append("Runners:")
        for m in solution.runners {
            lines.append("- \(m.id == "B" ? "Batter" : "Runner on \(m.from.name)"): \(m.summary)")
        }
        let notes = solution.rules.compactMap { SourceNotes.shared.notes[$0] }
        if !notes.isEmpty {
            lines.append("")
            lines.append("Where the app's rules come from (checked against published coaching sources):")
            for n in notes { lines.append("- \(n.rule) [\(n.verdict.label)]: \(n.note)") }
        }
        if let focus, let a = solution.assignments[focus] {
            lines.append("")
            lines.append("The kid is practicing the \(focus.name) position. Their job: \(a.job)")
            if let grade {
                let result = switch grade {
                case .rightOn: "right on"
                case .close: "close, but not quite"
                case .notQuite: "in the wrong spot"
                }
                lines.append("Before watching, they guessed where to go and were \(result).")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func jobKind(_ t: JobType) -> String {
        switch t {
        case .field: "fields the ball"
        case .cover: "covers a base"
        case .cutoff: "cutoff/relay"
        case .backup: "backs up"
        case .other: "other"
        }
    }
}

extension RunnerMove {
    /// "Goes to 2nd — tags up", in words.
    var summary: String {
        if out { return "Out when the ball is caught" }
        if to == from { return note.isEmpty ? "Stays" : note }
        let go = to == .home ? "Heads home" : "Goes to \(to.name)"
        return note.isEmpty ? go : "\(go) — \(note)"
    }
}
