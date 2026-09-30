import SwiftUI

/// Play/pause, step, scrub, and speed for a revealed play.
struct TransportBar: View {
    @Bindable var model: SimulatorModel
    private let stepMS = 200.0

    var body: some View {
        TimelineView(.animation(paused: !model.isPlaying)) { timeline in
            let t = model.elapsed(at: timeline.date) ?? 0
            HStack(spacing: 14) {
                Button("Step Back", systemImage: "backward.frame.fill") { model.step(by: -stepMS) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                    model.togglePlay()
                }
                .font(.title2)
                .frame(width: 32)
                .keyboardShortcut(.space, modifiers: [])
                Button("Step Forward", systemImage: "forward.frame.fill") { model.step(by: stepMS) }
                    .keyboardShortcut(.rightArrow, modifiers: [])

                VStack(alignment: .leading, spacing: 2) {
                    Slider(
                        value: Binding(get: { t }, set: { model.scrub(to: $0) }),
                        in: 0...SimulatorModel.playDuration,
                        onEditingChanged: { editing in if editing { model.pause() } }
                    )
                    .accessibilityLabel("Play position")
                    .accessibilityValue(SimulatorModel.phase(at: t))
                    Text(SimulatorModel.phase(at: t))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .frame(minWidth: 180, idealWidth: 320, maxWidth: 360)

                Menu {
                    Picker("Speed", selection: Binding(get: { model.speed }, set: { model.setSpeed($0) })) {
                        ForEach(SimulatorModel.speeds, id: \.self) { Text(Self.label($0)).tag($0) }
                    }
                } label: {
                    Text(Self.label(model.speed))
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 44)
                }
                .accessibilityLabel("Speed \(Self.label(model.speed))")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .glassCapsule()
        }
    }

    static func label(_ speed: Double) -> String {
        switch speed {
        case 0.25: "¼×"
        case 0.5: "½×"
        default: "\(Int(speed))×"
        }
    }
}
