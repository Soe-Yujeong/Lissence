import Foundation

enum Mood: String, CaseIterable, Identifiable {
    case happy
    case angry
    case sad
    case relaxed

    var id: String { rawValue }

    init?(qLabel: String) {
        switch qLabel {
        case "Q1": self = .happy
        case "Q2": self = .angry
        case "Q3": self = .sad
        case "Q4": self = .relaxed
        default: return nil
        }
    }

    var riveValue: Double {
        switch self {
        case .happy:   return 0.0
        case .angry:   return 1.0
        case .sad:     return 2.0
        case .relaxed: return 3.0
        }
    }
}
