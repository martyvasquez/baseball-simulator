import SwiftUI

/// ChatGPT sign-in, and the model and thinking level that answer questions about a play.
/// The Mac's Settings window (⌘,); a sheet on iPad.
struct SettingsView: View {
    @State private var ai = AIService.shared
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #else
        form
            .frame(width: 460)
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    private var form: some View {
        Form {
            account
            if ai.isSignedIn || ai.isReady {
                model
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - ChatGPT account

    private var account: some View {
        Section {
            if ai.isSignedIn {
                LabeledContent("Signed in as", value: ai.account?.email ?? ai.account?.name ?? "ChatGPT account")
                if !ai.planUsageGranted {
                    Text("Situations isn't allowed to use your ChatGPT plan, so it can't answer questions.")
                        .foregroundStyle(.orange)
                    Button("Allow Plan Use…") { ai.signIn(askConsent: true) }
                        .disabled(ai.isSigningIn)
                }
                Link("Manage Usage", destination: ChatGPTAuth.manageUsageURL)
                Button("Use a Different Account") { ai.useDifferentAccount() }
                    .disabled(ai.isSigningIn)
                Button("Sign Out", role: .destructive) { ai.signOut() }
            } else if ai.isSigningIn {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { ai.cancelSignIn() }
                }
            } else {
                HStack {
                    Spacer()
                    ContinueWithChatGPTButton { ai.signIn() }
                    Spacer()
                }
            }
            if let error = ai.signInError {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("ChatGPT")
        } footer: {
            if !ai.isSignedIn {
                Text("Sign in with your own ChatGPT account to ask questions about a play. It uses your ChatGPT plan (Plus or Pro). The situation, the app's answer, and your questions are sent to OpenAI.")
            }
        }
    }

    // MARK: - Model and thinking

    private var model: some View {
        Section {
            Picker("Model", selection: modelSelection) {
                ForEach(modelChoices, id: \.self) { id in
                    Text(ai.displayName(for: id) + (id == AIService.defaultModel ? " (default)" : "")).tag(id)
                }
            }
            Picker("Thinking", selection: effortSelection) {
                ForEach(ai.effortChoices, id: \.self) { effort in
                    Text(effort.capitalized + (effort == AIService.defaultEffort ? " (default)" : "")).tag(effort)
                }
            }
            if !ai.isDefaultChoice {
                Button("Reset to \(AIService.fallbackName(AIService.defaultModel)) · \(AIService.defaultEffort.capitalized)") {
                    ai.resetModelChoice()
                }
            }
            if let error = ai.modelsError {
                Label("Couldn't load your models: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                Button("Try Again") { Task { await ai.loadModels() } }
            }
        } header: {
            Text("Answers")
        } footer: {
            Text("More thinking gives more careful answers but takes longer and uses more of your plan. \(summary ?? "")")
        }
    }

    /// The account's models, with the one in use first if the list hasn't arrived.
    private var modelChoices: [String] {
        let ids = ai.models.map(\.id)
        return ids.contains(ai.modelID) ? ids : [ai.modelID] + ids
    }

    private var summary: String? {
        ai.models.first { $0.id == ai.modelID }?.summary
    }

    private var modelSelection: Binding<String> {
        Binding {
            ai.modelID
        } set: { id in
            ai.chosenModel = id == AIService.defaultModel ? nil : id
        }
    }

    private var effortSelection: Binding<String> {
        Binding {
            ai.effort
        } set: { effort in
            ai.chosenEffort = effort == AIService.defaultEffort ? nil : effort
        }
    }
}
