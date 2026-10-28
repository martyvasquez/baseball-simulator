import SwiftUI

/// Ask ChatGPT about the play that was just shown. One chat per situation.
struct AskPanel: View {
    @Bindable var model: SimulatorModel
    @State private var ai = AIService.shared
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        Group {
            if !model.revealed {
                placeholder("Watch the play first", systemImage: "play.circle",
                            "Tap Show Me! to see the play, then ask about it here.")
            } else if !ai.isReady {
                signIn
            } else if !ai.planAllowed {
                allowPlan
            } else {
                chat
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Not ready yet

    private func placeholder(_ title: String, systemImage: String, _ message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }

    private var signIn: some View {
        ScrollView {
            signInCard
        }
    }

    private var signInCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Ask About This Play").font(.title2.bold())
            Text("Ask ChatGPT why everyone goes where they do, or what changes if something's different. It uses your own ChatGPT plan (Plus or Pro).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Group {
                if ai.isSigningIn {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Finish signing in…").foregroundStyle(.secondary)
                        Button("Cancel") { ai.cancelSignIn() }
                    }
                } else {
                    ContinueWithChatGPTButton { ai.signIn() }
                }
            }
            .frame(minHeight: 44)
            if let error = ai.signInError {
                Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Text("The situation, the app's answer, and your questions are sent to OpenAI.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private var allowPlan: some View {
        VStack(spacing: 16) {
            placeholder("ChatGPT plan not allowed", systemImage: "lock",
                        "When you signed in, Situations wasn't allowed to use your ChatGPT plan. Sign in again and allow it to ask questions.")
            Button("Sign In Again") { ai.signIn(askConsent: true) }
                .buttonStyle(.borderedProminent)
                .disabled(ai.isSigningIn)
            accountFooter
        }
        .padding(.bottom, 16)
    }

    // MARK: - The chat

    private var chat: some View {
        let chat = model.chat
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            starters
                        }
                        ForEach(chat.messages) { m in
                            bubble(m, waiting: chat.isAnswering && m.id == chat.messages.last?.id)
                                .id(m.id)
                        }
                        if let error = chat.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.last?.text) {
                    if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            composer
            accountFooter
                .padding(.bottom, 8)
        }
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask anything about this play.")
                .foregroundStyle(.secondary)
            ForEach(PlayChat.starters, id: \.self) { q in
                Button { send(q) } label: {
                    Text(q).multilineTextAlignment(.leading)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private func bubble(_ m: PlayChat.Message, waiting: Bool) -> some View {
        if m.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.field.opacity(0.2), in: .rect(cornerRadius: 14))
                    .textSelection(.enabled)
            }
        } else if m.text.isEmpty && waiting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Thinking…").foregroundStyle(.secondary)
            }
        } else {
            Text(Self.styled(m.text))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Bold and italics from the reply, keeping its line breaks.
    private static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask about this play", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { send(draft) }
            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.chat.isAnswering)
            .accessibilityLabel("Send")
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// The model answering, and the way to Settings.
    private var accountFooter: some View {
        HStack(spacing: 6) {
            Text(ai.modelSummary).lineLimit(1)
            settingsButton
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var settingsButton: some View {
        #if os(macOS)
        SettingsLink { Text("Settings…") }
            .buttonStyle(.link)
        #else
        Button("Settings") { ai.showSettings = true }
            .buttonStyle(.borderless)
        #endif
    }

    private func send(_ text: String) {
        guard let s = model.solution, !model.chat.isAnswering else { return }
        model.chat.ask(text, about: s, focus: model.focus, grade: model.grade)
        draft = ""
    }
}

/// OpenAI's button label for Sign in with ChatGPT, in its black-or-white capsule.
struct ContinueWithChatGPTButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text("Continue with ChatGPT")
                .font(.body.weight(.medium))
                .padding(.horizontal, 24)
                .frame(height: 44)
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
