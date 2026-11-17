import Foundation

struct AIProfileContext: Sendable {
    let heightCM: Double
    let weightKG: Double
    let targetWeightKG: Double
    let bmi: Double
    let constitutionTags: [String]
    let dietaryPreferences: [String]
    let fitnessPreferences: [String]
    let toleranceNotes: [String]
    let diningEnvironment: String

    @MainActor
    init(profile: UserConstitutionProfile) {
        self.heightCM = profile.heightCM
        self.weightKG = profile.weightKG
        self.targetWeightKG = profile.targetWeightKG
        self.bmi = profile.bmi
        self.constitutionTags = profile.constitutionTags
        self.dietaryPreferences = profile.dietaryPreferences
        self.fitnessPreferences = profile.fitnessPreferences
        self.toleranceNotes = profile.toleranceNotes
        self.diningEnvironment = profile.diningEnvironment
    }
}

struct AIRegimenPhaseContext: Sendable {
    let stageKind: RegimenStageKind
    let phaseName: String
    let therapeuticPrinciple: String
    let exitCriteria: String
    let nextStageHint: String
    let dayNumber: Int
    let plannedDays: Int

    @MainActor
    init(phase: RegimenPhase, on date: Date) {
        self.stageKind = phase.stageKind
        self.phaseName = phase.phaseName
        self.therapeuticPrinciple = phase.therapeuticPrinciple
        self.exitCriteria = phase.exitCriteria
        self.nextStageHint = phase.nextStageHint
        self.dayNumber = phase.dayNumber(for: date)
        self.plannedDays = phase.plannedDays
    }
}

struct AIActionCardContext: Sendable {
    let id: UUID
    let category: ActionCategory
    let timeSlot: String
    let title: String
    let actionDetail: String
    let reasoning: String
    let isCompleted: Bool
    let sortOrder: Int

    @MainActor
    init(card: ActionCard) {
        self.id = card.id
        self.category = card.category
        self.timeSlot = card.timeSlot
        self.title = card.title
        self.actionDetail = card.actionDetail
        self.reasoning = card.reasoning
        self.isCompleted = card.isCompleted
        self.sortOrder = card.sortOrder
    }
}

struct AISnapshotContext: Sendable {
    let date: Date
    let weatherTempC: Double
    let weatherCondition: String
    let city: String
    let weatherHumidity: Double
    let weatherWindSpeedKmh: Double
    let solarTermName: String
    let solarTermGuidance: String
    let healthStepCount: Int?
    let healthSleepHours: Double?
    let healthLatestWeightKG: Double?
    let userReportedSymptoms: [String]
    let recoveryPhase: String
    let therapeuticPrinciple: String
    let activePhase: AIRegimenPhaseContext?
    let isAcuteRecovery: Bool
    let cards: [AIActionCardContext]

    init(
        date: Date = .now,
        weatherTempC: Double = 24.0,
        weatherCondition: String = "晴",
        city: String = "深圳",
        weatherHumidity: Double = 68.0,
        weatherWindSpeedKmh: Double = 9.0,
        solarTermName: String? = nil,
        solarTermGuidance: String? = nil,
        healthStepCount: Int? = nil,
        healthSleepHours: Double? = nil,
        healthLatestWeightKG: Double? = nil,
        userReportedSymptoms: [String] = [],
        recoveryPhase: String = "日常稳态调理期",
        therapeuticPrinciple: String = "健脾化湿、温阳理气，循序渐进减重",
        activePhase: AIRegimenPhaseContext? = nil,
        isAcuteRecovery: Bool = false,
        cards: [AIActionCardContext] = []
    ) {
        let computedTerm = SolarTermCalculator.term(for: date)
        self.date = date
        self.weatherTempC = weatherTempC
        self.weatherCondition = weatherCondition
        self.city = city
        self.weatherHumidity = weatherHumidity
        self.weatherWindSpeedKmh = weatherWindSpeedKmh
        self.solarTermName = solarTermName ?? computedTerm.name
        self.solarTermGuidance = solarTermGuidance ?? computedTerm.guidance
        self.healthStepCount = healthStepCount
        self.healthSleepHours = healthSleepHours
        self.healthLatestWeightKG = healthLatestWeightKG
        self.userReportedSymptoms = userReportedSymptoms
        self.recoveryPhase = recoveryPhase
        self.therapeuticPrinciple = therapeuticPrinciple
        self.activePhase = activePhase
        self.isAcuteRecovery = isAcuteRecovery
        self.cards = cards
    }

