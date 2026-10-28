#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import Observation

enum AIServiceError: Error, LocalizedError {
    case signInNeeded

    var errorDescription: String? {
        switch self {
        case .signInNeeded: "Sign in with ChatGPT to ask questions about a play."
        }
    }
}

/// Sign in with ChatGPT: whoever wants to ask questions signs in with their own ChatGPT account, and the answers run on
/// their plan. Owns the sign-in and the model. App-wide. (Adapted from Peanut Manager's AIService.)
@Observable
@MainActor
final class AIService {
    static let shared = AIService()

    private(set) var account: ChatGPTAccount?
    private(set) var isSignedIn = false
    private(set) var planUsageGranted = false
    private(set) var isSigningIn = false
    var signInError: String?
    private(set) var models: [ChatGPTClient.ModelInfo] = []
    private(set) var modelsError: String?
    /// Opens Settings on iPad (the Mac uses its Settings window).
    var showSettings = false

    // MARK: Model and thinking

    /// The default: Luna 5.6 at medium thinking, as Peanut Manager uses it.
    static let defaultModel = ChatGPTClient.defaultModel
    static let defaultEffort = "medium"
    /// Thinking levels, least to most, for when the account's list doesn't say.
    static let efforts = ["low", "medium", "high"]

    /// The person's choice in Settings; nil means the default.
    var chosenModel: String? = UserDefaults.standard.string(forKey: Keys.model) {
        didSet { UserDefaults.standard.set(chosenModel, forKey: Keys.model) }
    }
    var chosenEffort: String? = UserDefaults.standard.string(forKey: Keys.effort) {
        didSet { UserDefaults.standard.set(chosenEffort, forKey: Keys.effort) }
    }

    /// The model requests use: the choice, or Luna 5.6. If OpenAI no longer offers that model to the account,
    /// the newest Luna it does.
    var modelID: String {
        let wanted = chosenModel ?? Self.defaultModel
        let ids = models.map(\.id)
        guard !ids.isEmpty, !ids.contains(wanted) else { return wanted }
        return ChatGPTClient.preferredModel(in: ids) ?? wanted
    }

    /// The thinking levels the current model accepts.
    var effortChoices: [String] {
        let listed = models.first { $0.id == modelID }?.efforts ?? []
        return listed.isEmpty ? Self.efforts : listed
    }

    /// The thinking level requests use: the choice if the model accepts it, else medium, else the model's own default.
    var effort: String {
        let choices = effortChoices
        if let chosenEffort, choices.contains(chosenEffort) { return chosenEffort }
        if choices.contains(Self.defaultEffort) { return Self.defaultEffort }
        return models.first { $0.id == modelID }?.defaultEffort ?? choices.first ?? Self.defaultEffort
    }

    /// "GPT-5.6-Luna · Medium"
    var modelSummary: String { "\(displayName(for: modelID)) · \(effort.capitalized)" }

    func displayName(for id: String) -> String {
        models.first { $0.id == id }?.name ?? Self.fallbackName(id)
    }

    /// "gpt-5.6-luna" → "GPT-5.6-Luna", for before the account's list arrives.
    static func fallbackName(_ id: String) -> String {
        guard id.hasPrefix("gpt-") else { return id }
        return "GPT-" + id.dropFirst(4).split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
    }

    var isDefaultChoice: Bool { modelID == Self.defaultModel && effort == Self.defaultEffort }

    func resetModelChoice() {
        chosenModel = nil
        chosenEffort = nil
    }

    private var session: ChatGPTSession?
    private var signInTask: Task<Void, Never>?
    private let auth = ChatGPTAuth()

    private enum Keys {
        static let vault = "chatgpt-session"
        static let host = "chatgpt-host-id"
        static let model = "chatGPTModel"
        static let effort = "chatGPTEffort"
    }

    private init() {
        #if DEBUG
        if DemoLaunch.fakeAI { return }
        #endif
        if let record = Self.loadRecord() {
            account = record.account
            if let tokens = record.tokens { adopt(record.account, tokens) }
        }
        if isSignedIn { Task { await loadModels() } }
    }

    /// The client for the next request. Never fails here: a missing sign-in surfaces when the request runs.
    func client() -> any LLMClient {
        #if DEBUG
        if DemoLaunch.fakeAI { return FakeLLMClient() }
        #endif
        guard let session else { return UnavailableClient() }
        return ChatGPTClient(session: session, reasoningEffort: effort)
    }

    /// Whether questions can be asked; while not, the app shows Continue with ChatGPT in their place.
    var isReady: Bool {
        #if DEBUG
        if DemoLaunch.fakeAI { return true }
        #endif
        return isSignedIn
    }

    /// Whether the person let Situations use their ChatGPT plan when they signed in.
    var planAllowed: Bool {
        #if DEBUG
        if DemoLaunch.fakeAI { return true }
        #endif
        return planUsageGranted
    }

