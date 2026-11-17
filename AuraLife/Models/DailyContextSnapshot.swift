import Foundation
import SwiftData

@Model
final class DailyContextSnapshot {
    var id: UUID
    var date: Date
    var weatherTempC: Double
    var weatherCondition: String
    var city: String
    var weatherHumidity: Double = 68.0
    var weatherWindSpeedKmh: Double = 9.0
    var weatherSource: String = "默认"
    var solarTermName: String = ""
    var healthStepCount: Int?
    var healthSleepHours: Double?
    var healthLatestWeightKG: Double?
    var userReportedSymptoms: [String]
    var recoveryPhase: String

    @Relationship(deleteRule: .cascade, inverse: \ActionCard.snapshot)
    var actionCards: [ActionCard]

    init(
        id: UUID = UUID(),
        date: Date = .now,
        weatherTempC: Double = 24.0,
        weatherCondition: String = "晴",
        city: String = "深圳",
        weatherHumidity: Double = 68.0,
        weatherWindSpeedKmh: Double = 9.0,
        weatherSource: String = "默认",
        solarTermName: String = "",
        healthStepCount: Int? = nil,
        healthSleepHours: Double? = nil,
        healthLatestWeightKG: Double? = nil,
        userReportedSymptoms: [String] = [],
        recoveryPhase: String = "日常稳态调理期",
        actionCards: [ActionCard] = []
    ) {
        self.id = id
        self.date = date
        self.weatherTempC = weatherTempC
        self.weatherCondition = weatherCondition
        self.city = city
        self.weatherHumidity = weatherHumidity
        self.weatherWindSpeedKmh = weatherWindSpeedKmh
        self.weatherSource = weatherSource
        self.solarTermName = solarTermName.isEmpty ? SolarTermCalculator.term(for: date).name : solarTermName
        self.healthStepCount = healthStepCount
        self.healthSleepHours = healthSleepHours
        self.healthLatestWeightKG = healthLatestWeightKG
        self.userReportedSymptoms = userReportedSymptoms
        self.recoveryPhase = recoveryPhase
        self.actionCards = actionCards
    }

    var resolvedSolarTerm: (name: String, guidance: String) {
        let computed = SolarTermCalculator.term(for: date)
        return (solarTermName.isEmpty ? computed.name : solarTermName, computed.guidance)
    }

    var isAcuteRecovery: Bool {
        recoveryPhase.contains("恢复期") || !userReportedSymptoms.isEmpty
    }

    var sortedCards: [ActionCard] {
        actionCards.sorted { $0.sortOrder < $1.sortOrder }
    }
}
