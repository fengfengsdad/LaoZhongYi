import Foundation
import SwiftData

@MainActor
enum MockDataSeeder {
    static func seedIfNeeded(in context: ModelContext) {
        let profileDescriptor = FetchDescriptor<UserConstitutionProfile>()
        let existingProfiles = (try? context.fetch(profileDescriptor)) ?? []

        if existingProfiles.isEmpty {
            let profile = UserConstitutionProfile(
                heightCM: 176.5,
                weightKG: 85.0,
                targetWeightKG: 75.0,
                constitutionTags: ["痰湿质78分", "轻微气虚", "肠胃敏感"],
                dietaryPreferences: ["忌生冷冰饮", "忌寒凉海鲜", "偏爱温热汤羹"],
                fitnessPreferences: ["室外游泳40min", "讨厌传统跑步有氧", "居家轻抗阻"],
                diningEnvironment: "居家做饭",
                rawReportSummary: "中医体质辨识：痰湿质偏颇（78分），兼有轻微气虚、脾胃运化偏弱。"
            )
            context.insert(profile)
        }

        let snapshotDescriptor = FetchDescriptor<DailyContextSnapshot>()
        let existingSnapshots = (try? context.fetch(snapshotDescriptor)) ?? []

        if existingSnapshots.isEmpty {
            let solar = SolarTermCalculator.term(for: .now)
            let snapshot = DailyContextSnapshot(
                date: .now,
                weatherTempC: 24.0,
                weatherCondition: "晴",
                city: "深圳",
                weatherHumidity: 68.0,
                weatherWindSpeedKmh: 9.0,
                weatherSource: "默认初始",
                solarTermName: solar.name,
                healthStepCount: nil,
                healthSleepHours: nil,
                healthLatestWeightKG: nil,
                userReportedSymptoms: [],
                recoveryPhase: "日常稳态调理期"
            )
            context.insert(snapshot)

            let cards = [
                ActionCard(
                    category: .diet,
                    timeSlot: "上午 09:30",
                    title: "生姜陈皮温胃水",
                    actionDetail: "老姜 2 片 + 5 年陈皮 3g，沸水焖泡 10 分钟温服，空腹或餐后半小时小口饮用。",
                    reasoning: "痰湿兼轻微气虚，\(solar.name)温中理气开启脾胃运化。",
                    isCompleted: true,
                    sortOrder: 0,
                    snapshot: snapshot
                ),
                ActionCard(
                    category: .diet,
                    timeSlot: "中午 12:00-13:30",
                    title: "冬瓜薏米瘦肉温汤 + 杂粮饭",
                    actionDetail: "居家现煮：炒薏米 20g、冬瓜 200g、瘦肉片 120g 少盐炖汤，搭配半碗温热糙米饭。",
                    reasoning: "高蛋白低脂且清淡祛湿，契合减重与居家饮食。",
                    isCompleted: false,
                    sortOrder: 1,
                    snapshot: snapshot
                ),
                ActionCard(
                    category: .fitness,
                    timeSlot: "下午 16:30-17:30",
                    title: "阳光下室外游泳(限时30min)",
                    actionDetail: "中等配速蛙泳/自由泳 30 分钟，避开冷水深潜，上岸后立即擦干并披薄外套。",
                    reasoning: "深圳 24°C 晴朗适宜下水，避开伤膝跑步有氧。",
                    isCompleted: false,
                    sortOrder: 2,
                    snapshot: snapshot
                ),
                ActionCard(
                    category: .lifestyle,
                    timeSlot: "晚上 21:30",
                    title: "温水泡脚 + 睡前 2 小时控水",
                    actionDetail: "40°C 温水泡脚 15 分钟至微汗即止；21:30 后仅抿口润喉，不大量饮水。",
                    reasoning: "痰湿体质夜间水湿易停滞，防晨起浮肿沉重。",
                    isCompleted: false,
                    sortOrder: 3,
                    snapshot: snapshot
                )
            ]

            for card in cards {
                context.insert(card)
            }
            snapshot.actionCards = cards
        }

        try? context.save()
    }
}