    // MARK: - Sign in / out

    /// Opens OpenAI's sign-in page. `askConsent` re-shows the permission screen (to allow plan use after declining it).
    func signIn(askConsent: Bool = false) {
        guard signInTask == nil else { return }
        signInError = nil
        isSigningIn = true
        let previous = account
        let hint = Self.loadRecord()?.tokens?.idToken
        signInTask = Task {
            defer { isSigningIn = false; signInTask = nil }
            #if os(iOS)
            defer { WebSignIn.shared.close() }
            #endif
            do {
                let (account, tokens) = try await auth.signIn(hostID: Self.hostID(), account: previous, idTokenHint: hint, askConsent: askConsent) { url in
                    #if os(macOS)
                    await MainActor.run { _ = NSWorkspace.shared.open(url) }
                    #else
                    // In a sheet over the app, so the app stays in front to hear OpenAI's reply on 127.0.0.1.
                    await MainActor.run { WebSignIn.shared.open(url) }
                    #endif
                }
                Self.saveRecord(Record(account: account, tokens: tokens))
                adopt(account, tokens)
                #if os(macOS)
                NSApp.activate()
                #endif
                await loadModels()
            } catch is CancellationError {
            } catch {
                signInError = error.localizedDescription
                #if os(macOS)
                NSApp.activate()
                #endif
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    /// Ends the session on OpenAI's side, then forgets the tokens. Keeps the registration so the next sign-in reuses it.
    func signOut() {
        let record = Self.loadRecord()
        session = nil
        isSignedIn = false
        planUsageGranted = false
        models = []
        if let account { Self.saveRecord(Record(account: account, tokens: nil)) }
        guard let record, let tokens = record.tokens else { return }
        Task {
            do {
                try await auth.revoke(tokens, account: record.account)
            } catch {
                signInError = "Signed out here, but ChatGPT didn't confirm it. You can disconnect Situations in ChatGPT settings."
            }
        }
    }

    /// Forget the saved registration so the next sign-in can pick any ChatGPT account.
    func useDifferentAccount() {
        signOut()
        account = nil
        Self.saveRecord(nil)
        signIn()
    }

    func loadModels() async {
        guard let session else { return }
        do {
            models = try await ChatGPTClient(session: session).models()
            modelsError = nil
        } catch {
            modelsError = error.localizedDescription
        }
    }

    private func adopt(_ account: ChatGPTAccount, _ tokens: ChatGPTTokens) {
        self.account = account
        isSignedIn = true
        planUsageGranted = tokens.planUsageGranted
        session = ChatGPTSession(account: account, tokens: tokens) { tokens in
            // Called off the main actor with each refreshed token set, or nil once the session can't be renewed.
            Self.saveTokens(tokens, for: account)
            if tokens == nil { Task { @MainActor in AIService.shared.sessionEnded() } }
        }
    }

    private func sessionEnded() {
        session = nil
        isSignedIn = false
        planUsageGranted = false
    }

    // MARK: - Storage

    nonisolated struct Record: Codable {
        var account: ChatGPTAccount
        var tokens: ChatGPTTokens?
    }

    nonisolated private static func loadRecord() -> Record? {
        SecretStore.data(Keys.vault).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    nonisolated private static func saveRecord(_ record: Record?) {
        SecretStore.set(record.flatMap { try? JSONEncoder().encode($0) }, for: Keys.vault)
    }

    nonisolated private static func saveTokens(_ tokens: ChatGPTTokens?, for account: ChatGPTAccount) {
        saveRecord(Record(account: account, tokens: tokens))
    }

    /// This install's opaque host ID, made once and kept for good.
    nonisolated private static func hostID() -> String {
        if let data = SecretStore.data(Keys.host), let id = String(data: data, encoding: .utf8) { return id }
        let id = ChatGPTAuth.newHostID()
        SecretStore.set(Data(id.utf8), for: Keys.host)
        return id
    }
}

/// Stands in for ChatGPT before sign-in, so the request fails with a clear message.
private struct UnavailableClient: LLMClient {
    func complete(_ request: LLMRequest, onText: @escaping @Sendable (String) -> Void) async throws -> String {
        throw AIServiceError.signInNeeded
    }
}

#if DEBUG
/// `-fakeAI YES`: answers instantly without signing in or sending anything, for screenshots and UI checks.
struct FakeLLMClient: LLMClient {
    func complete(_ request: LLMRequest, onText: @escaping @Sendable (String) -> Void) async throws -> String {
        let question = request.messages.last?.content ?? ""
        let reply = "Good question! (A pretend answer for testing — you asked: “\(question)”.) In a real answer, ChatGPT explains the play shown on the field."
        var text = ""
        for word in reply.split(separator: " ") {
            try await Task.sleep(for: .milliseconds(40))
            text += (text.isEmpty ? "" : " ") + word
            onText(text)
        }
        return text
    }
}
#endif
