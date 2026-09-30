import SwiftUI

/// The answer: what to do and why, everyone's job, the runners, and where the rules come from.
struct AnswerPanel: View {
    @Bindable var model: SimulatorModel

    var body: some View {
        List {
            if let s = model.solution {
                answer(s)
            } else {
                thinkFirst
            }
        }
        .listStyle(.insetGrouped)
        .animation(.snappy, value: model.revealed)
        .animation(.snappy, value: model.focus)
    }

    // MARK: - Before the play

    @ViewBuilder private var thinkFirst: some View {
        if let f = model.focus {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("You're the \(f.name)", systemImage: "person.fill.questionmark")
                        .font(.headline)
                    Text(model.guess == nil
                         ? "Drag on the field to where you should go when the ball is hit."
                         : "Guess placed! Drag to move it, or tap Show Me.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        Section("Think first") {
            step(1, "How many outs?", model.situation.outs == 2 ? "Two — just get one out!" : "Less than two.")
            step(2, "Where are the runners?", "Is there a force play?")
            step(3, "If the ball is hit to me,", "where do I throw? If it's not, where do I go — cover a base, back someone up, or be the cutoff?")
        }
        Section("Key") { legend }
    }

    private func step(_ n: Int, _ bold: String, _ rest: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "\(n).circle.fill")
                .foregroundStyle(.tint)
                .font(.title3)
            (Text(bold).bold() + Text(" " + rest))
        }
        .padding(.vertical, 2)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([JobType.field, .cover, .cutoff, .backup], id: \.self) { t in
                HStack(spacing: 12) {
                    PositionBadge(label: "", ring: Theme.color(t), size: 20)
                    Text(Theme.label(t))
                }
            }
            HStack(spacing: 12) {
                PositionBadge(label: "", ring: .white, fill: Theme.runner, size: 20)
                Text("Runner")
            }
            HStack(spacing: 12) {
                Capsule().fill(Theme.field).frame(width: 20, height: 3)
                Text("Throw")
            }
            HStack(spacing: 12) {
                HStack(spacing: 3) { ForEach(0..<4) { _ in Circle().fill(.secondary).frame(width: 3, height: 3) } }
                    .frame(width: 20)
                Text("Possible throw — what a backup lines up with")
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    // MARK: - The answer

    @ViewBuilder private func answer(_ s: Solution) -> some View {
        if let f = model.focus, let a = s.assignments[f] {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let g = model.grade {
                        Label(g.title, systemImage: g.symbol)
                            .font(.title3.bold())
                            .foregroundStyle(g == .notQuite ? AnyShapeStyle(.orange) : AnyShapeStyle(.green))
                    }
                    (Text("\(f.name): ").bold() + Text(a.job))
                }
                .padding(.vertical, 4)
            }
        }

        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(s.headline)
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(Theme.field)
                Text(s.why)
                ForEach(s.tips, id: \.self) { tip in
                    Label(tip, systemImage: "lightbulb")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }

        Section("Everyone's job") {
            ForEach(Position.allCases) { p in
                let a = s.assignments[p]!
                Button {
                    model.toggleFocus(p)
                } label: {
                    HStack(spacing: 12) {
                        PositionBadge(label: p.label, ring: Theme.color(a.type))
                        Text(a.job).foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(model.focus == p ? Theme.field.opacity(0.18) : nil)
                .accessibilityLabel("\(p.name): \(a.job)")
                .accessibilityAddTraits(model.focus == p ? .isSelected : [])
            }
        }

        Section("Runners") {
            ForEach(s.runners) { m in
                HStack(spacing: 12) {
                    PositionBadge(label: m.id, ring: .white, fill: Theme.runner)
                    (Text(m.id == "B" ? "Batter: " : "Runner on \(m.from.name): ").bold() + Text(runnerText(m)))
                }
            }
        }

        let notes = s.rules.compactMap { id in SourceNotes.shared.notes[id].map { (id, $0) } }
        if !notes.isEmpty {
            Section {
                DisclosureGroup("Where this comes from (\(notes.count))") {
                    ForEach(notes, id: \.0) { _, n in SourceRow(note: n) }
                }
            }
        }
    }

    private func runnerText(_ m: RunnerMove) -> String {
        if m.out { return "Out when the ball is caught" }
        if m.to == m.from { return m.note.isEmpty ? "Stays" : m.note }
        let go = m.to == .home ? "Heads home" : "Goes to \(m.to.name)"
        return m.note.isEmpty ? go : "\(go) — \(m.note)"
    }
}

struct SourceRow: View {
    let note: SourceNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.verdict.label)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.color(note.verdict).opacity(0.25), in: .capsule)
                .foregroundStyle(Theme.color(note.verdict))
            Text(note.rule).font(.subheadline.bold())
            Text(note.note).font(.footnote).foregroundStyle(.secondary)
            ForEach(note.links, id: \.self) { link in
                if let url = URL(string: link.url) {
                    Link(destination: url) {
                        Label(link.name, systemImage: "arrow.up.right.square")
                            .font(.footnote)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
