import Foundation

// MARK: - Structured Outputs Swift Models (Strict JSON Schema Decodable)

struct AIPlannedCardPayload: Codable, Sendable {
    let category: String
    let timeSlot: String
    let title: String
    let actionDetail: String
    let reasoning: String

    var resolvedCategory: ActionCategory {
        ActionCategory(rawValue: category) ?? .lifestyle
    }

    var clampedReasoning: String {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 30 {
            return trimmed
        }
        return String(trimmed.prefix(29)) + "…"
    }
}

struct AIDayPlanPayload: Codable, Sendable {
    let dayOffset: Int
    let recoveryPhase: String
    let detectedSymptoms: [String]
    let cards: [AIPlannedCardPayload]
}

struct AIMultiDayPlanResponse: Codable, Sendable {
    let summary: String
    let days: [AIDayPlanPayload]
}

struct AICardDiffPayload: Codable, Sendable {
    let dayOffset: Int
    let targetCardID: String?
    let category: String
    let timeSlot: String
    let updatedTitle: String
    let updatedDetail: String
    let updatedReasoning: String

    var resolvedCategory: ActionCategory {
        ActionCategory(rawValue: category) ?? .lifestyle
    }

    var clampedReasoning: String {
        let trimmed = updatedReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 30 {
            return trimmed
        }
        return String(trimmed.prefix(29)) + "…"
    }
}

struct AIAdjustmentResponse: Codable, Sendable {
    let proposedPhase: String
    let detectedSymptoms: [String]
    let summary: String
    let diffs: [AICardDiffPayload]
}

struct AICardSwapResponse: Codable, Sendable {
    let title: String
    let actionDetail: String
    let reasoning: String

    var clampedReasoning: String {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 30 {
            return trimmed
        }
        return String(trimmed.prefix(29)) + "…"
    }
}
