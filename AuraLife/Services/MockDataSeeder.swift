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

        let phaseDescriptor = FetchDescriptor<RegimenPhase>()
        var existingPhases = (try? context.fetch(phaseDescriptor)) ?? []
        let activePhase: RegimenPhase
        if let found = existingPhases.first(where: { $0.status == .active }) ?? existingPhases.first {
            activePhase = found
        } else {
            let created = RegimenPhase(
                stageKind: .maintenance,
                phaseName: "日常顺时固本期",
                therapeuticPrinciple: "健脾化湿、温阳理气，循序渐进减重",
                exitCriteria: "排便成形、晨起轻快不困重且饮食作息平稳",
                nextStageHint: "持续顺时固本，随二十四节气与天气波动微调",
                startDate: .now,
                plannedDays: 14,
                status: .active,
                triggerSummary: "基于痰湿质78分画像建立初始稳态调理方案"
            )
            context.insert(created)
            existingPhases = [created]
            activePhase = created
        }

        let evolutionDescriptor = FetchDescriptor<ConstitutionEvolutionRecord>()
        let existingEvolutions = (try? context.fetch(evolutionDescriptor)) ?? []
        if existingEvolutions.isEmpty {
            let currentTags = (try? context.fetch(profileDescriptor))?.first?.constitutionTags ?? ["痰湿质78分", "轻微气虚", "肠胃敏感"]
            let baselineRecord = ConstitutionEvolutionRecord(
                date: .now,
                phaseName: activePhase.phaseName,
                stageKind: activePhase.stageKind,
                therapeuticPrinciple: activePhase.therapeuticPrinciple,
                outcomeTitle: "初始建档",
                clinicalNote: "依据体质辨识报告建立日常顺时调理基线。",
                constitutionSnapshotTags: currentTags,
                deltaSummary: "建立痰湿质顺时调理基线",
                toleranceNote: "偏爱温热汤羹、室外游泳，忌生冷冰饮"
            )
            context.insert(baselineRecord)
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
                recoveryPhase: activePhase.badgeText(for: .now),
                therapeuticPrinciple: activePhase.therapeuticPrinciple,
                regimenPhase: activePhase
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
                    category: .diet,
                    timeSlot: "傍晚 18:00-19:00",
                    title: "山药虾仁蒸蛋 + 蒜蓉油麦菜（轻食晚餐）",
                    actionDetail: "嫩豆腐蒸蛋配虾仁 80g、铁棍山药几块与清炒绿叶菜，七分饱不加主食或仅少许蒸南瓜。",
                    reasoning: "晚餐高蛋白低碳水且温热易化，减轻夜间脾胃积湿。",
                    isCompleted: false,
                    sortOrder: 3,
                    snapshot: snapshot
                ),
                ActionCard(
                    category: .lifestyle,
                    timeSlot: "晚上 21:30",
                    title: "温水泡脚 + 睡前 2 小时控水",
                    actionDetail: "40°C 温水泡脚 15 分钟至微汗即止；21:30 后仅抿口润喉，不大量饮水。",
                    reasoning: "痰湿体质夜间水湿易停滞，防晨起浮肿沉重。",
                    isCompleted: false,
                    sortOrder: 4,
                    snapshot: snapshot
                )
            ]

            for card in cards {
                context.insert(card)
            }
            snapshot.actionCards = cards
        } else {
            // 为从 Phase 1-4 升级上来的存量快照补全阶段关联
            for snap in existingSnapshots where snap.regimenPhase == nil {
                snap.regimenPhase = activePhase
                if snap.therapeuticPrinciple.isEmpty {
                    snap.therapeuticPrinciple = activePhase.therapeuticPrinciple
                }
            }
        }

        try? context.save()
    }
}
