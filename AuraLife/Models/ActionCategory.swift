import Foundation
import SwiftUI

enum ActionCategory: String, Codable, CaseIterable, Sendable {
    case diet
    case fitness
    case lifestyle

    var displayName: String {
        switch self {
        case .diet:
            return "食养"
        case .fitness:
            return "导引"
        case .lifestyle:
            return "起居"
        }
    }

    var systemImage: String {
        switch self {
        case .diet:
            return "cup.and.saucer.fill"
        case .fitness:
            return "figure.pool.swim"
        case .lifestyle:
            return "moon.stars.fill"
        }
    }
}