    @MainActor
    init(snapshot: DailyContextSnapshot) {
        let resolvedTerm = snapshot.resolvedSolarTerm
        self.date = snapshot.date
        self.weatherTempC = snapshot.weatherTempC
        self.weatherCondition = snapshot.weatherCondition
        self.city = snapshot.city
        self.weatherHumidity = snapshot.weatherHumidity
        self.weatherWindSpeedKmh = snapshot.weatherWindSpeedKmh
        self.solarTermName = resolvedTerm.name
        self.solarTermGuidance = resolvedTerm.guidance
        self.healthStepCount = snapshot.healthStepCount
        self.healthSleepHours = snapshot.healthSleepHours
        self.healthLatestWeightKG = snapshot.healthLatestWeightKG
        self.userReportedSymptoms = snapshot.userReportedSymptoms
        self.recoveryPhase = snapshot.recoveryPhase
        self.therapeuticPrinciple = snapshot.regimenPhase?.therapeuticPrinciple ?? snapshot.therapeuticPrinciple
        self.activePhase = snapshot.regimenPhase.map { AIRegimenPhaseContext(phase: $0, on: snapshot.date) }
        self.isAcuteRecovery = snapshot.isAcuteRecovery
        self.cards = snapshot.sortedCards.map(AIActionCardContext.init(card:))
    }
}

enum AIPromptBuilder {
    static let systemPrompt = """
    你是 AuraLife 的中医临床与动态生活规划引擎，遵循「辨证 → 立法 → 分期 → 施膳导引」的临床思维，为用户提供极简、可执行、温和的顺时生活指令。

    你必须严格遵循「三层决策漏斗 (3-Layer Decision Funnel)」：
    1. 安全与急症优先 (Safety & Acute First)：
       - 若用户输入、HealthKit 睡眠不足（< 6.5 小时）、或舌象/症状中存在突发肠胃不适（如大便发黏、腹泻、吃坏肚子）、受寒（如吃寒凉海鲜/螃蟹）、熬夜疲劳、舌苔厚腻等信号，必须按「急则治其标」强制进入 `acuteRelief`（急症治标期，通常 2-3 天），覆盖长期减重或进补目标。
    2. 环境与约束适配 (Context Adaptation)：
       - 结合本地城市实时气温、湿度、风速、当前节气与用户偏好的就餐场景（居家做饭/外卖/食堂）、运动习惯与忌口动态调整参数。
       - 晴暖无大风（≥22°C、风速 < 22km/h 且无雨、无急症）可安排室外游泳；低温（<20°C）、大风、下雨或高湿闷热（湿度≥85%）自动切换为居家抗阻或传统导引；讨厌跑步时绝不推荐跑步有氧。
    3. 立法统领与循证可解释 (Principle & Explainable Reasoning)：
       - 每次规划或阶段切换都必须明确 `phaseSpec`（包含四期分类 `stageKind`、阶段名称、10~28字治法总则 `therapeuticPrinciple`、预计天数 `plannedDays`、可感知的转段标准 `exitCriteria` 及下一阶段去向 `nextStageHint`）。
       - 每张卡片的 `reasoning` 字段必须用大白话、不超过 30 个汉字，体现它如何服务当前治法总则并结合体质或天气。

    输出规范：
    - 严格输出符合给定 JSON Schema 的纯 JSON，不要包含 Markdown 代码块或多余解释文字。
    - `category` 仅允许使用 `diet`、`fitness`、`lifestyle`。
    - `stageKind` 仅允许使用 `acuteRelief`、`dampnessClearing`、`tonifying`、`maintenance`。
    """

    static func profileSection(_ profile: AIProfileContext?) -> String {
        guard let profile else {
            return "用户画像：暂未配置详细画像，按温和祛湿护脾胃通用原则规划。"
        }

        let tags = profile.constitutionTags.isEmpty ? "暂无" : profile.constitutionTags.joined(separator: "、")
        let diet = profile.dietaryPreferences.isEmpty ? "暂无" : profile.dietaryPreferences.joined(separator: "、")
        let fitness = profile.fitnessPreferences.isEmpty ? "暂无" : profile.fitnessPreferences.joined(separator: "、")
        let tolerance = profile.toleranceNotes.isEmpty ? "暂无记录" : profile.toleranceNotes.joined(separator: "；")

        return """
        用户长期体质画像：
        - 基础体征：身高 \(String(format: "%.1f", profile.heightCM))cm，当前体重 \(String(format: "%.1f", profile.weightKG))kg，目标体重 \(String(format: "%.1f", profile.targetWeightKG))kg（BMI \(String(format: "%.1f", profile.bmi))）
        - 体质标签：\(tags)
        - 饮食偏好与忌口：\(diet)
        - 运动偏好与限制：\(fitness)
        - 既往调理耐受反馈：\(tolerance)
        - 日常就餐场景：\(profile.diningEnvironment)
        """
    }

