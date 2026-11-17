import Foundation
import SwiftData
import SwiftUI

enum RegimenStageKind: String, Codable, CaseIterable, Sendable {
    case acuteRelief
    case dampnessClearing
    case tonifying
    case maintenance

    var displayName: String {
        switch self {
        case .acuteRelief:
            return "急症治标期"
        case .dampnessClearing:
            return "祛邪疏通期"
        case .tonifying:
            return "缓调扶正期"
        case .maintenance:
            return "顺时固本期"
        }
    }

    var clinicalAxiom: String {
        switch self {
        case .acuteRelief:
            return "急则治其标"
        case .dampnessClearing:
            return "祛湿浊通脾运"
        case .tonifying:
            return "缓则治其本"
        case .maintenance:
            return "顺时治未病"
        }
    }

    var defaultSummary: String {
        switch self {
        case .acuteRelief:
            return "以护胃安中、散寒止泻为先，暂缓高强度运动与减重控制。"
        case .dampnessClearing:
            return "急症初平但湿浊尚留，重在健脾燥湿、温和行气导引。"
        case .tonifying:
            return "脾胃渐稳后补益正气，恢复高蛋白饮食与抗阻稳住代谢。"
        case .maintenance:
            return "紧扣体质画像、实时气象与节气节奏，平调稳态。"
        }
    }

    var systemImage: String {
        switch self {
        case .acuteRelief:
            return "cross.case.fill"
        case .dampnessClearing:
            return "wind"
        case .tonifying:
            return "leaf.arrow.circlepath"
        case .maintenance:
            return "sun.and.horizon.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .acuteRelief, .dampnessClearing:
            return AuraTheme.warmGinger
        case .tonifying, .maintenance:
            return AuraTheme.sageGreen
        }
    }

    static func infer(from rawOrPhaseName: String) -> RegimenStageKind {
        if let exact = RegimenStageKind(rawValue: rawOrPhaseName) {
            return exact
        }
        if rawOrPhaseName.contains("急") || rawOrPhaseName.contains("恢复") || rawOrPhaseName.contains("治标") {
            return .acuteRelief
        }
        if rawOrPhaseName.contains("祛") || rawOrPhaseName.contains("疏通") || rawOrPhaseName.contains("化湿") {
            return .dampnessClearing
        }
        if rawOrPhaseName.contains("扶正") || rawOrPhaseName.contains("健脾") || rawOrPhaseName.contains("补") {
            return .tonifying
        }
        return .maintenance
    }
}

enum RegimenPhaseStatus: String, Codable, Sendable {
    case active
    case needsReview
    case completed

    var displayName: String {
        switch self {
        case .active:
            return "进行中"
        case .needsReview:
            return "待复诊"
        case .completed:
            return "已转归"
        }
    }
}

@Model
final class RegimenPhase {
    var id: UUID
    var stageKindRawValue: String
    var phaseName: String
    var therapeuticPrinciple: String
    var exitCriteria: String
    var nextStageHint: String
    var startDate: Date
    var plannedDays: Int
    var statusRawValue: String
    var triggerSummary: String
    var updatedAt: Date

    var stageKind: RegimenStageKind {
        get { RegimenStageKind.infer(from: stageKindRawValue) }
        set { stageKindRawValue = newValue.rawValue }
    }

    var status: RegimenPhaseStatus {
        get { RegimenPhaseStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        stageKind: RegimenStageKind = .maintenance,
        phaseName: String = "日常顺时固本期",
        therapeuticPrinciple: String = "健脾化湿、温阳理气，循序渐进减重",
        exitCriteria: String = "排便成形、晨起轻快不困重且饮食作息规律",
        nextStageHint: String = "持续顺时固本，随二十四节气与天气微调",
        startDate: Date = .now,
        plannedDays: Int = 14,
        status: RegimenPhaseStatus = .active,
        triggerSummary: String = "基于初始体质画像建立",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.stageKindRawValue = stageKind.rawValue
        self.phaseName = phaseName
        self.therapeuticPrinciple = therapeuticPrinciple
        self.exitCriteria = exitCriteria
        self.nextStageHint = nextStageHint
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.plannedDays = max(1, plannedDays)
        self.statusRawValue = status.rawValue
        self.triggerSummary = triggerSummary
        self.updatedAt = updatedAt
    }

    func dayNumber(for date: Date = .now) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: date)
        let diff = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        return max(1, diff + 1)
    }

    func progressText(for date: Date = .now) -> String {
        let currentDay = dayNumber(for: date)
        if stageKind == .maintenance {
            return "第 \(currentDay) 天"
        }
        return "第 \(min(currentDay, plannedDays))/\(plannedDays) 天"
    }

    func badgeText(for date: Date = .now) -> String {
        "\(phaseName) (\(progressText(for: date)))"
    }

    func progressFraction(for date: Date = .now) -> Double {
        let currentDay = Double(dayNumber(for: date))
        return min(1.0, max(0.1, currentDay / Double(max(1, plannedDays))))
    }
}
