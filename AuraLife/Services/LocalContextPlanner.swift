import Foundation

struct CardAdjustmentDiff: Identifiable, Sendable {
    let id = UUID()
    let dayOffset: Int
    let targetCardID: UUID?
    let category: ActionCategory
    let timeSlot: String
    let previousTitle: String?
    let updatedTitle: String
    let updatedDetail: String
    let updatedReasoning: String
    let sortOrder: Int

    var dayLabel: String {
        switch dayOffset {
        case 0:
            return "今日"
        case 1:
            return "明日"
        case 2:
            return "后日"
        default:
            return "第\(dayOffset + 1)天"
        }
    }
}

struct AdjustmentProposal: Identifiable, Sendable {
    let id = UUID()
    let userInput: String
    let triageSummary: String?
    let detectedSymptoms: [String]
    let proposedPhase: String
    let phaseSpec: AIRegimenPhasePayload
    let summary: String
    let source: AIServiceSource
    let diffs: [CardAdjustmentDiff]
}

struct SymptomTriageSession: Identifiable, Sendable {
    let id = UUID()
    let userInput: String
    let clarificationReason: String
    let questions: [AITriageQuestionPayload]
    let source: AIServiceSource
}

enum AdjustmentEvaluationOutcome: Sendable {
    case needsClarification(SymptomTriageSession)
    case ready(AdjustmentProposal)
}

/// 本地三层决策漏斗兜底规则器（用于 Preview、天气/健康突变联动、两段式轻问诊及离线演示模式）
enum LocalContextPlanner {
    static func isOutdoorSwimmingSuitable(
        tempC: Double,
        condition: String,
        windSpeedKmh: Double,
        isAcuteRecovery: Bool
    ) -> Bool {
        guard !isAcuteRecovery else { return false }
        let wetOrWindy = condition.contains("雨") || condition.contains("雪") || condition.contains("风")
        return tempC >= 20.0 && windSpeedKmh < 22.0 && !wetOrWindy
    }

    static func makeEvaluationOutcome(
        from response: AIAdjustmentResponse,
        userInput: String,
        triageAnswers: [AITriageAnswer] = [],
        source: AIServiceSource,
        snapshotsByOffset: [Int: DailyContextSnapshot]
    ) -> AdjustmentEvaluationOutcome {
        if response.needsClarification && triageAnswers.isEmpty {
            let session = SymptomTriageSession(
                userInput: userInput,
                clarificationReason: response.clarificationReason.isEmpty
                    ? "为区分寒湿与湿热等不同证型，请先确认以下 1~2 个细节。"
                    : response.clarificationReason,
                questions: response.triageQuestions,
                source: source
            )
            return .needsClarification(session)
        }

        let triageSummary = triageAnswers.isEmpty
            ? nil
            : triageAnswers.map { "\($0.selectedOption)" }.joined(separator: " · ")

        let mappedDiffs: [CardAdjustmentDiff] = response.diffs.enumerated().map { index, item in
            let daySnapshot = snapshotsByOffset[item.dayOffset]
            let targetUUID = item.targetCardID.flatMap(UUID.init(uuidString:))
            let matchedCard = targetUUID.flatMap { id in
                daySnapshot?.actionCards.first(where: { $0.id == id })
            }

            return CardAdjustmentDiff(
                dayOffset: max(0, item.dayOffset),
                targetCardID: matchedCard?.id,
                category: item.resolvedCategory,
                timeSlot: item.timeSlot,
                previousTitle: matchedCard?.title,
                updatedTitle: item.updatedTitle,
                updatedDetail: item.updatedDetail,
                updatedReasoning: item.clampedReasoning,
                sortOrder: matchedCard?.sortOrder ?? (daySnapshot?.actionCards.count ?? 0) + index
            )
        }

        return .ready(
            AdjustmentProposal(
                userInput: userInput,
                triageSummary: triageSummary,
                detectedSymptoms: response.detectedSymptoms,
                proposedPhase: response.proposedPhase,
                phaseSpec: response.phaseSpec,
                summary: response.summary,
                source: source,
                diffs: mappedDiffs
            )
        )
    }

