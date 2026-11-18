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
    let corePrinciple: String
    let flexibleSwapHint: String
    let sortOrder: Int

    init(
        dayOffset: Int,
        targetCardID: UUID?,
        category: ActionCategory,
        timeSlot: String,
        previousTitle: String?,
        updatedTitle: String,
        updatedDetail: String,
        updatedReasoning: String,
        corePrinciple: String = "",
        flexibleSwapHint: String = "",
        sortOrder: Int
    ) {
        self.dayOffset = dayOffset
        self.targetCardID = targetCardID
        self.category = category
        self.timeSlot = timeSlot
        self.previousTitle = previousTitle
        self.updatedTitle = updatedTitle
        self.updatedDetail = updatedDetail
        self.updatedReasoning = updatedReasoning
        self.corePrinciple = corePrinciple
        self.flexibleSwapHint = flexibleSwapHint
        self.sortOrder = sortOrder
    }

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
    case redFlag(RedFlagAssessment)
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
        if response.isRedFlagWarning {
            let localFlag = RedFlagDetector.evaluate(input: userInput)
            let assessment = RedFlagAssessment(
                userInput: userInput,
                category: localFlag?.category ?? .acuteAbdomenOrFever,
                matchedKeywords: localFlag?.matchedKeywords ?? [],
                headline: "AI 检测到潜在医疗红线信号，建议暂缓食疗并线下排查",
                medicalGuidance: response.summary.isEmpty
                    ? (localFlag?.medicalGuidance ?? "当前描述存在潜在器质性病变风险，请及时前往医院明确诊断。")
                    : response.summary,
                suggestedDepartment: response.redFlagAdvice.isEmpty
                    ? (localFlag?.suggestedDepartment ?? "建议前往急诊或相应专科进行基础检查")
                    : response.redFlagAdvice,
                falsePositiveHint: localFlag?.falsePositiveHint ?? "若症状持续或加重，请第一时间线下就医。",
                allowsOverrideAsMild: localFlag?.allowsOverrideAsMild ?? false
            )
            return .redFlag(assessment)
        }

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
                corePrinciple: item.corePrinciple,
                flexibleSwapHint: item.flexibleSwapHint,
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
        bypassRedFlag: Bool = false,
        hasAttachedImage: Bool,
        photoIntent: PhotoCheckInIntent = .auto,
        recognizedPhotoText: String? = nil,
        diningEnvironment: String?,
        dietaryPreferences: [String] = [],
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

        // 第零段：器质性红线熔断（除非用户已确认排除食物/药物染色）
        if !bypassRedFlag, let redFlag = RedFlagDetector.evaluate(input: "\(effectiveInput) \(extraTriageNote ?? "")") {
            return AIAdjustmentResponse(
                resolutionStatus: "redFlagWarning",
                clarificationReason: "",
                redFlagAdvice: redFlag.suggestedDepartment,
                triageQuestions: [],
                proposedPhase: snapshot.recoveryPhase,
                phaseSpec: defaultPhaseSpec,
                detectedSymptoms: snapshot.userReportedSymptoms,
                summary: redFlag.medicalGuidance,
                diffs: []
            )
        }

        // 第一段：若输入存在模糊症状且尚未做过辨证追问，则先触发轻问诊选择题
        if triageAnswers.isEmpty && !hasAttachedImage {
            if let triage = detectAmbiguousSymptomTriage(for: effectiveInput) {
                return AIAdjustmentResponse(
                    resolutionStatus: "needsClarification",
                    clarificationReason: triage.reason,
                    redFlagAdvice: "",
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
                let adapted = DietaryAdaptationHelper.adaptCard(
                    title: "温热白粥配蒸豆腐 + 餐后冬瓜荷叶淡饮（去姜）",
                    detail: "先吃半碗温热白粥配嫩豆腐或水煮蛋垫胃；餐后泡饮干荷叶 2g + 炒薏米 15g，暂撤生姜以免助热。",
                    reasoning: "湿热偏盛先垫温粥保胃气，改用清利淡渗替换姜水。",
                    timeSlot: "上午 08:00-09:00",
                    diningEnvironment: diningEnvironment ?? "居家做饭",
                    dietaryPreferences: dietaryPreferences
                )
                diffs.append(
                    AICardDiffPayload(
                        dayOffset: 0,
                        targetCardID: dietMorning.id.uuidString,
                        category: ActionCategory.diet.rawValue,
                        timeSlot: "上午 08:00-09:00",
                        updatedTitle: adapted.title,
                        updatedDetail: adapted.detail,
                        updatedReasoning: adapted.reasoning
                    )
                )
            }
            if let dietLunch = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 1 }) {
                let adapted = DietaryAdaptationHelper.adaptCard(
                    title: "马齿苋/冬瓜清汤 + 白粥或杂粮",
                    detail: "清淡蔬菜汤配易消化主食，少油少盐，忌油炸、海鲜与辛辣调味。",
                    reasoning: "湿热积滞宜清疏导滞，避免肥甘厚腻加重黏滞。",
                    timeSlot: dietLunch.timeSlot,
                    diningEnvironment: diningEnvironment ?? "居家做饭",
                    dietaryPreferences: dietaryPreferences
                )
                diffs.append(
                    AICardDiffPayload(
                        dayOffset: 0,
                        targetCardID: dietLunch.id.uuidString,
                        category: ActionCategory.diet.rawValue,
                        timeSlot: dietLunch.timeSlot,
                        updatedTitle: adapted.title,
                        updatedDetail: adapted.detail,
                        updatedReasoning: adapted.reasoning
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
                redFlagAdvice: "",
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
            dietaryPreferences: dietaryPreferences,
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
            redFlagAdvice: "",
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
        dietaryPreferences: [String] = [],
        snapshot: AISnapshotContext
    ) -> AdjustmentProposal {
        let env = diningEnvironment ?? "居家做饭"
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
                let adapted = DietaryAdaptationHelper.adaptCard(
                    title: "温热小米粥配水煮蛋 + 餐后炒薏米焦米水",
                    detail: "先吃半碗温热小米粥配水煮蛋垫胃；餐后温饮炒薏米 15g + 陈皮 3g + 炒大米煮水 15 分钟。",
                    reasoning: "急症期先吃温粥护胃气，再温中燥湿避免空腹伤脾。",
                    timeSlot: "上午 08:00-09:00",
                    diningEnvironment: env,
                    dietaryPreferences: dietaryPreferences
                )
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dietMorning.id,
                        category: .diet,
                        timeSlot: "上午 08:00-09:00",
                        previousTitle: dietMorning.title,
                        updatedTitle: adapted.title,
                        updatedDetail: adapted.detail,
                        updatedReasoning: adapted.reasoning,
                        sortOrder: 0
                    )
                )
            }

            if let dietLunch = existingCards.first(where: { $0.category == .diet && $0.sortOrder == 1 }) {
                let adapted = DietaryAdaptationHelper.adaptCard(
                    title: "山药白扁豆小米暖胃粥",
                    detail: "怀山药 80g、炒白扁豆 15g、小米煮至绵软，配清蒸鸡胸肉 100g，忌生冷油腻。",
                    reasoning: "急症期暂停寒凉与粗硬纤维，减轻脾胃负担。",
                    timeSlot: dietLunch.timeSlot,
                    diningEnvironment: env,
                    dietaryPreferences: dietaryPreferences
                )
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dietLunch.id,
                        category: .diet,
                        timeSlot: dietLunch.timeSlot,
                        previousTitle: dietLunch.title,
                        updatedTitle: adapted.title,
                        updatedDetail: adapted.detail,
                        updatedReasoning: adapted.reasoning,
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

        // 偏离食谱 / 聚餐吃重口 / 晚上还饿想加餐：零负罪感共情兜底
        if effectiveInput.contains("聚餐") || effectiveInput.contains("吃多了") || effectiveInput.contains("没按计划") || effectiveInput.contains("火锅") || effectiveInput.contains("烧烤") {
            if let dinnerCard = existingCards.first(where: { $0.category == .diet && ($0.sortOrder == 3 || $0.timeSlot.contains("18:") || $0.timeSlot.contains("19:")) })
                ?? existingCards.last(where: { $0.category == .diet }) {
                let adapted = DietaryAdaptationHelper.adaptCard(
                    title: "冬瓜萝卜陈皮清顺汤（不吃主食）",
                    detail: "聚餐或没按计划吃完全没关系！下一餐吃一碗热冬瓜白萝卜汤配少许绿叶菜，餐后散步 15 分钟消食即可。",
                    reasoning: "偶尔解馋不焦虑，清顺汤水把多出的油湿拉回来。",
                    timeSlot: dinnerCard.timeSlot,
                    diningEnvironment: env,
                    dietaryPreferences: dietaryPreferences
                )
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dinnerCard.id,
                        category: .diet,
                        timeSlot: dinnerCard.timeSlot,
                        previousTitle: dinnerCard.title,
                        updatedTitle: adapted.title,
                        updatedDetail: adapted.detail,
                        updatedReasoning: adapted.reasoning,
                        corePrinciple: "下一餐减负清顺，不自责不节食",
                        flexibleSwapHint: "外食点不到萝卜汤？点一份白灼生菜+热柠檬陈皮水也同样管用。",
                        sortOrder: dinnerCard.sortOrder
                    )
                )
            }

            return AdjustmentProposal(
                userInput: effectiveInput,
                triageSummary: nil,
                detectedSymptoms: symptoms,
                proposedPhase: snapshot.recoveryPhase,
                phaseSpec: defaultPhaseSpec,
                summary: "偶尔聚餐或没按食谱吃完全没关系，身体看的是长期节奏！下一餐用清淡热汤顺一下就拉回来了。",
                source: .offlineDemo,
                diffs: diffs
            )
        }

        if effectiveInput.contains("还饿") || effectiveInput.contains("饿了") || effectiveInput.contains("加餐") {
            if let dinnerCard = existingCards.first(where: { $0.category == .diet && ($0.sortOrder == 3 || $0.timeSlot.contains("18:") || $0.timeSlot.contains("19:")) })
                ?? existingCards.last(where: { $0.category == .diet }) {
                let adapted = DietaryAdaptationHelper.adaptCard(
                    title: "\(dinnerCard.title) + 绿灯安心加餐",
                    detail: "千万别硬扛挨饿，硬饿反伤脾胃！睡前 2 小时外若还饿，可加半杯温无糖豆浆、1 个水煮蛋或 2 块蒸山药。",
                    reasoning: "补温热低脂绿灯蛋白，既解饿又不增加痰湿。",
                    timeSlot: dinnerCard.timeSlot,
                    diningEnvironment: env,
                    dietaryPreferences: dietaryPreferences
                )
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dinnerCard.id,
                        category: .diet,
                        timeSlot: dinnerCard.timeSlot,
                        previousTitle: dinnerCard.title,
                        updatedTitle: adapted.title,
                        updatedDetail: adapted.detail,
                        updatedReasoning: adapted.reasoning,
                        corePrinciple: "饥饿优先补绿灯温热蛋白，拒绝硬饿",
                        flexibleSwapHint: "常见绿灯加餐：热无糖豆浆、水煮蛋、蒸山药、温热小番茄。",
                        sortOrder: dinnerCard.sortOrder
                    )
                )
            }

            return AdjustmentProposal(
                userInput: effectiveInput,
                triageSummary: nil,
                detectedSymptoms: symptoms,
                proposedPhase: snapshot.recoveryPhase,
                phaseSpec: defaultPhaseSpec,
                summary: "食谱分量只是参考，真饿了千万别硬扛！已为你加上绿灯安全加餐建议，放心吃一点。",
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
                let adapted = DietaryAdaptationHelper.adaptCard(
                    title: "温热小米粥配鸡蛋 + 餐后炒薏米茯苓祛湿茶",
                    detail: "先吃温热小米粥配水煮蛋护脾胃；餐后泡饮炒薏米 15g、茯苓 6g、陈皮 3g，应对 \(humidity)% 高湿。",
                    reasoning: "湿度 \(humidity)% 偏重，先垫谷气再加强健脾化湿。",
                    timeSlot: "上午 08:00-09:00",
                    diningEnvironment: env,
                    dietaryPreferences: dietaryPreferences
                )
                diffs.append(
                    CardAdjustmentDiff(
                        dayOffset: 0,
                        targetCardID: dietMorning.id,
                        category: .diet,
                        timeSlot: "上午 08:00-09:00",
                        previousTitle: dietMorning.title,
                        updatedTitle: adapted.title,
                        updatedDetail: adapted.detail,
                        updatedReasoning: adapted.reasoning,
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
            let adapted = DietaryAdaptationHelper.adaptCard(
                title: diningEnv == "外卖" ? "清汤鸡肉米粉（去冰少油）" : "茯苓山药蒸鸡腿配时蔬",
                detail: "今日\(diningEnv)场景优先选温热易消化蛋白，七分饱停筷，餐后站立 15 分钟。"
                    + (ocrSnippet.map { "（参考识别信息：\($0)）" } ?? ""),
                reasoning: "结合「\(effectiveInput.prefix(8))」与\(Int(snapshot.weatherTempC.rounded()))°C体感微调。",
                timeSlot: dietLunch.timeSlot,
                diningEnvironment: diningEnv,
                dietaryPreferences: dietaryPreferences
            )
            diffs.append(
                CardAdjustmentDiff(
                    dayOffset: 0,
                    targetCardID: dietLunch.id,
                    category: .diet,
                    timeSlot: dietLunch.timeSlot,
                    previousTitle: dietLunch.title,
                    updatedTitle: adapted.title,
                    updatedDetail: adapted.detail,
                    updatedReasoning: adapted.reasoning,
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
            dietaryPreferences: profile?.dietaryPreferences ?? [],
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
        diningEnvironment: String?,
        dietaryPreferences: [String] = []
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
                    "小米南瓜粥配蒸蛋 + 餐后红枣陈皮饮",
                    "温热小米南瓜粥配水煮蛋先垫胃；餐后温饮去核红枣 2 颗 + 陈皮 2g 焖泡水。",
                    "急性恢复期先食温粥护胃，兼顾轻微气虚提神。"
                ),
                (
                    "猴头菇山药温胃羹",
                    "猴头菇干品泡发炖汤，加入铁棍山药块，少盐清淡，配半碗软米饭。",
                    "粘膜修复期温和养胃，避免加重痰湿停滞。"
                ),
                (
                    "炒白术茯苓温茶 + 蒸山药",
                    "先吃两块蒸山药垫胃，再温饮茯苓 6g + 炒白术 5g 代茶，下午 4 点前饮毕。",
                    "健脾益气燥湿，缓解午后困倦与大便粘滞。"
                )
            ] : [
                (
                    "燕麦小米粥配鸡蛋 + 餐后陈皮荷叶饮",
                    "先吃温热燕麦小米粥配水煮蛋；餐后老陈皮 3g + 干荷叶 2g 沸水冲泡温服，忌冰镇。",
                    "先养胃气再化浊醒脾，助力痰湿质减重代谢。"
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

            let chosen = nextCandidate(from: pool, excludingTitle: excludingTitle)
            return DietaryAdaptationHelper.adaptCard(
                title: chosen.0,
                detail: chosen.1,
                reasoning: chosen.2,
                timeSlot: chosen.0.contains("粥") ? "上午 08:00-09:00" : "中午 12:00-13:30",
                diningEnvironment: diningEnvironment ?? "居家做饭",
                dietaryPreferences: dietaryPreferences
            )

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

    static func offlinePhaseTransition(
        outcome: FollowUpOutcome,
        userNote: String,
        profile: AIProfileContext?,
        snapshot: AISnapshotContext
    ) -> AIPhaseTransitionResponse {
        let currentStage = snapshot.activePhase?.stageKind ?? (snapshot.isAcuteRecovery ? .acuteRelief : .maintenance)
        let diningEnv = profile?.diningEnvironment ?? "居家做饭"
        let dietPrefs = profile?.dietaryPreferences ?? []
        let tempC = Int(snapshot.weatherTempC.rounded())
        let isWarmHumid = snapshot.weatherTempC >= 24.0 && snapshot.weatherHumidity >= 75.0
        let swimSuitable = isOutdoorSwimmingSuitable(
            tempC: snapshot.weatherTempC,
            condition: snapshot.weatherCondition,
            windSpeedKmh: snapshot.weatherWindSpeedKmh,
            isAcuteRecovery: false
        )
        let currentTags = profile?.constitutionTags ?? ["痰湿质78分", "轻微气虚", "肠胃敏感"]

        func adapt(_ cards: [AIPlannedCardPayload]) -> [AIPlannedCardPayload] {
            cards.map { DietaryAdaptationHelper.adaptPayload($0, diningEnvironment: diningEnv, dietaryPreferences: dietPrefs) }
        }

        switch outcome {
        case .improved:
            let nextStage = currentStage.nextTypicalStage
            let evolved = evolvedConstitutionTags(from: currentTags, scoreDelta: -3)
            switch nextStage {
            case .dampnessClearing:
                let spec = AIRegimenPhasePayload(
                    stageKind: RegimenStageKind.dampnessClearing.rawValue,
                    phaseName: "祛邪疏通期",
                    therapeuticPrinciple: "健脾燥湿、温和行气，逐步恢复清淡蛋白",
                    plannedDays: 4,
                    exitCriteria: "舌苔由厚转薄、大便成形且午后不困倦",
                    nextStageHint: "转入「缓调扶正期」，恢复抗阻训练与减重节奏"
                )
                return AIPhaseTransitionResponse(
                    transitionDecision: "advanceToNextStage",
                    clinicalAssessment: "急性胃肠反应已平复，现转入「祛邪疏通期」巩固化湿。",
                    summary: "已从急症护胃过渡到健脾祛湿，饮食渐增清蒸优质蛋白并重启室内微抗阻。",
                    newPhaseSpec: spec,
                    evolutionSpec: AIConstitutionEvolutionPayload(
                        shouldUpdateProfile: true,
                        updatedConstitutionTags: evolved.tags,
                        deltaSummary: evolved.deltaSummary,
                        toleranceNote: "对温胃茶饮与八段锦导引耐受良好"
                    ),
                    remainingSymptoms: [],
                    cards: adapt([
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "上午 08:00-09:00",
                            title: "温热小米粥配蒸蛋 + 餐后炒白术茯苓茶",
                            actionDetail: "先吃温热小米粥配水煮蛋垫胃；餐后泡饮茯苓 6g、炒白术 5g、陈皮 3g 温茶。",
                            reasoning: "先垫谷气护胃，再健脾渗湿防止残湿留滞。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "中午 12:00-13:30",
                            title: "清蒸鲈鱼 + 炒冬瓜 + 半碗杂粮饭",
                            actionDetail: "\(diningEnv)选清蒸鱼虾 150g 搭配少油冬瓜与软杂粮饭，七分饱停筷。",
                            reasoning: "逐步恢复优质蛋白，既养脾又不生痰湿。"
                        ),
                        AIPlannedCardPayload(
                            category: "fitness",
                            timeSlot: "下午 17:00-17:30",
                            title: "居家弹力带划船 + 臀桥(20min)",
                            actionDetail: "弹力带划船 3×15、自重臀桥 3×15、八段锦收功两遍，微汗即止。",
                            reasoning: "疏通期以室内低冲击抗阻唤醒代谢，暂不猛练。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "傍晚 18:00-19:00",
                            title: "山药陈皮豆腐汤 + 清蒸鸡丝",
                            actionDetail: "\(diningEnv)晚餐温软易消化，少油盐、少主食，19:00 前进食完毕。",
                            reasoning: "疏通期晚餐轻食养脾，避免残湿夜间积滞。"
                        ),
                        AIPlannedCardPayload(
                            category: "lifestyle",
                            timeSlot: "晚上 21:30",
                            title: "顺时针揉腹 + 睡前 2 小时控水",
                            actionDetail: "仰卧轻柔摩腹 36 圈，21:30 后仅抿口润喉，23:00 前熄灯。",
                            reasoning: "巩固脾胃夜运，减少晨起肢体沉重感。"
                        )
                    ])
                )

            case .tonifying:
                let spec = AIRegimenPhasePayload(
                    stageKind: RegimenStageKind.tonifying.rawValue,
                    phaseName: "缓调扶正期",
                    therapeuticPrinciple: "健脾益气、培土制水，稳住肌肉推进减重",
                    plannedDays: 7,
                    exitCriteria: "精力充沛、体重稳步回落且大便连续规律",
                    nextStageHint: "转入「日常顺时固本期」，随节气长周期维护"
                )
                return AIPhaseTransitionResponse(
                    transitionDecision: "advanceToNextStage",
                    clinicalAssessment: "湿浊大退、脾运恢复，进入「缓调扶正期」治本固脾。",
                    summary: "全面恢复蛋白与常规运动节奏，重点培补脾气以防痰湿再生。",
                    newPhaseSpec: spec,
                    evolutionSpec: AIConstitutionEvolutionPayload(
                        shouldUpdateProfile: true,
                        updatedConstitutionTags: evolved.tags,
                        deltaSummary: evolved.deltaSummary,
                        toleranceNote: "清蒸蛋白与室内微抗阻适应良好"
                    ),
                    remainingSymptoms: [],
                    cards: adapt([
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "上午 08:00-09:00",
                            title: "山药燕麦粥配水煮蛋 + 餐后黄芪红枣陈皮饮",
                            actionDetail: "先吃温热山药燕麦粥配水煮蛋 1 个；餐后温饮黄芪 5g、红枣 2 颗、陈皮 2g 焖泡水。",
                            reasoning: "先食温粥补谷气，再益气健脾防湿反复。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "中午 12:00-13:30",
                            title: "芡实莲子瘦肉汤 + 时蔬杂粮",
                            actionDetail: "瘦肉 150g 炖芡实莲子清汤，搭配绿叶菜与半碗糙米饭。",
                            reasoning: "健脾固肾、高蛋白低脂，稳步恢复减重缺口。"
                        ),
                        AIPlannedCardPayload(
                            category: "fitness",
                            timeSlot: "下午 16:30-17:20",
                            title: swimSuitable ? "阳光下室外游泳(35min)" : "居家哑铃复合抗阻(25min)",
                            actionDetail: swimSuitable
                                ? "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)，蛙泳 35 分钟并注意上岸保暖。"
                                : "高脚杯深蹲 3×12、哑铃推举 3×12、划船 3×15，护膝高效燃脂。",
                            reasoning: swimSuitable
                                ? "\(snapshot.city) \(tempC)°C 晴暖适宜下水，重启有氧代谢。"
                                : "结合气象条件在室内保肌减脂，不伤关节。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "傍晚 18:00-19:00",
                            title: "清蒸鲜虾 + 蒜蓉芥兰 + 蒸南瓜",
                            actionDetail: "\(diningEnv)晚餐优质蛋白 120g 配高纤绿叶菜与一小块贝贝南瓜，七分饱。",
                            reasoning: "扶正期晚餐兼顾保肌与温脾，夜间轻负荷。"
                        ),
                        AIPlannedCardPayload(
                            category: "lifestyle",
                            timeSlot: "晚上 21:30",
                            title: "温水泡脚 + 23:00 前安眠",
                            actionDetail: "40°C 温水泡脚 12 分钟，放下屏幕保证 7.5 小时高质量睡眠。",
                            reasoning: "睡眠是最好的扶正之法，稳固脾肾阳气。"
                        )
                    ])
                )

            default:
                let spec = AIRegimenPhasePayload(
                    stageKind: RegimenStageKind.maintenance.rawValue,
                    phaseName: "日常顺时固本期",
                    therapeuticPrinciple: "健脾化湿、温阳理气，循序渐进减重",
                    plannedDays: 14,
                    exitCriteria: "排便成形、晨起轻快不困重且饮食作息平稳",
                    nextStageHint: "持续顺时固本，随二十四节气微调"
                )
                return AIPhaseTransitionResponse(
                    transitionDecision: "advanceToNextStage",
                    clinicalAssessment: "本周期调理圆满达标，顺利回归「日常顺时固本期」。",
                    summary: "已解除阶段限制，恢复贴合\(snapshot.city)实时天气与减重目标的日常顺时计划。",
                    newPhaseSpec: spec,
                    evolutionSpec: AIConstitutionEvolutionPayload(
                        shouldUpdateProfile: true,
                        updatedConstitutionTags: evolved.tags,
                        deltaSummary: evolved.deltaSummary,
                        toleranceNote: "完成整周期调理，脾胃耐受力较前提升"
                    ),
                    remainingSymptoms: [],
                    cards: adapt([
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "上午 08:00-09:00",
                            title: isWarmHumid ? "温热小米粥配水煮蛋 + 餐后陈皮茯苓饮" : "温热小米山药粥配水煮蛋 + 餐后生姜陈皮饮",
                            actionDetail: isWarmHumid
                                ? "先吃温热小米粥与水煮蛋；餐后温饮陈皮 3g + 茯苓 5g 泡饮（\(snapshot.city)\(tempC)°C偏湿暖，改平调）。"
                                : "先吃温热小米山药粥与水煮蛋；餐后老姜 2 片 + 5 年陈皮 3g 焖泡温饮。",
                            reasoning: "先吃温粥养胃，再顺应\(snapshot.city)\(tempC)°C气候调脾。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "中午 12:00-13:30",
                            title: "冬瓜薏米瘦肉温汤 + 杂粮饭",
                            actionDetail: "\(diningEnv)清淡烹调高蛋白配半碗杂粮饭，细嚼慢咽。",
                            reasoning: "痰湿质减重期高蛋白低脂，防湿浊积聚。"
                        ),
                        AIPlannedCardPayload(
                            category: "fitness",
                            timeSlot: "下午 16:30-17:30",
                            title: swimSuitable ? "阳光下室外游泳(限时35min)" : "居家壶铃/弹力带抗阻(25min)",
                            actionDetail: swimSuitable
                                ? "中等配速蛙泳/自由泳 35 分钟，避开冷水深潜。"
                                : "高脚杯深蹲 3×12、弹力带划船 3×15，避开传统跑步。",
                            reasoning: swimSuitable
                                ? "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)适宜下水，护膝燃脂。"
                                : "\(snapshot.city) \(tempC)°C \(snapshot.weatherCondition)，室内抗阻更稳妥。"
                        ),
                        AIPlannedCardPayload(
                            category: "diet",
                            timeSlot: "傍晚 18:00-19:00",
                            title: "山药虾仁蒸蛋 + 清炒时蔬（轻食晚餐）",
                            actionDetail: "\(diningEnv)晚餐少油少盐，以蛋虾豆腐配绿叶菜为主，控制精制主食。",
                            reasoning: "稳态减重期晚餐清淡高蛋白，防夜间生湿囤脂。"
                        ),
                        AIPlannedCardPayload(
                            category: "lifestyle",
                            timeSlot: "晚上 21:30",
                            title: "温水泡脚 + 睡前 2 小时控水",
                            actionDetail: "40°C 泡脚 15 分钟至微润即止，夜间不大量饮水。",
                            reasoning: "防夜间水湿停滞，保持次日晨起轻盈。"
                        )
                    ])
                )
            }

        case .steadyContinue:
            let spec = AIRegimenPhasePayload(
                stageKind: currentStage.rawValue,
                phaseName: snapshot.activePhase?.phaseName ?? currentStage.displayName,
                therapeuticPrinciple: snapshot.therapeuticPrinciple,
                plannedDays: (snapshot.activePhase?.plannedDays ?? 3) + 2,
                exitCriteria: snapshot.activePhase?.exitCriteria ?? "症状完全消退且精神恢复",
                nextStageHint: snapshot.activePhase?.nextStageHint ?? "待症状稳固后再向下一阶段推进"
            )
            return AIPhaseTransitionResponse(
                transitionDecision: "extendCurrentStage",
                clinicalAssessment: "「效不更方」：当前方向有效但尚需 2 天巩固，暂不急于增量加压。",
                summary: "为你顺延当前阶段 2 天，保持温和食养与低负荷导引。",
                newPhaseSpec: spec,
                evolutionSpec: AIConstitutionEvolutionPayload(
                    shouldUpdateProfile: false,
                    updatedConstitutionTags: currentTags,
                    deltaSummary: "症状改善中，维持当前体质基线并继续观察",
                    toleranceNote: "对温和食养方案有正向改善"
                ),
                remainingSymptoms: snapshot.userReportedSymptoms,
                cards: adapt([
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "上午 08:00-09:00",
                        title: "小米南瓜粥配鸡蛋 + 餐后红枣炒薏米饮",
                        actionDetail: "先吃温热小米南瓜粥配水煮蛋垫胃；餐后温饮炒薏米 15g、陈皮 3g、去核红枣 2 颗焖泡水。",
                        reasoning: "巩固期先垫温粥再健脾燥湿，避免空腹伤脾。"
                    ),
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "中午 12:00-13:30",
                        title: "猴头菇山药鸡肉温羹",
                        actionDetail: "山药与嫩鸡肉炖至软烂，少油少盐，配半碗温热米饭。",
                        reasoning: "继续护养脾胃黏膜，避免过早恢复生冷粗硬。"
                    ),
                    AIPlannedCardPayload(
                        category: "fitness",
                        timeSlot: "下午 17:00-17:25",
                        title: "八段锦 + 靠墙静蹲(15min)",
                        actionDetail: "八段锦两遍舒展脾胃，配合靠墙静蹲 3 组 × 45 秒。",
                        reasoning: "巩固阶段维持温和气血循环，防反复疲劳。"
                    ),
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "傍晚 18:00-18:45",
                        title: "南瓜小米瘦肉暖胃粥",
                        actionDetail: "嫩瘦肉丝 60g 配贝贝南瓜与小米煮至软烂，少盐温食六七分饱。",
                        reasoning: "巩固期晚餐继续温和护胃，不给脾胃添堵。"
                    ),
                    AIPlannedCardPayload(
                        category: "lifestyle",
                        timeSlot: "晚上 21:30",
                        title: "艾草温水泡脚 + 23:00 熄灯",
                        actionDetail: "温水泡脚 12 分钟后揉腹 36 圈，保证充足睡眠。",
                        reasoning: "睡眠修复加速残余症状退散。"
                    )
                ])
            )

        case .persistingOrWorse:
            let noteSnippet = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
            var updatedSymptoms = snapshot.userReportedSymptoms
            if !noteSnippet.isEmpty {
                updatedSymptoms.append(String(noteSnippet.prefix(14)))
            } else if !updatedSymptoms.contains("症状待进一步观察") {
                updatedSymptoms.append("症状待进一步观察")
            }

            let spec = AIRegimenPhasePayload(
                stageKind: RegimenStageKind.acuteRelief.rawValue,
                phaseName: "急性护胃重整期",
                therapeuticPrinciple: "变证易法：彻底清简饮食、停掉负重训练以保脾胃",
                plannedDays: 3,
                exitCriteria: "不适感消退、胃腹安和且排便恢复正常",
                nextStageHint: "若持续超过 3 天未缓解或伴发热剧痛，建议线下就医"
            )
            return AIPhaseTransitionResponse(
                transitionDecision: "adjustPlan",
                clinicalAssessment: "症状未达预期或有新变化，已切换为更清简的护胃重整方案（如伴高热剧痛请及时就医）。",
                summary: "进一步简化今日饮食与活动负荷，以流质温粥和静养观察为主。",
                newPhaseSpec: spec,
                evolutionSpec: AIConstitutionEvolutionPayload(
                    shouldUpdateProfile: false,
                    updatedConstitutionTags: currentTags,
                    deltaSummary: "脾胃尚处于敏感波动期，需降负荷护胃",
                    toleranceNote: noteSnippet.isEmpty ? "当前阶段对肉类或负重较敏感，已简化食谱" : "反馈重点：\(String(noteSnippet.prefix(16)))"
                ),
                remainingSymptoms: updatedSymptoms,
                cards: adapt([
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "上午 08:00-09:00",
                        title: "焦米陈皮护胃温粥",
                        actionDetail: "温热软白米粥/焦米汤少量多次温服，暂不加粗粮与生冷配菜。",
                        reasoning: "反复不适时以温粥焦米汤护胃膜，减轻负担。"
                    ),
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "中午 12:00-13:30",
                        title: "软烂山药小米粥（清淡无油）",
                        actionDetail: "怀山药蒸熟压泥同小米熬粥，暂撤肉类油脂，七分饱即可。",
                        reasoning: "暂时减负让脾胃休整，防止食积或寒湿反复。"
                    ),
                    AIPlannedCardPayload(
                        category: "fitness",
                        timeSlot: "下午 17:00",
                        title: "腹式呼吸静养 + 轻缓散步(10min)",
                        actionDetail: "暂停抗阻与游泳，室内慢走 10 分钟配合深长腹式呼吸。",
                        reasoning: "不适期保留气血用于修复，避免运动耗气。"
                    ),
                    AIPlannedCardPayload(
                        category: "diet",
                        timeSlot: "傍晚 18:00-18:30",
                        title: "温热白米汤 + 蒸山药泥（清简晚餐）",
                        actionDetail: "少量温热软米粥配熟山药泥，不加油腻荤腥与生冷水果。",
                        reasoning: "重整期晚餐极简留余地，让脾胃安稳过夜。"
                    ),
                    AIPlannedCardPayload(
                        category: "lifestyle",
                        timeSlot: "晚上 21:00",
                        title: "暖腹热敷 + 早睡观察",
                        actionDetail: "热敷袋温敷中脘与肚脐 15 分钟，22:30 前入睡并留意次日体温与排便。",
                        reasoning: "温阳安中并密切观察转归，确保安全底线。"
                    )
                ])
            )
        }
    }

    private static func evolvedConstitutionTags(
        from tags: [String],
        scoreDelta: Int
    ) -> (tags: [String], deltaSummary: String) {
        var updated = tags
        var summary = "脾胃运化改善，整体体质向稳态推进"

        if let first = updated.first,
           let currentScore = ConstitutionEvolutionRecord.extractScore(from: [first]) {
            let newScore = max(45, currentScore + scoreDelta)
            let updatedFirst = first.replacingOccurrences(of: "\(currentScore)分", with: "\(newScore)分")
            updated[0] = updatedFirst
            summary = "偏颇指数温和改善（\(currentScore)分 → \(newScore)分）"
        }

        if let sensitiveIndex = updated.firstIndex(of: "肠胃敏感") {
            updated[sensitiveIndex] = "脾胃渐稳"
        }

        return (updated, summary)
    }

    // MARK: - Phase 9: Adaptive 4+2 Onboarding Inquiry

    static func offlineOnboardingFollowUp(
        baseAnswers: [OnboardingInquiryAnswer],
        voiceTranscript: String = "",
        reportText: String,
        hasTongueImage: Bool,
        hasFaceImage: Bool = false
    ) -> AIOnboardingFollowUpResponse {
        if !reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasTongueImage && hasFaceImage {
            return AIOnboardingFollowUpResponse(
                needFollowUp: false,
                reasoningHint: "已结合体检/体质报告及自然光舌象、面色照片，四诊信息充分，可直接进入综合辨证。",
                questions: []
            )
        }

        let joined = "\(baseAnswers.map(\.answer).joined(separator: " ")) \(voiceTranscript)"
        var questions: [AITriageQuestionPayload] = []

        if joined.contains("上热下寒")
            || joined.contains("下面却怕冷")
            || (joined.contains("怕冷") && (joined.contains("口干") || joined.contains("口苦") || joined.contains("烦躁"))) {
            questions.append(
                AITriageQuestionPayload(
                    id: "upper_heat_lower_cold",
                    question: "是否经常熬夜或吃温热食物后容易口腔溃疡/长痘，但下肢和腹部依然怕凉？",
                    options: ["是，典型上火下凉", "不是，整体主要是怕冷", "主要偏热，下肢不凉"]
                )
            )
        } else if joined.contains("黏腻") || joined.contains("粘腻") || joined.contains("头重") || joined.contains("胀气") || joined.contains("口淡") {
            questions.append(
                AITriageQuestionPayload(
                    id: "dampness_nature",
                    question: "平时喝生姜红糖水或吃微辣温补食物后，身体感受更接近哪种？",
                    options: ["胃里暖和舒服、更有精神", "容易口干喉咙痛或长痘", "感觉偏腻、消化变慢"]
                )
            )
        }

        questions.append(
            AITriageQuestionPayload(
                id: "sleep_stamina_depth",
                question: "近两周早上醒来和夜间睡眠的规律更偏向？",
                options: ["常熬夜(>23:30)，醒后仍疲惫", "入睡尚可但多梦易醒", "作息规律，睡醒后较轻快"]
            )
        )

        let limited = Array(questions.prefix(2))
        return AIOnboardingFollowUpResponse(
            needFollowUp: !limited.isEmpty,
            reasoningHint: "为排除「寒热交错」与「温补耐受差异」，请再确认 \(limited.count) 个关键辨证问题：",
            questions: limited
        )
    }

    static func offlineOnboardingAssessment(
        heightCM: Double,
        weightKG: Double,
        targetWeightKG: Double,
        diningEnvironment: String,
        dietaryPreferences: [String],
        fitnessPreferences: [String],
        allAnswers: [OnboardingInquiryAnswer],
        voiceTranscript: String = "",
        acousticSummary: String? = nil,
        reportText: String,
        hasTongueImage: Bool,
        hasFaceImage: Bool = false,
        city: String,
        weatherTempC: Double,
        weatherCondition: String,
        weatherHumidity: Double = 68.0
    ) -> AIOnboardingConstitutionResponse {
        let trimmedReport = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVoice = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let joinedAnswers = "\(allAnswers.map(\.answer).joined(separator: " ")) \(trimmedVoice) \(acousticSummary ?? "")"

        let parsed = trimmedReport.isEmpty ? nil : ConstitutionReportParser.parse(text: trimmedReport)
        let bmi = heightCM > 0 ? weightKG / pow(heightCM / 100.0, 2) : 24.0
        let tempC = Int(weatherTempC.rounded())
        let isWarmHumid = weatherTempC >= 24.0 && weatherHumidity >= 75.0
        let swimSuitable = isOutdoorSwimmingSuitable(
            tempC: weatherTempC,
            condition: weatherCondition,
            windSpeedKmh: 9.0,
            isAcuteRecovery: false
        )
        let likesSwim = fitnessPreferences.contains { $0.contains("游泳") }

        // 决定主体质与兼夹特征
        var primary = "痰湿质74分"
        var secondary: [String] = []
        var phaseName = "初筛试探校准期"
        var stageKind: RegimenStageKind = .dampnessClearing
        var principle = isWarmHumid
            ? "健脾平调化湿、顺应湿暖气候，忌生冷与过度温燥"
            : "健脾燥湿、温和试探，忌生冷观察3日反应"
        var morningDrink = isWarmHumid
            ? ("温热小米粥配水煮蛋 + 餐后陈皮茯苓平调饮", "先吃温粥垫胃；餐后泡饮陈皮 3g + 茯苓 5g（\(city)\(tempC)°C偏湿暖，暂不加纯姜）。", "先养胃气再平调化湿，贴合当地湿暖体感。")
            : ("温热小米山药粥配水煮蛋 + 餐后生姜陈皮饮", "先吃 1 碗温粥与鸡蛋护胃；餐后老姜 1 片 + 陈皮 3g 温泡 10 分钟。", "先食谷物保胃气，再温中和胃测耐受度。")
        var lunchMeal = ("冬瓜薏米瘦肉温汤 + 杂粮饭", "\(diningEnvironment)清淡少油，瘦肉/鱼虾 130g 配半碗温热杂粮饭。", "高蛋白低脂健脾，兼顾减重与化湿。")

        var dinnerMeal = ("山药虾仁蒸蛋 + 蒜蓉油麦菜（轻食晚餐）", "\(diningEnvironment)晚餐高蛋白低碳水，七分饱并在 19:30 前吃完。", "晚餐温软少主食，减轻夜间脾胃运化负担。")

        if let parsed, !parsed.constitutionTags.isEmpty {
            primary = parsed.constitutionTags[0]
            secondary = Array(parsed.constitutionTags.dropFirst())
        } else if joinedAnswers.contains("上火下凉") || joinedAnswers.contains("上热下寒") || joinedAnswers.contains("下面却怕冷") {
            primary = "寒热错杂质72分"
            secondary = ["脾胃气弱", "上热下寒"]
            phaseName = "引火归元试探期"
            stageKind = .tonifying
            principle = "清上温下、健运中焦，忌辛辣过燥与冰冷"
            morningDrink = ("小米百合粥配鸡蛋 + 餐后茯苓麦冬陈皮饮", "先吃温热小米百合粥配鸡蛋；餐后泡饮茯苓 6g + 麦冬 3g + 陈皮 2g。", "先垫谷气护中焦，平调上热下寒不燥。")
            lunchMeal = ("山药百合清炖鸡胸 + 绿叶时蔬", "\(diningEnvironment)温和清补，少辣少油，搭配半碗糙米饭。", "清润不过寒，护胃同时防口干长痘。")
            dinnerMeal = ("豆腐菌菇鸡蛋温汤 + 焯生菜（轻食晚餐）", "\(diningEnvironment)晚餐清润少油盐，少主食，不吃宵夜辛辣。", "晚餐清淡守中焦，防夜间虚火上炎。")
        } else if joinedAnswers.contains("口干口苦") || joinedAnswers.contains("偏怕热") || joinedAnswers.contains("偏热") || joinedAnswers.contains("易口干喉咙痛") || joinedAnswers.contains("干结") {
            primary = "湿热质73分"
            secondary = ["脾胃湿滞", "轻度内热"]
            phaseName = "清化湿热校准期"
            stageKind = .dampnessClearing
            principle = "清利湿热、轻食通腑，忌辛辣姜桂温燥"
            morningDrink = ("温热燕麦杂粮粥配鸡蛋 + 餐后冬瓜荷叶淡饮", "先吃温热杂粮粥配鸡蛋；餐后泡饮炒薏米 15g + 干荷叶 2g（不加姜片）。", "先固胃气再清化湿热，观察口苦改善。")
            lunchMeal = ("清蒸鲈鱼 + 清炒时蔬 + 杂粮饭", "\(diningEnvironment)少油少辣，多吃冬瓜、芹菜等利湿清蔬。", "清淡高蛋白利湿，避免助热生痰。")
            dinnerMeal = ("冬瓜海带豆腐汤 + 凉拌/清炒苦菊（轻食晚餐）", "\(diningEnvironment)晚餐清热利湿、不吃烧烤与油腻荤菜。", "夜间清疏湿热，减少晨起口苦粘腻。")
        } else if joinedAnswers.contains("怕冷") || joinedAnswers.contains("稀水") {
            primary = "阳虚兼痰湿74分"
            secondary = ["脾胃偏寒", "轻微气虚"]
            phaseName = "温阳健脾试探期"
            stageKind = .tonifying
            principle = "温中散寒、健脾助阳，忌生冷果蔬冰饮"
            morningDrink = ("小米南瓜粥配水煮蛋 + 餐后生姜红枣温胃饮", "先吃热小米南瓜粥配鸡蛋；餐后温饮老姜 2 片 + 陈皮 3g + 去核红枣 2 颗。", "先吃温粥培土固胃，再温脾散寒。")
            lunchMeal = ("山药排骨/鸡腿温汤 + 软米饭", "\(diningEnvironment)保证食物温热，配山药、南瓜等健脾食材。", "培补脾阳，改善畏寒与吃凉腹泻。")
            dinnerMeal = ("姜丝白萝卜瘦肉暖汤 + 蒸南瓜（轻食晚餐）", "\(diningEnvironment)晚餐趁热小口吃，忌生冷沙拉与冷饮。", "温脾暖腹安睡，防夜间寒气侵胃。")
        } else {
            if bmi >= 25.0 || joinedAnswers.contains("黏腻") || joinedAnswers.contains("粘腻") || joinedAnswers.contains("不成形") || joinedAnswers.contains("头重") {
                primary = "痰湿质75分"
            } else {
                primary = "气虚偏湿质68分"
            }
            if joinedAnswers.contains("气短") || joinedAnswers.contains("疲惫") || joinedAnswers.contains("易倦") {
                secondary.append("轻微气虚")
            }
            if joinedAnswers.contains("吃凉") || joinedAnswers.contains("胀气") {
                secondary.append("肠胃敏感")
            }
            if joinedAnswers.contains("烦躁") || joinedAnswers.contains("胸闷") {
                secondary.append("轻度气郁")
            }
            if secondary.isEmpty {
                secondary = ["脾运偏弱"]
            }
        }

        if (joinedAnswers.contains("烦躁") || joinedAnswers.contains("胸闷")) && !secondary.contains("轻度气郁") {
            secondary.append("轻度气郁")
        }
        if (joinedAnswers.contains("吃凉") || joinedAnswers.contains("胀气")) && !secondary.contains("肠胃敏感") {
            secondary.append("肠胃敏感")
        }
        if (joinedAnswers.contains("气短") || joinedAnswers.contains("易倦") || joinedAnswers.contains("偏轻细")) && !secondary.contains("轻微气虚") {
            secondary.append("轻微气虚")
        }

        // 计算置信度：基础 66%，+ 报告 18%，+ 舌象 14%，+ 面色 8%，+ 语音口述 6%，+ 深度追问 6%
        var confidence = 66
        if parsed != nil && !(parsed?.constitutionTags.isEmpty ?? true) {
            confidence += 18
        }
        if hasTongueImage {
            confidence += 14
        }
        if hasFaceImage {
            confidence += 8
        }
        if !trimmedVoice.isEmpty {
            confidence += 6
        }
        if allAnswers.count >= 5 {
            confidence += 6
        }
        confidence = min(94, confidence)

        let needsTrial = confidence < 82
        if !needsTrial {
            phaseName = "日常顺时固本期"
            stageKind = .maintenance
        }

        let fitnessCard: AIPlannedCardPayload
        if likesSwim && swimSuitable {
            fitnessCard = AIPlannedCardPayload(
                category: "fitness",
                timeSlot: "下午 16:30-17:20",
                title: "阳光下室外游泳(限时30min)",
                actionDetail: "中等配速蛙泳 30 分钟，上岸立即擦干穿外套，避免吹风受凉。",
                reasoning: "\(city) \(tempC)°C \(weatherCondition)适宜下水，避开伤膝跑步。"
            )
        } else {
            fitnessCard = AIPlannedCardPayload(
                category: "fitness",
                timeSlot: "下午 17:00-17:30",
                title: "居家八段锦 + 微抗阻(20min)",
                actionDetail: "八段锦两遍（调理脾胃须单举）+ 靠墙静蹲 3×45s + 弹力带划船 3×15。",
                reasoning: "温和导引助脾运，同时保肌提升基础代谢。"
            )
        }

        let rawCards = [
            AIPlannedCardPayload(
                category: "diet",
                timeSlot: "上午 08:00-09:00",
                title: morningDrink.0,
                actionDetail: morningDrink.1,
                reasoning: morningDrink.2
            ),
            AIPlannedCardPayload(
                category: "diet",
                timeSlot: "中午 12:00-13:30",
                title: lunchMeal.0,
                actionDetail: lunchMeal.1,
                reasoning: lunchMeal.2
            ),
            fitnessCard,
            AIPlannedCardPayload(
                category: "diet",
                timeSlot: "傍晚 18:00-19:00",
                title: dinnerMeal.0,
                actionDetail: dinnerMeal.1,
                reasoning: dinnerMeal.2
            ),
            AIPlannedCardPayload(
                category: "lifestyle",
                timeSlot: "晚上 21:30",
                title: "温水泡脚 + 睡前 2 小时控水",
                actionDetail: "40°C 温水泡脚 15 分钟至微润即止，23:00 前熄灯并记录今日体感。",
                reasoning: "稳住夜间脾运与睡眠节律，助前3天试探校准。"
            )
        ]

        let cards = rawCards.map {
            DietaryAdaptationHelper.adaptPayload(
                $0,
                diningEnvironment: diningEnvironment,
                dietaryPreferences: dietaryPreferences
            )
        }

        let trialHint = needsTrial
            ? "前 3 天先以温和方案「以方测证」，第 2 天复诊后将自动提升置信度。"
            : "四诊信息充分，已直接建立专属日常顺时方案。"

        let plainDiagnosis: String
        let strategyOverview: String
        let expectedTimeline: String
        let boundary: AIDietaryBoundaryPayload

        if primary.contains("寒热错杂") {
            plainDiagnosis = "你目前主要是「上面容易上火、下面却怕冷」，脾胃运化偏弱，单纯大补容易上火、单纯清凉又容易拉肚子。"
            strategyOverview = "先用「清上温下、平调中焦」的温和茶饮和软食把脾胃稳住，避免冰冷和辛辣，运动以微汗导引为主。"
            expectedTimeline = needsTrial
                ? "前 3 天观察口干与畏寒变化（第 2 天会提醒复诊微调），一般 1～2 周睡眠和腹温会更稳。"
                : "坚持 7～14 天温和平调后，口腔上火与下肢发凉的割裂感会明显缓解。"
            boundary = AIDietaryBoundaryPayload(
                greenLightFoods: ["温热小米粥", "蒸山药/百合", "水煮蛋/嫩豆腐", "温热无糖豆浆", "常温苹果"],
                yellowLightLimit: ["杂粮饭半碗", "去皮鸡肉/清蒸鱼少量"],
                redLightAvoid: ["辛辣烧烤", "冰镇饮品", "纯姜大补汤", "寒凉生冷海鲜"],
                flexibilityNote: "食谱只是省心示范，只要避开太辣太冰、保持温热七分饱，外食换同类家常菜一样算达标。"
            )
        } else if primary.contains("湿热") {
            plainDiagnosis = "你目前主要是「脾胃湿滞偏热」，容易出现口干口苦、大便偏黏或皮肤发油，不适合直接喝姜茶等温燥食物。"
            strategyOverview = "先撤掉温燥调料，用「清利湿热、轻食通腑」把积热湿浊疏导出去，再逐步恢复高蛋白减重节奏。"
            expectedTimeline = needsTrial
                ? "前 3 天看口苦与排便黏腻是否减轻（第 2 天复诊确认），约 1～2 周体感会明显清爽。"
                : "按此节奏坚持 1～2 周，晨起口苦和大便粘滞通常会明显改善。"
            boundary = AIDietaryBoundaryPayload(
                greenLightFoods: ["冬瓜/丝瓜/苦瓜", "嫩豆腐/清蒸蛋白", "炒薏米荷叶淡茶", "温热绿叶菜"],
                yellowLightLimit: ["杂粮饭半碗", "温和清甜水果少量"],
                redLightAvoid: ["火锅烧烤油炸", "老姜肉桂进补", "冰镇奶茶啤酒", "甜腻糕点"],
                flexibilityNote: "不必逐字照做：做到「清淡少油+少甜少辣」，聚餐时多夹绿叶菜和清炖蛋白、用热汤涮去浮油即可。"
            )
        } else if primary.contains("阳虚") {
            plainDiagnosis = "你目前主要是「脾阳偏虚、体内有寒湿」，一吃凉的或吹风就容易腹部不适、手脚凉、精力偏乏。"
            strategyOverview = "先做「温中散寒、培土固胃」，早上一定要吃温热谷物护胃，暂避生冷果蔬和冰饮，把阳气慢慢养回来。"
            expectedTimeline = needsTrial
                ? "前 3 天观察喝完温饮后胃里是否暖和、大便是否成形，一般 2～3 周手脚发凉和乏力会改善。"
                : "坚持 2 周温养脾胃后，对生冷的敏感度和午后犯困感都会明显降低。"
            boundary = AIDietaryBoundaryPayload(
                greenLightFoods: ["热小米南瓜粥", "水煮蛋/温热鸡汤", "蒸山药红薯", "生姜陈皮红枣茶"],
                yellowLightLimit: ["清淡炒时蔬", "温水烫过的水果"],
                redLightAvoid: ["冰饮冷酸奶", "生冷沙拉刺生", "螃蟹等寒凉海鲜", "空腹喝凉茶"],
                flexibilityNote: "重点在于「食物必须是温热的」且别挨饿，日常外食换成热汤面、热粥配蛋白同样很好。"
            )
        } else {
            plainDiagnosis = "你目前主要是「脾胃运化偏慢、水湿容易停滞」（\(primary)），还带一点轻微气虚，所以容易午后犯困、体重难降。"
            strategyOverview = "先用 3 天温和方式「唤醒脾胃、轻量祛湿」，再进入高蛋白低碳水减重与护膝运动，不搞伤胃的激进节食。"
            expectedTimeline = needsTrial
                ? "前 3 天观察大便成型度与午后困倦感（第 2 天复诊校准），一般 7～14 天能感到身体变轻快。"
                : "坚持 14 天顺时节奏后，晨起浮肿沉重感会减轻，体重也会开始稳步回落。"
            boundary = AIDietaryBoundaryPayload(
                greenLightFoods: ["水煮蛋/蒸蛋", "温热无糖豆浆", "蒸山药/玉米", "清炖鸡胸/瘦肉/豆腐", "时令绿叶菜"],
                yellowLightLimit: ["糙米/杂粮饭半碗", "常温微甜水果少量"],
                redLightAvoid: ["冰镇饮品", "高糖奶茶糕点", "宵夜炸物烧烤", "过量寒凉海鲜"],
                flexibilityNote: "不必把推荐食谱当考卷：按推荐吃七八分饱，饿了直接从绿灯区加餐，聚餐偏离了下一餐清淡拉回即可。"
            )
        }

        return AIOnboardingConstitutionResponse(
            primaryConstitution: primary,
            secondaryTags: secondary,
            confidencePercent: confidence,
            needsThreeDayTrial: needsTrial,
            clinicalSummary: "初诊倾向「\(primary)」\(secondary.isEmpty ? "" : "兼\(secondary.joined(separator: "、"))")（置信度 \(confidence)%）。\(trialHint)",
            plainDiagnosis: plainDiagnosis,
            strategyOverview: strategyOverview,
            expectedTimeline: expectedTimeline,
            suggestedPhaseSpec: AIRegimenPhasePayload(
                stageKind: stageKind.rawValue,
                phaseName: phaseName,
                therapeuticPrinciple: principle,
                plannedDays: needsTrial ? 3 : 14,
                exitCriteria: needsTrial
                    ? "饮用晨间调理饮后胃肠舒适、不上火不腹胀，且第2天大便与精力向好"
                    : "排便成形、晨起轻快不困重且作息平稳",
                nextStageHint: needsTrial
                    ? "第 2～3 天复诊确认耐受后，置信度升至 82%+ 并进入稳态期"
                    : "持续顺时固本，随二十四节气微调",
                dietaryBoundary: boundary
            ),
            initialDayCards: cards,
            baselineDeltaSummary: "完成四诊合参建档（初始置信度 \(confidence)%）",
            baselineToleranceNote: needsTrial ? "前 3 天试探校准中，留意对晨饮与运动的反应" : "初始基线已建立"
        )
    }
}