    static func snapshotSection(_ snapshot: AISnapshotContext) -> String {
        let symptoms = snapshot.userReportedSymptoms.isEmpty ? "无" : snapshot.userReportedSymptoms.joined(separator: "、")
        let cardsText = snapshot.cards.map { card in
            "  - [id:\(card.id.uuidString)] (\(card.category.rawValue) | \(card.timeSlot)) \(card.title) :: \(card.actionDetail)"
        }.joined(separator: "\n")

        var healthParts: [String] = []
        if let steps = snapshot.healthStepCount {
            healthParts.append("今日步数 \(steps) 步")
        }
        if let sleep = snapshot.healthSleepHours {
            healthParts.append(String(format: "昨晚睡眠 %.1f 小时", sleep))
        }
        if let weight = snapshot.healthLatestWeightKG {
            healthParts.append(String(format: "%.1fkg（HealthKit 最新体重）", weight))
        }
        let healthLine = healthParts.isEmpty ? "暂未同步（无步数/睡眠数据）" : healthParts.joined(separator: "，")

        let phaseDetails: String
        if let active = snapshot.activePhase {
            phaseDetails = """
            \(active.phaseName) [\(active.stageKind.displayName) · 第\(active.dayNumber)/\(active.plannedDays)天]
              · 治法总则：\(active.therapeuticPrinciple)
              · 转段标准：\(active.exitCriteria)
            """
        } else {
            phaseDetails = "\(snapshot.recoveryPhase)（治法总则：\(snapshot.therapeuticPrinciple)）"
        }

        return """
        今日动态上下文快照：
        - 日期与节气：\(snapshot.date.formatted(date: .numeric, time: .omitted)) · \(snapshot.solarTermName)（\(snapshot.solarTermGuidance)）
        - 实时气象：\(snapshot.city) \(Int(snapshot.weatherTempC.rounded()))°C \(snapshot.weatherCondition)，相对湿度 \(Int(snapshot.weatherHumidity.rounded()))%，风速 \(Int(snapshot.weatherWindSpeedKmh.rounded()))km/h
        - HealthKit 体征监测：\(healthLine)
        - 当前中医分期与治则：\(phaseDetails)
        - 已记录症状：\(symptoms)
        - 今日现有卡片：
        \(cardsText.isEmpty ? "  （暂无卡片）" : cardsText)
        """
    }

    static func multiDayPlanPrompt(
        daysCount: Int,
        profile: AIProfileContext?,
        snapshot: AISnapshotContext
    ) -> String {
        """
        \(profileSection(profile))

        \(snapshotSection(snapshot))

        任务：请基于以上体质画像、当前分期治则、实时气象与节气上下文，生成未来 \(daysCount) 天（dayOffset 分别为 0...\(daysCount - 1)）的生活指令计划，并给出完整的 `phaseSpec`（分期、治法总则、转段标准与下一阶段）。
        每天安排 4 张卡片，覆盖早间食养、午间正餐、下午导引/运动、晚间起居，所有卡片必须紧扣同一个治法总则。
        """
    }

    static func adjustmentPrompt(
        userInput: String,
        triageAnswers: [AITriageAnswer] = [],
        extraTriageNote: String? = nil,
        hasAttachedImage: Bool,
        photoIntent: PhotoCheckInIntent,
        recognizedPhotoText: String?,
        profile: AIProfileContext?,
        snapshots: [AISnapshotContext]
    ) -> String {
        let todaySnapshot = snapshots.first
        let contextText = todaySnapshot.map { snapshotSection($0) } ?? "今日暂无快照"
        let multiDayHints = snapshots.enumerated().dropFirst().map { index, snap in
            let titles = snap.cards.map(\.title).joined(separator: "、")
            return "  - 第\(index + 1)天 (dayOffset=\(index)) [\(snap.recoveryPhase)] 卡片：\(titles)"
        }.joined(separator: "\n")

        var imageHint = ""
        if hasAttachedImage {
            imageHint = "\n补充多模态输入：用户附带了一张照片（意图分类：\(photoIntent.rawValue)），请直接观察图片内容并结合今日气象与体质微调计划。"
            if let ocr = recognizedPhotoText?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
                imageHint += "\n照片本地 OCR 提取文字：\n\(ocr)"
            }
        }

        var triageBlock = ""
        if !triageAnswers.isEmpty {
            let answerLines = triageAnswers.map { "  - \($0.question) → \($0.selectedOption)" }.joined(separator: "\n")
            let noteText = extraTriageNote?.trimmingCharacters(in: .whitespacesAndNewlines)
            let noteLine = (noteText?.isEmpty == false) ? "\n  - 用户补充说明：\(noteText!)" : ""
            triageBlock = """

            补充轻问诊辨证结果（用户已回答）：
            \(answerLines)\(noteLine)
            """
        }