    static func evaluateOfflineAdjustment(
        input: String,
        triageAnswers: [AITriageAnswer] = [],
        extraTriageNote: String? = nil,
        hasAttachedImage: Bool,
        photoIntent: PhotoCheckInIntent = .auto,
        recognizedPhotoText: String? = nil,
        diningEnvironment: String?,
        snapshot: AISnapshotContext
    ) -> AIAdjustmentResponse {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInput = trimmed.isEmpty && hasAttachedImage ? photoIntent.defaultPromptHint : trimmed

        let defaultPhaseSpec = AIRegimenPhasePayload(
            stageKind: snapshot.activePhase?.stageKind.rawValue ?? RegimenStageKind.maintenance.rawValue,
            phaseName: snapshot.activePhase?.phaseName ?? "日常顺时固本期",
            therapeuticPrinciple: snapshot.therapeuticPrinciple,
            plannedDays: snapshot.activePhase?.plannedDays ?? 14,
            exitCriteria: snapshot.activePhase?.exitCriteria ?? "排便成形、晨起轻快不困重且饮食作息平稳",
            nextStageHint: snapshot.activePhase?.nextStageHint ?? "持续顺时固本，随二十四节气微调"
        )

        // 第一段：若输入存在模糊症状且尚未做过辨证追问，则先触发轻问诊选择题
        if triageAnswers.isEmpty && !hasAttachedImage {
            if let triage = detectAmbiguousSymptomTriage(for: effectiveInput) {
                return AIAdjustmentResponse(
                    resolutionStatus: "needsClarification",
                    clarificationReason: triage.reason,
                    triageQuestions: triage.questions,
                    proposedPhase: snapshot.recoveryPhase,
                    phaseSpec: defaultPhaseSpec,
                    detectedSymptoms: snapshot.userReportedSymptoms,
                    summary: triage.reason,
                    diffs: []
                )
            }
        }

        // 第二段：结合追问答案（若存在）识别寒湿 / 湿热 / 气虚证型并给出调整方案
        let answerText = triageAnswers.map(\.selectedOption).joined(separator: " ")
        let extraText = extraTriageNote ?? ""
        let combinedSignal = "\(effectiveInput) \(answerText) \(extraText)"

        let isDampHeat = combinedSignal.contains("黏腻臭秽")
            || combinedSignal.contains("灼热")
            || combinedSignal.contains("口干口苦")
            || combinedSignal.contains("想喝凉水")
            || combinedSignal.contains("手足发热")

        let isColdDamp = combinedSignal.contains("水样")
            || combinedSignal.contains("怕凉")
            || combinedSignal.contains("怕冷")
            || combinedSignal.contains("畏寒")
            || combinedSignal.contains("螃蟹")
            || combinedSignal.contains("生冷")

        let existingCards = snapshot.cards
        var symptoms = snapshot.userReportedSymptoms
        var diffs: [AICardDiffPayload] = []

        if isDampHeat {
            if !symptoms.contains("湿热积滞信号") { symptoms.append("湿热积滞信号") }

            let dampHeatSpec = AIRegimenPhasePayload(
                stageKind: RegimenStageKind.dampnessClearing.rawValue,
                phaseName: "清化湿热恢复期",
                therapeuticPrinciple: "清热利湿、轻食导滞，忌生姜温燥与辛辣",
                plannedDays: 3,
                exitCriteria: "大便不黏腻灼热、口干口苦消退且胃肠舒畅",
                nextStageHint: "湿热退后转入「日常顺时固本期」，恢复均衡蛋白与运动"
            )

            if let dietMorning = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 0 }) {
                diffs.append(
                    AICardDiffPayload(
                        dayOffset: 0,
                        targetCardID: dietMorning.id.uuidString,
                        category: ActionCategory.diet.rawValue,
                        timeSlot: dietMorning.timeSlot,
                        updatedTitle: "冬瓜荷叶炒薏米淡饮（去姜）",
                        updatedDetail: "干荷叶 2g + 炒薏米 15g + 淡竹叶 3g 煮水放至微温饮用，暂撤生姜以免助热。",
                        updatedReasoning: "辨证属湿热偏盛，改用清利淡渗替换温燥姜水。",
                    )
                )
            }
            if let dietLunch = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 1 }) {
                diffs.append(
                    AICardDiffPayload(
                        dayOffset: 0,
                        targetCardID: dietLunch.id.uuidString,
                        category: ActionCategory.diet.rawValue,
                        timeSlot: dietLunch.timeSlot,
                        updatedTitle: "马齿苋/苦瓜清汤 + 白粥或杂粮",
                        updatedDetail: "清淡蔬菜汤配易消化主食，少油少盐，忌油炸、海鲜与辛辣调味。",
                        updatedReasoning: "湿热积滞宜清疏导滞，避免肥甘厚腻加重黏滞。",
                    )
                )
            }
            if let fitnessCard = existingCards.first(where: { $0.category == .fitness }) {
                diffs.append(
                    AICardDiffPayload(
                        dayOffset: 0,
                        targetCardID: fitnessCard.id.uuidString,
                        category: ActionCategory.fitness.rawValue,
                        timeSlot: "下午 17:00-17:30",
                        updatedTitle: "舒缓站姿导引 + 散步(20min)",
                        updatedDetail: "避免剧烈暴汗耗津，饭后室内或阴凉处慢步 20 分钟配合深呼吸。",
                        updatedReasoning: "湿热期以温和宣散为主，大汗反易伤津。",
                    )
                )
            }

            return AIAdjustmentResponse(
                resolutionStatus: "readyToAdjust",
                clarificationReason: "",
                triageQuestions: [],
                proposedPhase: "\(dampHeatSpec.phaseName) (第1/3天)",
                phaseSpec: dampHeatSpec,
                detectedSymptoms: symptoms,
                summary: "结合追问判定偏「湿热积滞」，已撤去温燥姜饮，切换为清化湿热与轻食导滞方案。",
                diffs: diffs
            )
        }

        // 若偏寒湿或走常规离线判断
        let proposal = proposeOfflineAdjustment(
            input: isColdDamp ? "\(effectiveInput) 寒湿怕冷" : effectiveInput,
            hasAttachedImage: hasAttachedImage,
            photoIntent: photoIntent,
            recognizedPhotoText: recognizedPhotoText,
            diningEnvironment: diningEnvironment,
            snapshot: snapshot
        )

        var mappedDiffs = proposal.diffs.map { diff in
            AICardDiffPayload(
                dayOffset: diff.dayOffset,
                targetCardID: diff.targetCardID?.uuidString,
                category: diff.category.rawValue,
                timeSlot: diff.timeSlot,
                updatedTitle: diff.updatedTitle,
                updatedDetail: diff.updatedDetail,
                updatedReasoning: diff.updatedReasoning
            )
        }

        if proposal.phaseSpec.resolvedStageKind == .acuteRelief {
            mappedDiffs.append(
                AICardDiffPayload(
                    dayOffset: 1,
                    targetCardID: nil,
                    category: ActionCategory.diet.rawValue,
                    timeSlot: "中午 12:00-13:30",
                    updatedTitle: "明日衔接：清蒸鲈鱼 + 温热软米饭",
                    updatedDetail: "恢复期第2天继续忌生冷海鲜，采用高蛋白温热软食巩固脾胃。",
                    updatedReasoning: "延续3日恢复节奏，防肠胃二次受凉。"
                )
            )
        }

        return AIAdjustmentResponse(
            resolutionStatus: "readyToAdjust",
            clarificationReason: "",
            triageQuestions: [],
            proposedPhase: proposal.proposedPhase,
            phaseSpec: proposal.phaseSpec,
            detectedSymptoms: proposal.detectedSymptoms,
            summary: triageAnswers.isEmpty
                ? proposal.summary
                : "结合轻问诊补充辨证（\(triageAnswers.map(\.selectedOption).joined(separator: "、"))），\(proposal.summary)",
            diffs: mappedDiffs
        )
    }

    private static func detectAmbiguousSymptomTriage(
        for input: String
    ) -> (reason: String, questions: [AITriageQuestionPayload])? {
        let alreadyClear = input.contains("螃蟹")
            || input.contains("发黏")
            || input.contains("黏")
            || input.contains("水样")
            || input.contains("怕冷")
            || input.contains("口苦")
            || input.contains("室内")
            || input.contains("不去游")
            || input.contains("掉肌肉")
            || input.contains("天气")
            || input.contains("降温")
            || input.contains("下雨")

        guard !alreadyClear else { return nil }

        let giKeywords = ["吃坏", "拉肚子", "腹泻", "肚子疼", "胃不舒服", "胃胀", "反酸", "拉稀"]
        if giKeywords.contains(where: input.contains) {
            return (
                reason: "「肠胃不适」在中医里寒湿与湿热食养截然相反（姜饮只适合偏寒），先确认 2 个细节：",
                questions: [
                    AITriageQuestionPayload(
                        id: "gi_stool",
                        question: "腹部与排便更偏向哪种感受？",
                        options: ["偏水样清稀 / 腹部怕凉", "偏黏腻臭秽 / 肛门灼热", "只是胃胀隐痛 / 暂无腹泻"]
                    ),
                    AITriageQuestionPayload(
                        id: "gi_thermal",
                        question: "伴随的口渴与寒热体感？",
                        options: ["偏怕冷手脚凉 / 喜热饮", "口干口苦 / 想喝凉水", "仅觉乏力 / 均不明显"]
                    )
                ]
            )
        }

        let generalSymptomKeywords = ["腰酸", "没胃口", "不舒服", "头晕", "困倦", "乏力", "上火", "嗓子", "感冒"]
        if generalSymptomKeywords.contains(where: input.contains) {
            return (
                reason: "同一体感可能对应气虚、寒湿或湿热偏颇，先核对 2 项寒热与作息线索：",
                questions: [
                    AITriageQuestionPayload(
                        id: "symptom_thermal",
                        question: "当下整体体感更偏寒还是偏热？",
                        options: ["偏畏寒怕冷 / 腰腹发凉", "偏心烦口苦 / 口干发热", "主要困重乏力、不偏寒热"]
                    ),
                    AITriageQuestionPayload(
                        id: "symptom_trigger",
                        question: "近期是否有明显诱因？",
                        options: ["昨晚熬夜 / 睡眠不足", "吃了生冷海鲜或油腻大餐", "久坐受凉 / 无明显诱因"]
                    )
                ]
            )
        }

        return nil
    }

    static func proposeOfflineAdjustment(
        input: String,
        hasAttachedImage: Bool,
        photoIntent: PhotoCheckInIntent = .auto,
        recognizedPhotoText: String? = nil,
        diningEnvironment: String?,
        snapshot: AISnapshotContext
    ) -> AdjustmentProposal {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInput = trimmed.isEmpty && hasAttachedImage ? photoIntent.defaultPromptHint : trimmed

        var symptoms = snapshot.userReportedSymptoms
        var isAcute = false

        let acuteSignals: [(String, String)] = [
            ("熬夜", "昨晚熬夜"),
            ("晚睡", "昨晚熬夜"),
            ("螃蟹", "吃了寒凉海鲜"),
            ("海鲜", "吃了寒凉海鲜"),
            ("生冷", "饮食偏寒凉"),
            ("寒湿", "寒湿困脾"),
            ("怕冷", "畏寒受凉"),
            ("大便", "排便异常/肠胃不适"),
            ("拉肚子", "肠胃腹泻不适"),
            ("吃坏", "急性肠胃不适"),
            ("腰酸", "晨起腰酸"),
            ("舌苔", "舌苔偏腻")
        ]

        for (keyword, label) in acuteSignals where effectiveInput.contains(keyword) {
            isAcute = true
            if !symptoms.contains(label) {
                symptoms.append(label)
            }
        }

        if let sleepHours = snapshot.healthSleepHours, sleepHours < 6.5 {
            isAcute = true
            let sleepTag = String(format: "睡眠偏短(%.1fh)", sleepHours)
            if !symptoms.contains(sleepTag) {
                symptoms.append(sleepTag)
            }
        }

        if hasAttachedImage {
            switch photoIntent {
            case .tongue:
                isAcute = true
                if !symptoms.contains("舌象偏腻待化湿") { symptoms.append("舌象偏腻待化湿") }
            case .meal:
                if !symptoms.contains("餐食照片已评估") { symptoms.append("餐食照片已评估") }
            case .report:
                if !symptoms.contains("体检/体质报告已解析") { symptoms.append("体检/体质报告已解析") }
            case .auto:
                isAcute = true
                if !symptoms.contains("已附状态照片") { symptoms.append("已附状态照片") }
            }
        }

        let defaultPhaseSpec = AIRegimenPhasePayload(
            stageKind: snapshot.activePhase?.stageKind.rawValue ?? RegimenStageKind.maintenance.rawValue,
            phaseName: snapshot.activePhase?.phaseName ?? "日常顺时固本期",
            therapeuticPrinciple: snapshot.therapeuticPrinciple,
            plannedDays: snapshot.activePhase?.plannedDays ?? 14,
            exitCriteria: snapshot.activePhase?.exitCriteria ?? "排便成形、晨起轻快不困重且饮食作息平稳",
            nextStageHint: snapshot.activePhase?.nextStageHint ?? "持续顺时固本，随二十四节气微调"
        )

        let existingCards = snapshot.cards
        var diffs: [CardAdjustmentDiff] = []

        // 多模态餐食打卡场景
        if hasAttachedImage && photoIntent == .meal && !isAcute {
            if let dietLunch = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 1 }) {
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dietLunch.id,
                        category: .diet,
                        timeSlot: "下一餐 / 晚餐调整",
                        previousTitle: dietLunch.title,
                        updatedTitle: "陈皮冬瓜山药轻膳汤 + 半碗杂粮",
                        updatedDetail: "结合餐食照片评估：下一餐减少油脂与精制碳水，补足温热绿叶菜与清炖高蛋白。",
                        updatedReasoning: "餐食评估后轻断油腻，防痰湿积聚。",
                        sortOrder: dietLunch.sortOrder
                    )
                )
            }
            if let fitnessCard = existingCards.first(where: { $0.category == .fitness }) {
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: fitnessCard.id,
                        category: .fitness,
                        timeSlot: "餐后 40 分钟",
                        previousTitle: fitnessCard.title,
                        updatedTitle: "餐后舒缓站立 + 靠墙静蹲(15min)",
                        updatedDetail: "餐后先慢走 15 分钟消食，再做 3 组靠墙静蹲提升胰岛素敏感性。",
                        updatedReasoning: "结合餐后血糖波动与痰湿运化节奏微调。",
                        sortOrder: fitnessCard.sortOrder
                    )
                )
            }
            let clearingSpec = AIRegimenPhasePayload(
                stageKind: RegimenStageKind.dampnessClearing.rawValue,
                phaseName: "轻消导祛湿期",
                therapeuticPrinciple: "消食导滞、清化痰湿，餐后温和助运",
                plannedDays: 2,
                exitCriteria: "餐后无腹胀饱滞、次日晨起舌苔清爽",
                nextStageHint: "转回「日常顺时固本期」继续常规调理"
            )
            return AdjustmentProposal(
                userInput: effectiveInput,
                triageSummary: nil,
                detectedSymptoms: symptoms,
                proposedPhase: "\(clearingSpec.phaseName) (第1/2天)",
                phaseSpec: clearingSpec,
                summary: "已结合餐食照片及\(snapshot.city) \(Int(snapshot.weatherTempC.rounded()))°C 气象条件切换为轻消导方案。",
                source: .offlineDemo,
                diffs: diffs
            )
        }

        // Layer 1: 安全与急症优先
        if isAcute {
            let acuteSpec = AIRegimenPhasePayload(
                stageKind: RegimenStageKind.acuteRelief.rawValue,
                phaseName: "急性祛湿恢复期",
                therapeuticPrinciple: "温中散寒、先护胃气，暂缓减重与生冷",
                plannedDays: 3,
                exitCriteria: "排便成形不黏腻、胃脘温暖无胀闷且精神恢复",
                nextStageHint: "转入「祛邪疏通期」，逐步恢复蛋白与微抗阻"
            )
            let phase = "\(acuteSpec.phaseName) (第1/3天)"

            if let dietMorning = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 0 }) {
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dietMorning.id,
                        category: .diet,
                        timeSlot: dietMorning.timeSlot,
                        previousTitle: dietMorning.title,
                        updatedTitle: "炒薏米陈皮焦米温胃水",
                        updatedDetail: "炒薏米 15g + 陈皮 3g + 炒大米 10g 煮水 15 分钟温饮，先护脾胃再温和化湿。",
                        updatedReasoning: "熬夜或受寒湿扰胃，优先温中燥湿护脾。",
                        sortOrder: 0
                    )
                )
            }

            if let dietLunch = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 1 }) {
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dietLunch.id,
                        category: .diet,
                        timeSlot: dietLunch.timeSlot,
                        previousTitle: dietLunch.title,
                        updatedTitle: "山药白扁豆小米暖胃粥",
                        updatedDetail: "怀山药 80g、炒白扁豆 15g、小米煮至绵软，配清蒸鸡胸肉 100g，忌生冷油腻。",
                        updatedReasoning: "急症期暂停寒凉与粗硬纤维，减轻脾胃负担。",
                        sortOrder: 1
                    )
                )
            }

            if let fitnessCard = existingCards.first(where: { $0.category == .fitness }) {
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: fitnessCard.id,
                        category: .fitness,
                        timeSlot: "下午 17:00-17:30",
                        previousTitle: fitnessCard.title,
                        updatedTitle: "居家八段锦 + 靠墙静蹲(15min)",
                        updatedDetail: "取消下水游泳，改为八段锦两遍（重点调理脾胃须单举）+ 靠墙静蹲 3 组 × 45 秒。",
                        updatedReasoning: "疲劳受寒后防毛孔受凉，用温和导引代替游泳。",
                        sortOrder: fitnessCard.sortOrder
                    )
                )
            }

            return AdjustmentProposal(
                userInput: effectiveInput,
                triageSummary: nil,
                detectedSymptoms: symptoms,
                proposedPhase: phase,
                phaseSpec: acuteSpec,
                summary: "识别到短期脾胃受寒、疲劳或舌苔信号，已按「急则治其标」切换至 3 天温和恢复期。",
                source: .offlineDemo,
                diffs: diffs
            )
        }

        // Layer 2: 环境气象与偏好适配
        let tempC = Int(snapshot.weatherTempC.rounded())
        let humidity = Int(snapshot.weatherHumidity.rounded())
        let swimSuitable = isOutdoorSwimmingSuitable(
            tempC: snapshot.weatherTempC,
            condition: snapshot.weatherCondition,
            windSpeedKmh: snapshot.weatherWindSpeedKmh,
            isAcuteRecovery: false
        )

        if effectiveInput.contains("天气") || effectiveInput.contains("降温") || effectiveInput.contains("下雨") || !swimSuitable {
            if let fitnessCard = existingCards.first(where: { $0.category == .fitness }) {
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: fitnessCard.id,
                        category: .fitness,
                        timeSlot: fitnessCard.timeSlot,
                        previousTitle: fitnessCard.title,
                        updatedTitle: swimSuitable ? "阳光下室外游泳(限时30min)" : "居家靠墙静蹲 + 弹力带抗阻(25min)",
                        updatedDetail: swimSuitable
                            ? "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)，适度蛙泳/自由泳 30 分钟，上岸立刻擦干披外套。"
                            : "\(snapshot.city)当前 \(tempC)°C \(snapshot.weatherCondition)（湿度 \(humidity)%），室内进行靠墙静蹲 3×45s + 弹力带划船 3×15。",
                        updatedReasoning: swimSuitable
                            ? "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)适宜下水，避开伤膝跑步。"
                            : "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)不宜下水，切居家抗阻。",
                        sortOrder: fitnessCard.sortOrder
                    )
                )
            }

            if humidity >= 80, let dietMorning = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 0 }) {
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dietMorning.id,
                        category: .diet,
                        timeSlot: dietMorning.timeSlot,
                        previousTitle: dietMorning.title,
                        updatedTitle: "炒薏米陈皮茯苓祛湿茶",
                        updatedDetail: "炒薏米 15g、茯苓 6g、陈皮 3g 煮水代茶，今日湿度高达 \(humidity)% 更需健脾利湿。",
                        updatedReasoning: "湿度 \(humidity)% 偏重，痰湿体质加强健脾化湿。",
                        sortOrder: 0
                    )
                )
            }

            let weatherSpec = AIRegimenPhasePayload(
                stageKind: humidity >= 80 ? RegimenStageKind.dampnessClearing.rawValue : defaultPhaseSpec.stageKind,
                phaseName: humidity >= 80 ? "祛湿避寒顺时期" : defaultPhaseSpec.phaseName,
                therapeuticPrinciple: humidity >= 80 ? "健脾利湿、防外湿引动内湿，转入室内导引" : "顺应天时、避风寒护阳，保持轻度抗阻代谢",
                plannedDays: defaultPhaseSpec.plannedDays,
                exitCriteria: defaultPhaseSpec.exitCriteria,
                nextStageHint: defaultPhaseSpec.nextStageHint
            )

            return AdjustmentProposal(
                userInput: effectiveInput,
                triageSummary: nil,
                detectedSymptoms: symptoms,
                proposedPhase: weatherSpec.phaseName,
                phaseSpec: weatherSpec,
                summary: "已结合\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)（湿度 \(humidity)%）与\(snapshot.solarTermName)节气重新适配今日运动与食养。",
                source: .offlineDemo,
                diffs: diffs
            )
        }

        if effectiveInput.contains("室内") || effectiveInput.contains("不去游") || effectiveInput.contains("不想") {
            if let fitnessCard = existingCards.first(where: { $0.category == .fitness }) {
                let reason = (effectiveInput.contains("掉肌肉") || effectiveInput.contains("抗阻"))
                    ? "用轻抗阻保肌减脂，同样适合痰湿体质代谢。"
                    : "按当前场景切换室内抗阻，免去出行且不伤膝盖。"

                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: fitnessCard.id,
                        category: .fitness,
                        timeSlot: fitnessCard.timeSlot,
                        previousTitle: fitnessCard.title,
                        updatedTitle: "居家哑铃/弹力带微抗阻(25min)",
                        updatedDetail: "高脚杯深蹲 3×12、弹力带划船 3×15、死虫式核心 3×12，组间休息 60 秒。",
                        updatedReasoning: reason,
                        sortOrder: fitnessCard.sortOrder
                    )
                )
            }

            return AdjustmentProposal(
                userInput: effectiveInput,
                triageSummary: nil,
                detectedSymptoms: symptoms,
                proposedPhase: snapshot.recoveryPhase,
                phaseSpec: defaultPhaseSpec,
                summary: "已依据你的即时运动偏好与减重保肌目标，将今日训练切换为居家轻量抗阻。",
                source: .offlineDemo,
                diffs: diffs
            )
        }

        let diningEnv = diningEnvironment ?? "居家做饭"
        let ocrSnippet = recognizedPhotoText.flatMap { text -> String? in
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : String(cleaned.prefix(24))
        }
        if let dietLunch = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 1 }) {
            diffs.append(
                CardAdjustmentDiff(
                    dayOffset: 0,
                    targetCardID: dietLunch.id,
                    category: .diet,
                    timeSlot: dietLunch.timeSlot,
                    previousTitle: dietLunch.title,
                    updatedTitle: diningEnv == "外卖" ? "清汤鸡肉米粉（去冰少油）" : "茯苓山药蒸鸡腿配时蔬",
                    updatedDetail: "今日\(diningEnv)场景优先选温热易消化蛋白，七分饱停筷，餐后站立 15 分钟。"
                        + (ocrSnippet.map { "（参考识别信息：\($0)）" } ?? ""),
                    updatedReasoning: "结合「\(effectiveInput.prefix(8))」与\(snapshot.solarTermName)节气微调。",
                    sortOrder: dietLunch.sortOrder
                )
            )
        }

        return AdjustmentProposal(
            userInput: effectiveInput,
            triageSummary: nil,
            detectedSymptoms: symptoms,
            proposedPhase: snapshot.recoveryPhase,
            phaseSpec: defaultPhaseSpec,
            summary: "已记录你今天的状态反馈，并结合\(snapshot.city) \(tempC)°C 天气做了温和微调。",
            source: .offlineDemo,
            diffs: diffs
        )
    }

    @MainActor
    static func proposeAdjustment(
        input: String,
        hasAttachedImage: Bool,
        profile: UserConstitutionProfile?,
        snapshot: DailyContextSnapshot
    ) -> AdjustmentProposal {
        proposeOfflineAdjustment(
            input: input,
            hasAttachedImage: hasAttachedImage,
            photoIntent: .auto,
            recognizedPhotoText: nil,
            diningEnvironment: profile?.diningEnvironment,
            snapshot: AISnapshotContext(snapshot: snapshot)
        )
    }

    static func swapAlternative(
        category: ActionCategory,
        excludingTitle: String,
        isAcuteRecovery: Bool,
        weatherTempC: Double,
        weatherCondition: String,
        city: String,
        diningEnvironment: String?
    ) -> (title: String, detail: String, reasoning: String) {
        let isAcute = isAcuteRecovery
        let tempC = Int(weatherTempC.rounded())
        let swimSuitable = isOutdoorSwimmingSuitable(
            tempC: weatherTempC,
            condition: weatherCondition,
            windSpeedKmh: 9.0,
            isAcuteRecovery: isAcute
        )

        switch category {
        case .diet:
            let pool: [(String, String, String)] = isAcute ? [
                (
                    "红枣生姜陈皮饮",
                    "去核红枣 2 颗、生姜 2 片、陈皮 2g 煮沸焖泡，温热小口慢饮。",
                    "急性恢复期暖胃散寒，兼顾轻微气虚提神。"
                ),
                (
                    "猴头菇山药温胃羹",
                    "猴头菇干品泡发炖汤，加入铁棍山药块，少盐清淡，配半碗软米饭。",
                    "粘膜修复期温和养胃，避免加重痰湿停滞。"
                ),
                (
                    "炒白术茯苓温茶",
                    "茯苓 6g + 炒白术 5g 代茶饮，下午 4 点前温服完毕。",
                    "健脾益气燥湿，缓解午后困倦与大便粘滞。"
                )
            ] : [
                (
                    "陈皮荷叶祛湿轻饮",
                    "老陈皮 3g + 干荷叶 2g 沸水冲泡，上午代茶饮用，忌冰镇。",
                    "痰湿体质化浊醒脾，助力减重期代谢。"
                ),
                (
                    "清蒸鲈鱼 + 清炒芥兰",
                    "鲈鱼 180g 姜葱清蒸，搭配少油蒜蓉芥兰与杂粮饭半碗。",
                    "符合\(diningEnvironment ?? "居家")场景，高蛋白不生痰湿。"
                ),
                (
                    "芡实莲子瘦肉汤",
                    "芡实 15g、去芯莲子 10g、瘦肉 120g 隔水炖 40 分钟。",
                    "健脾固肾、补而不腻，适合气虚兼痰湿人群。"
                )
            ]

            return nextCandidate(from: pool, excludingTitle: excludingTitle)

        case .fitness:
            let pool: [(String, String, String)] = !swimSuitable ? [
                (
                    "居家八段锦 + 腹式呼吸(15min)",
                    "重点练习「调理脾胃须单举」与「双手托天理三焦」，全程鼻吸口呼至微微发热。",
                    "\(city) \(tempC)°C \(weatherCondition)，微汗通络更护阳气。"
                ),
                (
                    "弹力带坐姿划船 + 臀桥(20min)",
                    "弹力带划船 3×15、自重臀桥 3×15、猫牛式伸展 2 分钟，保持呼吸均匀。",
                    "零冲击居家抗阻，维持肌肉量同时不伤关节。"
                )
            ] : [
                (
                    "室外慢游 + 池边拉伸(35min)",
                    "保持心率 125-135 的轻松蛙泳 25 分钟，配合 10 分钟肩背水中放松。",
                    "\(city) \(tempC)°C \(weatherCondition)，水中减负燃脂更护膝。"
                ),
                (
                    "居家壶铃/哑铃循环(25min)",
                    "哑铃推举 3×12、箱式深蹲 3×12、农夫行走 3×30 秒，全程不跑跳。",
                    "避开传统跑步有氧，用复合抗阻提升基础代谢。"
                )
            ]

            return nextCandidate(from: pool, excludingTitle: excludingTitle)

        case .lifestyle:
            let pool: [(String, String, String)] = [
                (
                    "揉腹顺气 + 23:00 前熄灯",
                    "睡前仰卧顺时针轻柔摩腹 36 圈，放下手机调暗灯光，保证 7.5 小时睡眠。",
                    "痰湿体质重在助脾胃夜运，避免熬夜耗伤脾气。"
                ),
                (
                    "艾草温水泡脚 + 踝泵拉伸",
                    "40°C 温水泡脚 12 分钟，擦干后做 20 次勾脚绷脚促进下肢回流。",
                    "温通下焦经络，减轻白天久坐引起的下肢沉重。"
                )
            ]

            return nextCandidate(from: pool, excludingTitle: excludingTitle)
        }
    }

    private static func nextCandidate(
        from pool: [(String, String, String)],
        excludingTitle: String
    ) -> (title: String, detail: String, reasoning: String) {
        if let currentIndex = pool.firstIndex(where: { $0.0 == excludingTitle }) {
            let nextIndex = (currentIndex + 1) % pool.count
            return pool[nextIndex]
        }
        return pool.first ?? (excludingTitle, "", "")
    }
}
