import Foundation

/// "Where this comes from": the published-source check for each rule the engine uses.
/// Loaded from Sources.json (generated from the web version's sources.js).
struct SourceNote: Decodable, Sendable {
    struct Link: Decodable, Sendable, Hashable {
        let name: String
        let url: String
    }

    enum Verdict: String, Decodable, Sendable {
        case confirmed, partly, judgment, contradicted

        var label: String {
            switch self {
            case .confirmed: "Matches sources"
            case .partly: "Varies by coach"
            case .judgment: "Our choice"
            case .contradicted: "Differs from sources"
            }
        }
    }

    let rule: String
    let verdict: Verdict
    let note: String
    let links: [Link]
}

struct SourceNotes: Sendable {
    let notes: [String: SourceNote]

    static let shared: SourceNotes = {
        guard let url = Bundle.main.url(forResource: "Sources", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let notes = try? JSONDecoder().decode([String: SourceNote].self, from: data)
        else { return SourceNotes(notes: [:]) }
        return SourceNotes(notes: notes)
    }()
}
