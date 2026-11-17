import Foundation

// MARK: - Structured Outputs Swift Models (Strict JSON Schema Decodable)

struct AIRegimenPhasePayload: Codable, Sendable {
    let stageKind: String
    let phaseName: String
    let therapeuticPrinciple: String
    let plannedDays: Int
    let exitCriteria: String
    let nextStageHint: String

    var resolvedStageKind: RegimenStageKind {
        RegimenStageKind.infer(from: stageKind)
    }

    var normalizedPlannedDays: Int {
        max(1, min(30, plannedDays))
    }
}

struct AITriageQuestionPayload: Codable, Sendable, Identifiable {
    let id: String
    let question: String
    let options: [String]
}

struct AITriageAnswer: Identifiable, Sendable {
    let id: String
    let question: String
    let selectedOption: String
}

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
    let phaseSpec: AIRegimenPhasePayload
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
    let resolutionStatus: String
    let clarificationReason: String
    let triageQuestions: [AITriageQuestionPayload]
    let proposedPhase: String
    let phaseSpec: AIRegimenPhasePayload
    let detectedSymptoms: [String]
    let summary: String
    let diffs: [AICardDiffPayload]

    var needsClarification: Bool {
        resolutionStatus == "needsClarification" && !triageQuestions.isEmpty
    }
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
