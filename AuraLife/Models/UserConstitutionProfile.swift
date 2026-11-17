import Foundation
import SwiftData

@Model
final class UserConstitutionProfile {
    var id: UUID
    var heightCM: Double
    var weightKG: Double
    var targetWeightKG: Double
    var constitutionTags: [String]
    var dietaryPreferences: [String]
    var fitnessPreferences: [String]
    var diningEnvironment: String
    var rawReportSummary: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        heightCM: Double = 176.5,
        weightKG: Double = 85.0,
        targetWeightKG: Double = 75.0,
        constitutionTags: [String] = ["痰湿质78分", "轻微气虚", "肠胃敏感"],
        dietaryPreferences: [String] = ["忌生冷冰饮", "少油腻甜食", "偏爱温热汤羹"],
        fitnessPreferences: [String] = ["室外游泳40min", "讨厌传统跑步有氧", "居家轻抗阻"],
        diningEnvironment: String = "居家做饭",
        rawReportSummary: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.heightCM = heightCM
        self.weightKG = weightKG
        self.targetWeightKG = targetWeightKG
        self.constitutionTags = constitutionTags
        self.dietaryPreferences = dietaryPreferences
        self.fitnessPreferences = fitnessPreferences
        self.diningEnvironment = diningEnvironment
        self.rawReportSummary = rawReportSummary
        self.updatedAt = updatedAt
    }

    var bmi: Double {
        let heightMeters = heightCM / 100.0
        guard heightMeters > 0 else { return 0 }
        return weightKG / (heightMeters * heightMeters)
    }

    var primaryConstitution: String {
        constitutionTags.first ?? "待辨识体质"
    }
}
