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

    var nextTypicalStage: RegimenStageKind {
        switch self {
        case .acuteRelief:
            return .dampnessClearing
        case .dampnessClearing:
            return .tonifying
        case .tonifying, .maintenance:
            return .maintenance
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

enum FollowUpOutcome: String, CaseIterable, Identifiable, Sendable {
    case improved
    case steadyContinue
    case persistingOrWorse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .improved:
            return "明显好转，可考虑转段"
        case .steadyContinue:
            return "略有改善，延续当前调理"
        case .persistingOrWorse:
            return "仍有不适或出现新变化"
        }
    }

    var subtitle: String {
        switch self {
        case .improved:
            return "已接近或达到转段标准，推进至下一调理阶段"
        case .steadyContinue:
            return "体感减轻但尚未稳固，延长 1～2 天温和巩固"
        case .persistingOrWorse:
            return "症状反复或有新诱因，由 AI 重新评估治法与食谱"
        }
    }

    var systemImage: String {
        switch self {
        case .improved:
            return "checkmark.seal.fill"
        case .steadyContinue:
            return "arrow.clockwise.heart.fill"
        case .persistingOrWorse:
            return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .improved:
            return AuraTheme.sageGreen
        case .steadyContinue:
            return AuraTheme.inkSlate
        case .persistingOrWorse:
            return AuraTheme.warmGinger
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
    var lastFollowUpDate: Date?
    var greenLightFoods: [String] = []
    var yellowLightFoods: [String] = []
    var redLightFoods: [String] = []
    var dietaryFlexibilityNote: String = "推荐菜单仅作示范，吃七八分饱即可；饿了可从绿灯加餐，不必硬扛。"
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
        lastFollowUpDate: Date? = nil,
        greenLightFoods: [String] = [],
        yellowLightFoods: [String] = [],
        redLightFoods: [String] = [],
        dietaryFlexibilityNote: String = "推荐菜单仅作示范，吃七八分饱即可；饿了可从绿灯加餐，不必硬扛。",
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
        self.lastFollowUpDate = lastFollowUpDate
        self.greenLightFoods = greenLightFoods
        self.yellowLightFoods = yellowLightFoods
        self.redLightFoods = redLightFoods
        self.dietaryFlexibilityNote = dietaryFlexibilityNote
        self.updatedAt = updatedAt
    }

    var resolvedDietaryBoundary: (green: [String], yellow: [String], red: [String], flexibility: String) {
        if !greenLightFoods.isEmpty || !redLightFoods.isEmpty {
            return (
                greenLightFoods,
                yellowLightFoods.isEmpty ? ["精制米面减半", "温和水果少量"] : yellowLightFoods,
                redLightFoods,
                dietaryFlexibilityNote
            )
        }
        switch stageKind {
        case .acuteRelief:
            return (
                ["温热小米粥", "蒸山药/南瓜", "水煮蛋/嫩豆腐", "焦米陈皮水"],
                ["去皮鸡肉丝", "温软米饭半碗"],
                ["冰饮冷食", "螃蟹等寒凉海鲜", "辛辣油炸", "生冷沙拉水果"],
                "急症护胃期重在减轻消化负担，吃不惯可换成温粥+蒸蛋，饿了喝温热米汤或吃两块蒸山药，千万别硬饿。"
            )
        case .dampnessClearing:
            return (
                ["冬瓜/丝瓜/苦瓜", "嫩豆腐/去皮鸡肉", "炒薏米陈皮茶", "清蒸鱼虾（不忌口时）"],
                ["杂粮饭半碗", "贝贝南瓜/玉米"],
                ["奶茶甜食", "油炸烧烤", "冰镇啤酒/冷饮", "粘腻糯米糕点"],
                "这阶段的菜谱只是省心示范，只要做到「温热 + 清淡少油 + 优质蛋白」，聚餐或外卖换同类菜完全算达标。"
            )
        case .tonifying, .maintenance:
            return (
                ["水煮蛋/蒸蛋", "温热无糖豆浆", "蒸山药/玉米", "清炖瘦肉/鸡胸/豆腐", "时令温热绿叶菜"],
                ["糙米/杂粮饭半碗", "常温微甜水果少量"],
                ["冰镇饮品", "高糖奶茶糕点", "宵夜烧烤炸物", "过量寒凉海鲜"],
                "不必把推荐食谱当考卷：按推荐吃到七八分饱，两餐间或晚间还饿时直接从绿灯区补一点蛋白或山药，偶尔聚餐偏离，下一餐清淡拉回即可。"
            )
        }
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

    func shouldSuggestFollowUp(on date: Date = .now) -> Bool {
        let calendar = Calendar.current
        if let last = lastFollowUpDate, calendar.isDate(last, inSameDayAs: date) {
            return false
        }
        if status == .needsReview {
            return true
        }
        guard status == .active else { return false }
        let currentDay = dayNumber(for: date)
        if stageKind == .maintenance {
            return currentDay >= plannedDays
        }
        return currentDay >= min(2, plannedDays)
    }
}
