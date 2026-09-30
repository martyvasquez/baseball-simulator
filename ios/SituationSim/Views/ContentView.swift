import SwiftUI

struct ContentView: View {
    @State private var model = SimulatorModel()
    @State private var showAnswer = true
    @State private var columns = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SetupSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            stage
                .inspector(isPresented: $showAnswer) {
                    AnswerPanel(model: model)
                        .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
                        } label: {
                            Label("Set Up Situation", systemImage: "sidebar.leading")
                        }
                        .keyboardShortcut("s", modifiers: [.command, .control])
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Random Situation", systemImage: "dice", action: model.randomize)
                            .keyboardShortcut("r", modifiers: .command)
                        Button {
                            showAnswer.toggle()
                        } label: {
                            Label("Answer", systemImage: "sidebar.trailing")
                        }
                    }
                }
        }
        // The setup sidebar slides over the field instead of squeezing it.
        .navigationSplitViewStyle(.prominentDetail)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.throwLandings)
        #if DEBUG
        .task { DemoLaunch.apply(to: model) }
        #endif
    }

    private var stage: some View {
        // Header and controls get their own space so they never cover the play.
        FieldView(model: model)
            .safeAreaInset(edge: .top, spacing: 4) { header }
            .safeAreaInset(edge: .bottom, spacing: 8) { controls }
            .background(Theme.foulGrass)
            .navigationTitle(model.situation.hit.text)
            .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(model.runnersText)
                .font(.headline)
            HStack(spacing: 5) {
                Text("OUTS").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(0..<2) { i in
                    Circle()
                        .strokeBorder(Theme.runner, lineWidth: 2)
                        .background(Circle().fill(i < model.situation.outs ? Theme.runner : .clear))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.situation.outs) outs")
            Text(model.situation.level.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 8)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 14) {
            if model.revealed {
                TransportBar(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 16) {
                Button("Random", systemImage: "dice", action: model.randomize)
                    .buttonStyle(.glass)
                Button(model.revealed ? "Replay" : "Show Me!", systemImage: model.revealed ? "arrow.counterclockwise" : "play.fill") {
                    model.reveal()
                    showAnswer = true
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.runner)
                // After the reveal, Space is play/pause on the transport bar.
                .keyboardShortcut(model.revealed ? nil : KeyboardShortcut(.space, modifiers: []))
            }
            .controlSize(.extraLarge)
            .font(.headline)
            }
            .animation(.snappy, value: model.revealed)
        }
        .padding(.bottom, 16)
    }
}

#Preview {
    ContentView()
}
