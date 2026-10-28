import SwiftUI

struct ContentView: View {
    @State private var model = SimulatorModel()
    @State private var showAnswer = true
    @State private var ai = AIService.shared
    #if os(iOS)
    @State private var columns = NavigationSplitViewVisibility.detailOnly
    // On iPhone the columns collapse into one screen; start on the field, not the setup list.
    @State private var compactColumn = NavigationSplitViewColumn.detail
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #else
    // A Mac window has room for setup, field, and answer side by side.
    @State private var columns = NavigationSplitViewVisibility.all
    #endif

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: compactColumnBinding) {
            SetupSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
                #if os(iOS)
                // iPad uses the custom button below; the Mac keeps its standard sidebar button.
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    if isCompact {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { compactColumn = .detail }
                        }
                    }
                }
                #endif
        } detail: {
            stage
                .inspector(isPresented: $showAnswer) {
                    InspectorPanel(model: model)
                        .inspectorColumnWidth(min: 300, ideal: 360, max: 440)
                        #if os(iOS)
                        // On iPhone the answer is a sheet; half height leaves the field in view.
                        .presentationDetents([.medium, .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                        #endif
                }
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if isCompact {
                                compactColumn = .sidebar
                            } else {
                                withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
                            }
                        } label: {
                            Label("Set Up Situation", systemImage: "sidebar.leading")
                        }
                        .keyboardShortcut("s", modifiers: [.command, .control])
                    }
                    #endif
                    #if os(iOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            AIService.shared.showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .keyboardShortcut(",", modifiers: .command)
                    }
                    #endif
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAnswer.toggle()
                        } label: {
                            Label("Answer", systemImage: "sidebar.trailing")
                        }
                        .help("Show or hide the answer")
                    }
                }
        }
        #if os(iOS)
        // The setup sidebar slides over the field instead of squeezing it.
        .navigationSplitViewStyle(.prominentDetail)
        #endif
        .impactFeedback(trigger: model.throwLandings)
        #if os(iOS)
        .sheet(isPresented: $ai.showSettings) { SettingsView() }
        #endif
        #if os(iOS)
        // On iPhone the answer sheet would cover the field, so it opens only when asked for.
        .onAppear { if isCompact { showAnswer = false } }
        #endif
        #if DEBUG
        .task { DemoLaunch.apply(to: model) }
        #endif
    }

    private var compactColumnBinding: Binding<NavigationSplitViewColumn> {
        #if os(iOS)
        $compactColumn
        #else
        .constant(.detail)
        #endif
    }

    private var stage: some View {
        // Header and controls get their own space so they never cover the play.
        FieldView(model: model)
            .safeAreaInset(edge: .top, spacing: 4) { header }
            .safeAreaInset(edge: .bottom, spacing: 8) { controls }
            .background(Theme.foulGrass)
            .navigationTitle(model.situation.hit.text)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // On iPhone the setup button already goes back to the setup list.
            .navigationBarBackButtonHidden(isCompact)
            #endif
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
        .glassCapsule()
        .padding(.top, 8)
    }

    private var controls: some View {
        GlassGroup(spacing: 16) {
            VStack(spacing: 14) {
                if model.revealed {
                    TransportBar(model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: 16) {
                    Button("Random", systemImage: "dice", action: model.randomize)
                        .glassButton()
                        .keyboardShortcut("r", modifiers: .command)
                    Button(model.revealed ? "Replay" : "Show Me!", systemImage: model.revealed ? "arrow.counterclockwise" : "play.fill") {
                        model.reveal()
                        #if os(iOS)
                        if !isCompact { showAnswer = true }
                        #else
                        showAnswer = true
                        #endif
                    }
                    .glassButton(prominent: true)
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

/// The answer, and a chat with ChatGPT about the play, side by side as tabs.
struct InspectorPanel: View {
    @Bindable var model: SimulatorModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $model.answerTab) {
                Text("Answer").tag(SimulatorModel.AnswerTab.answer)
                Label("Ask", systemImage: "bubble.left.and.text.bubble.right").tag(SimulatorModel.AnswerTab.ask)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            switch model.answerTab {
            case .answer: AnswerPanel(model: model)
            case .ask: AskPanel(model: model)
            }
        }
    }
}

#Preview {
    ContentView()
}