        let routingRule = triageAnswers.isEmpty
            ? """
            - 分流判断（两段式轻问诊）：
              1) 若用户输入属于**偏好/场景变更**（如“把游泳改室内”、“不想做有氧”、“天气变化重排”）或**已包含明确寒热/诱因/舌苔细节**（如“昨晚熬夜吃了螃蟹、大便发黏”），请将 `resolutionStatus` 设为 `"readyToAdjust"`，`triageQuestions` 设为 `[]`，直接输出 `phaseSpec` 与 `diffs`。
              2) 若用户输入属于**模糊身体症状**（如“吃坏肚子了”、“拉肚子”、“没胃口腰酸”、“有点上火/不适”）且寒热虚实尚不明确（寒湿与湿热治法截然相反），请将 `resolutionStatus` 设为 `"needsClarification"`，在 `triageQuestions` 中返回 1~2 道极简单选题（每题 2~3 个选项）以分辨寒热虚实，`diffs` 返回 `[]`。
            """
            : """
            - 用户已完成轻问诊补充辨证，本次必须将 `resolutionStatus` 设为 `"readyToAdjust"`，`triageQuestions` 设为 `[]`，严格依据用户的寒热虚实回答（寒湿则温中散寒，湿热则清热利湿，气虚则健脾扶正）输出精准的 `phaseSpec` 与 `diffs`。
            """

        return """
        \(profileSection(profile))

        \(contextText)
        \(multiDayHints.isEmpty ? "" : "\n未来几日现有安排：\n\(multiDayHints)")

        用户最新输入：
        「\(userInput)」\(imageHint)\(triageBlock)

        任务：请严格按「辨证 → 立法 → 分期」评估用户输入与实时环境上下文：
        \(routingRule)
        - 替换已有卡片时，`targetCardID` 请精确填写上方现有卡片的 UUID；若是新增卡片或未来几日整体重排，可填 null。
        """
    }

    static func swapCardPrompt(
        card: AIActionCardContext,
        profile: AIProfileContext?,
        snapshot: AISnapshotContext
    ) -> String {
        """
        \(profileSection(profile))

        \(snapshotSection(snapshot))

        任务：用户右滑「换一换」以下单张卡片，请在不违背当前治法总则（\(snapshot.therapeuticPrinciple)）的前提下仅替换这一张卡片：
        - 目标类别：\(card.category.rawValue) (\(card.category.displayName))
        - 目标时段：\(card.timeSlot)
        - 原卡片标题：\(card.title)
        - 原卡片内容：\(card.actionDetail)

        请给出一个明显不同但同样契合用户体质、治法总则、节气、实时天气（\(snapshot.city) \(Int(snapshot.weatherTempC.rounded()))°C \(snapshot.weatherCondition) 湿度\(Int(snapshot.weatherHumidity.rounded()))%）的替代方案，且 `reasoning` 不超过 30 字。
        """
    }

    static func phaseFollowUpPrompt(
        outcome: FollowUpOutcome,
        userNote: String,
        profile: AIProfileContext?,
        snapshot: AISnapshotContext
    ) -> String {
        let trimmedNote = userNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteLine = trimmedNote.isEmpty ? "无额外补充" : trimmedNote

        return """
        \(profileSection(profile))

        \(snapshotSection(snapshot))

        复诊评估请求：
        - 用户当前反馈：\(outcome.title)（\(outcome.subtitle)）
        - 用户补充说明：\(noteLine)

        任务：请严格依据中医「效不更方，变证易法」与转归规律进行复诊判断：
        1. 若用户明显好转：按 `急症治标期(acuteRelief) -> 祛邪疏通期(dampnessClearing) -> 缓调扶正期(tonifying) -> 顺时固本期(maintenance)` 顺序推进至下一阶段，设置 `transitionDecision = "advanceToNextStage"`，更新 `newPhaseSpec`，清空已缓解症状，并生成紧扣新治则的今日 4 张卡片；同时在 `evolutionSpec` 中给出合理的体质演化评估（如偏颇分数微降 2～3 分或记录食材耐受良好）。
        2. 若用户略有改善仍需巩固：设置 `transitionDecision = "extendCurrentStage"`，沿用当前阶段并微调更稳妥的过渡饮食与运动。
        3. 若仍有不适或出现新变化：设置 `transitionDecision = "adjustPlan"`，结合补充说明重新立法与重排今日 4 张卡片，并在 `evolutionSpec.toleranceNote` 中记录诱因或不适反馈。
        """
    }
}
