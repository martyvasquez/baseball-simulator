#if DEBUG
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Debug-only launch arguments for screenshots, e.g.
/// `-level hs -hit gap_LC -runners 100 -outs 1 -focus RF -reveal YES -ask "Why?" -fakeAI YES`
@MainActor
enum DemoLaunch {
    /// `-fakeAI YES`: the Ask tab works without signing in, with canned answers (nothing is sent anywhere).
    static var fakeAI: Bool { UserDefaults.standard.bool(forKey: "fakeAI") }

    static func apply(to model: SimulatorModel) {
        let args = UserDefaults.standard
        var s = model.situation
        if let l = args.string(forKey: "level").flatMap(Level.init(rawValue:)) { s.level = l }
        if let h = args.string(forKey: "hit"), Hit.all.contains(where: { $0.id == h }) { s.hitID = h }
        if let r = args.string(forKey: "runners"), r.count == 3 { s.runners = r.map { $0 == "1" } }
        if args.object(forKey: "outs") != nil { s.outs = min(2, max(0, args.integer(forKey: "outs"))) }
        model.situation = s
        if let f = args.string(forKey: "focus").flatMap(Position.init(rawValue:)) { model.focus = f }
        #if os(iOS)
        if args.bool(forKey: "landscape"),
           let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        #endif
        if args.bool(forKey: "reveal") { model.reveal() }
        if args.object(forKey: "at") != nil { model.scrub(to: args.double(forKey: "at")) }
        // Ask a question about the revealed play, and show the Ask tab: -ask "Why throw to first?"
        if let q = args.string(forKey: "ask"), let s = model.solution {
            model.answerTab = .ask
            model.chat.ask(q, about: s, focus: model.focus, grade: model.grade)
        }
        #if os(macOS)
        // Save a picture of the window: -snapshot /path/to/file.png
        if let path = args.string(forKey: "snapshot") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard let view = NSApp.windows.first(where: \.isVisible)?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
        #endif
    }
}
#endif
