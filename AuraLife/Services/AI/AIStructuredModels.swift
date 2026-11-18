import Foundation

// MARK: - Structured Outputs Swift Models (Strict JSON Schema Decodable)

struct AIDietaryBoundaryPayload: Codable, Sendable {
    let greenLightFoods: [String]
    let yellowLightLimit: [String]
    let redLightAvoid: [String]
    let flexibilityNote: String

    static let defaultMaintenance = AIDietaryBoundaryPayload(
        greenLightFoods: ["水煮蛋/蒸蛋", "温热无糖豆浆", "蒸山药/南瓜", "清炖鸡胸/瘦肉/嫩豆腐", "温热绿叶菜"],
        yellowLightLimit: ["杂粮饭半碗", "常温微甜水果少量"],
        redLightAvoid: ["冰镇饮品", "高糖奶茶糕点", "油炸烧烤宵夜", "过量寒凉海鲜"],
        flexibilityNote: "食谱只是省心示范，做到「温热+少油+优质蛋白」就算达标；饿了可从绿灯加餐，不必硬扛。"
    )
}

struct AIRegimenPhasePayload: Codable, Sendable {
    let stageKind: String
    let phaseName: String
    let therapeuticPrinciple: String
    let plannedDays: Int
    let exitCriteria: String
    let nextStageHint: String
    let dietaryBoundary: AIDietaryBoundaryPayload

    init(
        stageKind: String,
        phaseName: String,
        therapeuticPrinciple: String,
        plannedDays: Int,
        exitCriteria: String,
        nextStageHint: String,
        dietaryBoundary: AIDietaryBoundaryPayload = .defaultMaintenance
    ) {
        self.stageKind = stageKind
        self.phaseName = phaseName
        self.therapeuticPrinciple = therapeuticPrinciple
        self.plannedDays = plannedDays
        self.exitCriteria = exitCriteria
        self.nextStageHint = nextStageHint
        self.dietaryBoundary = dietaryBoundary
    }

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
    let corePrinciple: String
    let flexibleSwapHint: String

    init(
        category: String,
        timeSlot: String,
        title: String,
        actionDetail: String,
        reasoning: String,
        corePrinciple: String = "",
        flexibleSwapHint: String = ""
    ) {
        self.category = category
        self.timeSlot = timeSlot
        self.title = title
        self.actionDetail = actionDetail
        self.reasoning = reasoning
        self.corePrinciple = corePrinciple
        self.flexibleSwapHint = flexibleSwapHint
    }

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
    let corePrinciple: String
    let flexibleSwapHint: String

    init(
        dayOffset: Int,
        targetCardID: String?,
        category: String,
        timeSlot: String,
        updatedTitle: String,
        updatedDetail: String,
        updatedReasoning: String,
        corePrinciple: String = "",
        flexibleSwapHint: String = ""
    ) {
        self.dayOffset = dayOffset
        self.targetCardID = targetCardID
        self.category = category
        self.timeSlot = timeSlot
        self.updatedTitle = updatedTitle
        self.updatedDetail = updatedDetail
        self.updatedReasoning = updatedReasoning
        self.corePrinciple = corePrinciple
        self.flexibleSwapHint = flexibleSwapHint
    }

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
    let redFlagAdvice: String
    let triageQuestions: [AITriageQuestionPayload]
    let proposedPhase: String
    let phaseSpec: AIRegimenPhasePayload
    let detectedSymptoms: [String]
    let summary: String
    let diffs: [AICardDiffPayload]

    var needsClarification: Bool {
        resolutionStatus == "needsClarification" && !triageQuestions.isEmpty
    }

    var isRedFlagWarning: Bool {
        resolutionStatus == "redFlagWarning"
    }
}

struct AICardSwapResponse: Codable, Sendable {
    let title: String
    let actionDetail: String
    let reasoning: String
    let corePrinciple: String
    let flexibleSwapHint: String

    init(
        title: String,
        actionDetail: String,
        reasoning: String,
        corePrinciple: String = "",
        flexibleSwapHint: String = ""
    ) {
        self.title = title
        self.actionDetail = actionDetail
        self.reasoning = reasoning
        self.corePrinciple = corePrinciple
        self.flexibleSwapHint = flexibleSwapHint
    }

    var clampedReasoning: String {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 30 {
            return trimmed
        }
        return String(trimmed.prefix(29)) + "…"
    }
}

struct AIConstitutionEvolutionPayload: Codable, Sendable {
    let shouldUpdateProfile: Bool
    let updatedConstitutionTags: [String]
    let deltaSummary: String
    let toleranceNote: String
}

struct OnboardingInquiryAnswer: Identifiable, Sendable {
    let id: String
    let question: String
    let answer: String
}

struct AIOnboardingFollowUpResponse: Codable, Sendable {
    let needFollowUp: Bool
    let reasoningHint: String
    let questions: [AITriageQuestionPayload]
}

struct AIOnboardingConstitutionResponse: Codable, Sendable {
    let primaryConstitution: String
    let secondaryTags: [String]
    let confidencePercent: Int
    let needsThreeDayTrial: Bool
    let clinicalSummary: String
    let plainDiagnosis: String
    let strategyOverview: String
    let expectedTimeline: String
    let suggestedPhaseSpec: AIRegimenPhasePayload
    let initialDayCards: [AIPlannedCardPayload]
    let baselineDeltaSummary: String
    let baselineToleranceNote: String

    var allConstitutionTags: [String] {
        var tags = [primaryConstitution]
        for tag in secondaryTags where !tag.isEmpty && !tags.contains(tag) {
            tags.append(tag)
        }
        return tags
    }

    var clampedConfidence: Int {
        max(45, min(95, confidencePercent))
    }
}

struct AIPhaseTransitionResponse: Codable, Sendable {
    let transitionDecision: String
    let clinicalAssessment: String
    let summary: String
    let newPhaseSpec: AIRegimenPhasePayload
    let evolutionSpec: AIConstitutionEvolutionPayload
    let remainingSymptoms: [String]
    let cards: [AIPlannedCardPayload]

    var isAdvancingStage: Bool {
        transitionDecision == "advanceToNextStage"
    }
}
