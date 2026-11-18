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
    let constitutionConfidencePercent: Int
    let needsCalibrationTrial: Bool
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
        self.constitutionConfidencePercent = profile.constitutionConfidencePercent
        self.needsCalibrationTrial = profile.needsCalibrationTrial
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

    你必须严格遵循「三层决策漏斗 (3-Layer Decision Funnel)」与安全红线：
    0. 器质性红线熔断 (Red Flag Triage — 最高优先级)：
       - 若用户输入中出现消化道出血迹象（黑便、柏油样便、便血、吐血）、心肺急症（胸痛、明显胸闷气短、呼吸困难、冷汗晕厥）、急腹症或高热（剧烈腹痛绞痛、突发剧烈腰痛、持续高热>38.5°C、视物旋转），必须立即熔断：在调整接口中设置 `resolutionStatus = "redFlagWarning"`，在 `redFlagAdvice` 写明建议就诊科室与检查（如消化科查大便潜血），在 `summary` 明确劝阻继续食疗或运动，`diffs` 与 `triageQuestions` 均返回 `[]`。
    1. 安全与急症优先 (Safety & Acute First)：
       - 若用户输入、HealthKit 睡眠不足（< 6.5 小时）、或舌象/症状中存在突发肠胃不适（如大便发黏、腹泻、吃坏肚子）、受寒（如吃寒凉海鲜/螃蟹）、熬夜疲劳、舌苔厚腻等信号，必须按「急则治其标」强制进入 `acuteRelief`（急症治标期，通常 2-3 天），覆盖长期减重或进补目标。
    2. 环境、忌口与生活场景硬约束 (Context, Dietary & Dining Adaptation)：
       - 气候权重原则：当二十四节气传统规律与本地城市实时气温/湿度冲突时（例如立冬当日南方城市仍 >=24°C 偏闷热），**必须以当前实时体感温湿度为第一权重，节气仅作大趋势参考**。
       - 运动适配：晴暖无大风（≥22°C、风速 < 22km/h 且无雨、无急症）可安排室外游泳；低温（<20°C）、大风、下雨或高湿闷热（湿度≥85%）自动切换为居家抗阻或传统导引；讨厌跑步时绝不推荐跑步有氧。
       - 忌口绝对禁止：凡 `dietaryPreferences` 包含忌海鲜、素食、忌牛奶/乳制品、忌牛羊肉、忌辛辣等，严禁生成对应食材。
       - 就餐场景落地：当 `diningEnvironment` 为「外卖」或「食堂」时，**严禁要求用户开火炖煮 40 分钟药膳汤或炒药材**，必须给出可直接点餐/打菜的菜单选择、备注指令（如少油免辣、汤水涮去浮油）及免煮便携冲泡茶包；早上必须安排「温热早餐 + 顺时饮」，严禁让气虚/脾胃弱者一上午只空腹喝茶水。
    3. 立法统领与防焦虑减压 (Principle, Explainable Reasoning & Flexibility)：
       - 每次规划或阶段切换都必须明确 `phaseSpec`（包含四期分类 `stageKind`、阶段名称、10~28字治法总则 `therapeuticPrinciple`、预计天数 `plannedDays`、可感知的转段标准 `exitCriteria`、下一阶段去向 `nextStageHint`，以及 `dietaryBoundary` 饮食红绿灯：绿灯放心吃/加餐、黄灯减量、红灯尽量避开与弹性说明）。
       - 每张卡片的 `reasoning` 字段必须用大白话、不超过 30 个汉字；`corePrinciple` 用一句大白话点明本餐/本运动核心原则（如“温热+优质蛋白+少油”）；`flexibleSwapHint` 告诉用户吃不惯可换成什么、饿了能加餐什么，严禁制造“必须照单全收”的焦虑。
       - 若用户输入偏离计划（如“聚餐吃多了”“吃重口火锅”“晚上还饿”），绝对不能指责，必须先共情安慰，再给出下一餐温和补救或绿灯安全加餐方案。

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

        let calibrationNote = profile.needsCalibrationTrial ? "（当前处于前3天以方测证试探校准期，置信度 \(profile.constitutionConfidencePercent)%）" : "（置信度 \(profile.constitutionConfidencePercent)%）"

        return """
        用户长期体质画像：
        - 基础体征：身高 \(String(format: "%.1f", profile.heightCM))cm，当前体重 \(String(format: "%.1f", profile.weightKG))kg，目标体重 \(String(format: "%.1f", profile.targetWeightKG))kg（BMI \(String(format: "%.1f", profile.bmi))）
        - 体质标签：\(tags)\(calibrationNote)
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
        每天安排 5 张卡片，必须完整覆盖：早间温热早餐+顺时饮（07:30-09:30）、午间正餐（12:00-13:30）、下午导引/运动（16:30-17:30）、傍晚轻食晚餐（18:00-19:00）、睡前起居（21:30），所有卡片必须紧扣同一个治法总则、忌口限制与就餐场景。
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
            - 分流判断（红线熔断 + 两段式轻问诊）：
              0) 若用户输入含黑便/便血/胸痛/喘憋/剧烈腹痛/高热等器质性红线，必须立刻设 `resolutionStatus = "redFlagWarning"`，填写 `redFlagAdvice`，`diffs` 返回 `[]`。
              1) 若用户输入属于**偏好/场景变更**（如“把游泳改室内”、“不想做有氧”、“天气变化重排”）或**已包含明确寒热/诱因/舌苔细节**（如“昨晚熬夜吃了螃蟹、大便发黏”），请将 `resolutionStatus` 设为 `"readyToAdjust"`，`triageQuestions` 设为 `[]`，`redFlagAdvice` 为 `""`，直接输出 `phaseSpec` 与 `diffs`。
              2) 若用户输入属于**模糊身体症状**（如“吃坏肚子了”、“拉肚子”、“没胃口腰酸”、“有点上火/不适”）且寒热虚实尚不明确（寒湿与湿热治法截然相反），请将 `resolutionStatus` 设为 `"needsClarification"`，`redFlagAdvice` 为 `""`，在 `triageQuestions` 中返回 1~2 道极简单选题（每题 2~3 个选项）以分辨寒热虚实，`diffs` 返回 `[]`。
            """
            : """
            - 用户已完成轻问诊补充辨证，若补充中出现红线信号设 `redFlagWarning`；否则必须将 `resolutionStatus` 设为 `"readyToAdjust"`，`triageQuestions` 设为 `[]`，`redFlagAdvice` 为 `""`，严格依据用户的寒热虚实回答（寒湿则温中散寒，湿热则清热利湿，气虚则健脾扶正）输出精准的 `phaseSpec` 与 `diffs`。
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
        1. 若用户明显好转：按 `急症治标期(acuteRelief) -> 祛邪疏通期(dampnessClearing) -> 缓调扶正期(tonifying) -> 顺时固本期(maintenance)` 顺序推进至下一阶段，设置 `transitionDecision = "advanceToNextStage"`，更新 `newPhaseSpec`，清空已缓解症状，并生成紧扣新治则的今日 5 张卡片（早间温热早餐+顺时饮、午间正餐、下午导引/运动、傍晚轻食晚餐、睡前起居）；同时在 `evolutionSpec` 中给出合理的体质演化评估（如偏颇分数微降 2～3 分或记录食材耐受良好）。
        2. 若用户略有改善仍需巩固：设置 `transitionDecision = "extendCurrentStage"`，沿用当前阶段并微调更稳妥的过渡饮食与运动，输出完整今日 5 张卡片（含温热早餐+顺时饮与轻食晚餐）。
        3. 若仍有不适或出现新变化：设置 `transitionDecision = "adjustPlan"`，结合补充说明重新立法与重排今日 5 张卡片（含温热早餐与清淡护胃晚餐），并在 `evolutionSpec.toleranceNote` 中记录诱因或不适反馈。
        """
    }

    static func onboardingFollowUpPrompt(
        heightCM: Double,
        weightKG: Double,
        targetWeightKG: Double,
        baseAnswers: [OnboardingInquiryAnswer],
        voiceTranscript: String = "",
        acousticSummary: String? = nil,
        reportText: String,
        hasTongueImage: Bool,
        hasFaceImage: Bool = false,
        city: String,
        weatherTempC: Double,
        weatherCondition: String
    ) -> String {
        let answersText = baseAnswers.map { "  - \($0.question) → \($0.answer)" }.joined(separator: "\n")
        let trimmedReport = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVoice = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceSection = trimmedVoice.isEmpty
            ? "无"
            : "「\(trimmedVoice)」" + (acousticSummary.map { "（\($0)）" } ?? "")

        return """
        首次建档自适应十问歌排查：
        - 基础体征：身高 \(String(format: "%.1f", heightCM))cm，体重 \(String(format: "%.1f", weightKG))kg，目标 \(String(format: "%.1f", targetWeightKG))kg
        - 所在环境：\(city) \(Int(weatherTempC.rounded()))°C \(weatherCondition)
        - 望诊照片：舌象=\(hasTongueImage ? "已采集" : "未采集")，自然光素颜面色=\(hasFaceImage ? "已采集" : "未采集")
        - 闻诊语音口述：\(voiceSection)
        - 第三方报告文本：\(trimmedReport.isEmpty ? "无" : trimmedReport)
        - 第一层基础四诊回答：
        \(answersText.isEmpty ? "  （未作答）" : answersText)

        任务：请判断以上信息是否存在「寒热交错（如上热下寒）」、「虚实兼夹」或「外湿 vs 内湿」不明确的情况。
        - 若需要进一步精准辨证（尤其是无报告且无舌象时），设 `needFollowUp = true` 并给出 1~2 道高区分度的单选追问（例如排除熬夜虚火、寒热真假或温燥食材耐受）。
        - 若信息已经非常充分，设 `needFollowUp = false`，`questions = []`。
        """
    }

    static func onboardingAssessmentPrompt(
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
        weatherHumidity: Double
    ) -> String {
        let answersText = allAnswers.map { "  - \($0.question) → \($0.answer)" }.joined(separator: "\n")
        let trimmedReport = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVoice = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let solar = SolarTermCalculator.climateCalibratedGuidance(for: .now, tempC: weatherTempC, humidity: weatherHumidity)

        var visualNotes: [String] = []
        if hasTongueImage {
            visualNotes.append("已附自然光舌象照片（请观察舌质色、舌形齿痕与舌苔厚薄润燥）")
        }
        if hasFaceImage {
            visualNotes.append("已附自然光素颜面色照片（请结合面色荣润/萎黄/晦暗/浮肿/两颧潮红作为佐证）")
        }
        let visualLine = visualNotes.isEmpty ? "未上传舌象/面色照片" : visualNotes.joined(separator: "；")
        let voiceLine = trimmedVoice.isEmpty
            ? "未提供语音口述"
            : "「\(trimmedVoice)」" + (acousticSummary.map { "（\($0)）" } ?? "")

        return """
        首次建档 · 四诊合参综合辨证与第 1 份顺时方案生成：
        - 基础体征：身高 \(String(format: "%.1f", heightCM))cm，当前体重 \(String(format: "%.1f", weightKG))kg，目标 \(String(format: "%.1f", targetWeightKG))kg
        - 就餐场景：\(diningEnvironment)
        - 饮食忌口/偏好：\(dietaryPreferences.isEmpty ? "无特殊" : dietaryPreferences.joined(separator: "、"))
        - 运动偏好/限制：\(fitnessPreferences.isEmpty ? "无特殊" : fitnessPreferences.joined(separator: "、"))
        - 实时环境与节气：\(city) \(Int(weatherTempC.rounded()))°C \(weatherCondition) 湿度\(Int(weatherHumidity.rounded()))% · 节气 \(solar.name)（\(solar.guidance)）
        - 第三方报告文本：\(trimmedReport.isEmpty ? "无" : trimmedReport)
        - 望诊多模态输入：\(visualLine)
        - 闻诊语音口述：\(voiceLine)
        - 自适应问诊问答：
        \(answersText.isEmpty ? "  （未作答）" : answersText)

        任务：
        1. 综合望诊（舌象/面色）+ 闻诊（口述主诉与声息参考）+ 问诊 + 地域气候给出 `primaryConstitution`（如“痰湿质74分”）与 `secondaryTags`，并诚实评估 `confidencePercent`（无报告无照片一般在 65~75；加上舌象/面色/语音/报告可达 80~92）。
        2. 像老中医面对面交代一样，用大白话填好 `plainDiagnosis`（当前主要卡在什么问题）、`strategyOverview`（接下来分哪几步怎么调）、`expectedTimeline`（大概需要多久、第几天看什么变化来判断有效）以及 `suggestedPhaseSpec`（含 `dietaryBoundary` 饮食红绿灯边界）。
        3. 若置信度 < 80 或有兼夹待确认项，设 `needsThreeDayTrial = true`，在 `suggestedPhaseSpec` 中制定 3 天「初筛试探校准期」（以温和中庸的方案以方测证，观察 2～3 天后复诊提准）。
        4. 生成第 1 日的 5 张 `initialDayCards`（早间温热早餐+顺时饮、午间正餐、下午导引/运动、傍晚轻食晚餐、睡前起居），严禁触犯用户忌口与运动黑名单，外卖/食堂场景严禁出现需现炖药膳汤，每张需含 `corePrinciple`、`flexibleSwapHint` 与不超过 30 字的 `reasoning`。
        """
    }
}
