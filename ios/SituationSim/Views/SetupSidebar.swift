import SwiftUI

/// Sidebar for setting up the situation: field size, runners, outs, where the ball goes, and quiz mode.
struct SetupSidebar: View {
    @Bindable var model: SimulatorModel

    var body: some View {
        List {
            Section("Field") {
                Picker("Field size", selection: $model.situation.level) {
                    ForEach(Level.allCases) { Text($0.shortName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("\(model.situation.level.name): \(model.situation.level.detail)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 20) {
                    RunnerDiamond(runners: model.situation.runners) { model.toggleRunner($0) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.runnersText).font(.headline)
                        Text("Tap a base to put a runner on — here or on the field.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Runners")
            }

            Section("Outs") {
                Picker("Outs", selection: $model.situation.outs) {
                    ForEach(0..<3) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ForEach(Hit.groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.hits) { hit in
                        Button {
                            model.situation.hitID = hit.id
                        } label: {
                            HStack {
                                Label(hit.label, systemImage: hit.line ? (hit.leftSide ? "arrow.up.left" : "arrow.up.right") : symbol(hit.kind))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if model.situation.hitID == hit.id {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.situation.hitID == hit.id ? .isSelected : [])
                        .accessibilityLabel(hit.text)
                    }
                }
            }

            Section {
                Picker("Quiz me as", selection: $model.focus) {
                    Text("Everyone (no quiz)").tag(Position?.none)
                    ForEach(Position.allCases) { p in
                        Text("\(p.label) — \(p.name)").tag(Position?.some(p))
                    }
                }
            } header: {
                Text("Quiz")
            } footer: {
                Text("Pick a position, drag on the field to where that player should go, then tap Show Me.")
            }
        }
        .navigationTitle("Situations")
    }

    private func symbol(_ kind: HitKind) -> String {
        switch kind {
        case .ground: "arrow.down.right"
        case .bunt: "arrow.down.to.line"
        case .fly: "arrow.up.forward"
        case .single: "arrow.forward"
        case .gap: "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// A small diamond with tappable 1st/2nd/3rd bases.
struct RunnerDiamond: View {
    let runners: [Bool]
    let toggle: (Int) -> Void

    var body: some View {
        let size: CGFloat = 84
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: size / 2, y: size - 8))
                p.addLine(to: CGPoint(x: size - 8, y: size / 2))
                p.addLine(to: CGPoint(x: size / 2, y: 8))
                p.addLine(to: CGPoint(x: 8, y: size / 2))
                p.closeSubpath()
            }
            .stroke(.secondary.opacity(0.5), lineWidth: 1.5)

            base(1, at: CGPoint(x: size - 8, y: size / 2))
            base(2, at: CGPoint(x: size / 2, y: 8))
            base(3, at: CGPoint(x: 8, y: size / 2))
            Image(systemName: "pentagon.fill")
                .rotationEffect(.degrees(180))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .position(x: size / 2, y: size - 8)
        }
        .frame(width: size, height: size)
    }

    private func base(_ n: Int, at pt: CGPoint) -> some View {
        let on = runners[n - 1]
        return Button {
            toggle(n)
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(on ? Theme.runner : Color.secondary.opacity(0.15))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(on ? .white : .secondary, lineWidth: 1.5))
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(45))
                .frame(width: 36, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .position(pt)
        .selectionFeedback(trigger: on)
        .accessibilityLabel(["First", "Second", "Third"][n - 1] + " base")
        .accessibilityValue(on ? "Runner on" : "Empty")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
