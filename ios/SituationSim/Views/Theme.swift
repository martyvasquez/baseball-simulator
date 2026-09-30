import SwiftUI

enum Theme {
    static let field = Color(red: 0.98, green: 0.80, blue: 0.08)
    static let cover = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let cutoff = Color(red: 0.98, green: 0.57, blue: 0.24)
    static let backup = Color(red: 0.75, green: 0.52, blue: 0.99)
    static let other = Color(red: 0.58, green: 0.64, blue: 0.72)
    static let runner = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let player = Color(red: 0.12, green: 0.23, blue: 0.54)

    static let foulGrass = Color(red: 0.09, green: 0.24, blue: 0.14)
    static let grass = Color(red: 0.18, green: 0.48, blue: 0.23)
    static let grassStripe = Color(red: 0.16, green: 0.44, blue: 0.20)
    static let dirt = Color(red: 0.75, green: 0.52, blue: 0.32)
    static let track = Color(red: 0.60, green: 0.42, blue: 0.24)

    static func color(_ type: JobType) -> Color {
        switch type {
        case .field: field
        case .cover: cover
        case .cutoff: cutoff
        case .backup: backup
        case .other: other
        }
    }

    static func label(_ type: JobType) -> String {
        switch type {
        case .field: "Fields the ball"
        case .cover: "Covers a base"
        case .cutoff: "Cutoff / relay"
        case .backup: "Backs up"
        case .other: "Other"
        }
    }

    static func color(_ v: SourceNote.Verdict) -> Color {
        switch v {
        case .confirmed: .green
        case .partly: field
        case .judgment: other
        case .contradicted: .red
        }
    }
}

/// A position's round badge, matching the dots on the field.
struct PositionBadge: View {
    let label: String
    let ring: Color
    var fill: Color = Theme.player
    var size: CGFloat = 32

    var body: some View {
        Text(label)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(fill, in: .circle)
            .overlay(Circle().strokeBorder(ring, lineWidth: size * 0.1))
            .accessibilityHidden(true)
    }
}
