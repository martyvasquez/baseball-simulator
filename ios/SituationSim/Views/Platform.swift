import SwiftUI

// Small helpers so the same views work on iPad and Mac, and on Macs older than
// macOS 26 (which don't have Liquid Glass — they get standard materials instead).

extension View {
    /// A glass capsule behind floating controls.
    @ViewBuilder func glassCapsule() -> some View {
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: .capsule)
        }
    }

    /// Glass button style, or the closest standard style on older systems.
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// A haptic tap on iPad; nothing on Mac.
    @ViewBuilder func impactFeedback<T: Equatable>(trigger: T) -> some View {
        #if os(iOS)
        sensoryFeedback(.impact(weight: .medium), trigger: trigger)
        #else
        self
        #endif
    }

    /// A light selection haptic on iPad; nothing on Mac.
    @ViewBuilder func selectionFeedback<T: Equatable>(trigger: T) -> some View {
        #if os(iOS)
        sensoryFeedback(.selection, trigger: trigger)
        #else
        self
        #endif
    }
}

/// Groups glass controls so they blend together (macOS 26 / iOS 26), or just lays them out.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
