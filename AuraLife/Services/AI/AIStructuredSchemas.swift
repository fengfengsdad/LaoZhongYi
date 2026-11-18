import Foundation

enum AIStructuredSchemas {
    static let multiDayPlanSchemaName = "auralife_multi_day_plan"
    static let adjustmentSchemaName = "auralife_contextual_adjustment"
    static let cardSwapSchemaName = "auralife_card_swap"
    static let phaseTransitionSchemaName = "auralife_phase_transition"
    static let onboardingFollowUpSchemaName = "auralife_onboarding_followup"
    static let onboardingAssessmentSchemaName = "auralife_onboarding_assessment"

    static var multiDayPlanSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["summary", "phaseSpec", "days"],
            "properties": [
                "summary": [
                    "type": "string",
                    "description": "多日动态规划总览说明，不超过60字"
                ],
                "phaseSpec": phaseSpecSchema,
                "days": [
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 5,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["dayOffset", "recoveryPhase", "detectedSymptoms", "cards"],
                        "properties": [
                            "dayOffset": [
                                "type": "integer",
                                "description": "0代表今日，1代表明日，2代表后日"
                            ],
                            "recoveryPhase": [
                                "type": "string",
                                "description": "例如：急性祛湿恢复期 (第1/3天) 或 日常顺时固本期 (第1天)"
                            ],
                            "detectedSymptoms": [
                                "type": "array",
                                "items": ["type": "string"]
                            ],
                            "cards": [
                                "type": "array",
                                "minItems": 3,
                                "maxItems": 6,
                                "items": plannedCardSchema
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    static var adjustmentSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "resolutionStatus",
                "clarificationReason",
                "redFlagAdvice",
                "triageQuestions",
                "proposedPhase",
                "phaseSpec",
                "detectedSymptoms",
                "summary",
                "diffs"
            ],
            "properties": [
                "resolutionStatus": [
                    "type": "string",
                    "enum": ["needsClarification", "readyToAdjust", "redFlagWarning"],
                    "description": "命中黑便/便血/胸闷胸痛/剧烈腹痛/高热等器质性红线时填 redFlagWarning；需辨证追问填 needsClarification；可直接调整填 readyToAdjust"
                ],
                "clarificationReason": [
                    "type": "string",
                    "description": "若为 needsClarification，用1句话解释为何需要补充辨证（不超过45字）；否则填空字符串"
                ],
                "redFlagAdvice": [
                    "type": "string",
                    "description": "若为 redFlagWarning，给出建议就医科室与排查项目（如消化科查大便潜血）；否则填空字符串"
                ],
                "triageQuestions": [
                    "type": "array",
                    "maxItems": 2,
                    "description": "当 resolutionStatus 为 needsClarification 时提供 1~2 道极简辨证选择题；readyToAdjust 时为空数组",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["id", "question", "options"],
                        "properties": [
                            "id": ["type": "string"],
                            "question": ["type": "string"],
                            "options": [
                                "type": "array",
                                "minItems": 2,
                                "maxItems": 3,
                                "items": ["type": "string"]
                            ]
                        ]
                    ]
                ],
                "proposedPhase": [
                    "type": "string",
                    "description": "例如：急性祛湿恢复期 (第1/3天) 或 日常顺时固本期"
                ],
                "phaseSpec": phaseSpecSchema,
                "detectedSymptoms": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "summary": [
                    "type": "string",
                    "description": "一句话向用户解释本次为何调整计划"
                ],
                "diffs": [
                    "type": "array",
                    "description": "readyToAdjust 时返回 1 条以上调整；needsClarification 时返回空数组 []",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": [
                            "dayOffset",
                            "targetCardID",
                            "category",
                            "timeSlot",
                            "updatedTitle",
                            "updatedDetail",
                            "updatedReasoning",
                            "corePrinciple",
                            "flexibleSwapHint"
                        ],
                        "properties": [
                            "dayOffset": [
                                "type": "integer",
                                "description": "0代表今日，1代表明日，2代表后日"
                            ],
                            "targetCardID": [
                                "type": ["string", "null"],
                                "description": "要替换的现有卡片UUID；若为新增卡片则填null"
                            ],
                            "category": [
                                "type": "string",
                                "enum": ["diet", "fitness", "lifestyle"]
                            ],
                            "timeSlot": [
                                "type": "string",
                                "description": "例如：上午 08:00-09:00 或 下午 17:00-17:30"
                            ],
                            "updatedTitle": [
                                "type": "string"
                            ],
                            "updatedDetail": [
                                "type": "string"
                            ],
                            "updatedReasoning": [
                                "type": "string",
                                "description": "不超过30字的大白话解释，说明结合了哪项体质特征或天气因素"
                            ],
                            "corePrinciple": [
                                "type": "string",
                                "description": "一句话说明本餐或本运动的核心原则（例如：温热+优质蛋白+少油）"
                            ],
                            "flexibleSwapHint": [
                                "type": "string",
                                "description": "防焦虑提示：说明换哪些食材也算达标、饿了可加餐什么"
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    static var cardSwapSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "actionDetail", "reasoning", "corePrinciple", "flexibleSwapHint"],
            "properties": [
                "title": ["type": "string"],
                "actionDetail": ["type": "string"],
                "reasoning": [
                    "type": "string",
                    "description": "不超过30字的大白话解释，说明结合了哪项体质特征或天气因素"
                ],
                "corePrinciple": [
                    "type": "string",
                    "description": "本项安排的核心原则（不超过24字）"
                ],
                "flexibleSwapHint": [
                    "type": "string",
                    "description": "可替换食材或防焦虑加餐提示"
                ]
            ]
        ]
    }

    static var phaseTransitionSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "transitionDecision",
                "clinicalAssessment",
                "summary",
                "newPhaseSpec",
                "evolutionSpec",
                "remainingSymptoms",
                "cards"
            ],
            "properties": [
                "transitionDecision": [
                    "type": "string",
                    "enum": ["advanceToNextStage", "extendCurrentStage", "adjustPlan"],
                    "description": "advanceToNextStage=症状好转推进至下一阶段，extendCurrentStage=延续当前阶段巩固，adjustPlan=重估调整"
                ],
                "clinicalAssessment": [
                    "type": "string",
                    "description": "一句中医复诊评估结论，如：脾胃寒湿已退七八，具备转入祛邪疏通期条件"
                ],
                "summary": [
                    "type": "string",
                    "description": "向用户解释本次转段或巩固的核心变化"
                ],
                "newPhaseSpec": phaseSpecSchema,
                "evolutionSpec": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": [
                        "shouldUpdateProfile",
                        "updatedConstitutionTags",
                        "deltaSummary",
                        "toleranceNote"
                    ],
                    "properties": [
                        "shouldUpdateProfile": [
                            "type": "boolean",
                            "description": "若体质偏颇评分或脾胃耐受有明显变化则填 true"
                        ],
                        "updatedConstitutionTags": [
                            "type": "array",
                            "description": "更新后的体质标签列表（如痰湿质由78分调为75分）",
                            "items": ["type": "string"]
                        ],
                        "deltaSummary": [
                            "type": "string",
                            "description": "一句简短体质演进总结，如：寒湿反应平复，痰湿负荷略有回落"
                        ],
                        "toleranceNote": [
                            "type": "string",
                            "description": "记录本周期耐受/反馈（如：对炒薏米焦米水与八段锦耐受良好）"
                        ]
                    ]
                ],
                "remainingSymptoms": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "cards": [
                    "type": "array",
                    "minItems": 3,
                    "maxItems": 6,
                    "items": plannedCardSchema
                ]
            ]
        ]
    }

    static var onboardingFollowUpSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["needFollowUp", "reasoningHint", "questions"],
            "properties": [
                "needFollowUp": [
                    "type": "boolean",
                    "description": "当基础四诊出现寒热交织、虚实未明或偏颇交界时填 true，否则填 false"
                ],
                "reasoningHint": [
                    "type": "string",
                    "description": "一句话说明为什么需要或无需补充追问"
                ],
                "questions": [
                    "type": "array",
                    "maxItems": 2,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["id", "question", "options"],
                        "properties": [
                            "id": ["type": "string"],
                            "question": ["type": "string"],
                            "options": [
                                "type": "array",
                                "minItems": 2,
                                "maxItems": 4,
                                "items": ["type": "string"]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    static var onboardingAssessmentSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "primaryConstitution",
                "secondaryTags",
                "confidencePercent",
                "needsThreeDayTrial",
                "clinicalSummary",
                "plainDiagnosis",
                "strategyOverview",
                "expectedTimeline",
                "suggestedPhaseSpec",
                "initialDayCards",
                "baselineDeltaSummary",
                "baselineToleranceNote"
            ],
            "properties": [
                "primaryConstitution": [
                    "type": "string",
                    "description": "主体质及倾向分，如：痰湿质74分、气虚质68分、湿热质72分"
                ],
                "secondaryTags": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "confidencePercent": [
                    "type": "integer",
                    "description": "初筛判断置信度 45~95（仅问答一般65~75，结合舌象或报告可80~90）"
                ],
                "needsThreeDayTrial": [
                    "type": "boolean",
                    "description": "当置信度 < 80 或存在兼夹未定证型时填 true，开启3天以方测证试探校准"
                ],
                "clinicalSummary": [
                    "type": "string",
                    "description": "60字以内的初诊辨证小结，交代主兼体质、环境因素及是否需试探校准"
                ],
                "plainDiagnosis": [
                    "type": "string",
                    "description": "大白话像老中医面诊一样交代：你当前身体主要卡在什么问题（60字以内）"
                ],
                "strategyOverview": [
                    "type": "string",
                    "description": "大白话说明接下来的整体分步调理思路（先调什么、再调什么，70字以内）"
                ],
                "expectedTimeline": [
                    "type": "string",
                    "description": "说明大概需要多久、第几天看什么变化来判断有效（55字以内）"
                ],
                "suggestedPhaseSpec": phaseSpecSchema,
                "initialDayCards": [
                    "type": "array",
                    "minItems": 4,
                    "maxItems": 6,
                    "items": plannedCardSchema
                ],
                "baselineDeltaSummary": [
                    "type": "string",
                    "description": "首条演进基线摘要"
                ],
                "baselineToleranceNote": [
                    "type": "string",
                    "description": "初始耐受与禁忌注意事项"
                ]
            ]
        ]
    }

    private static var phaseSpecSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": [
                "stageKind",
                "phaseName",
                "therapeuticPrinciple",
                "plannedDays",
                "exitCriteria",
                "nextStageHint",
                "dietaryBoundary"
            ],
            "properties": [
                "stageKind": [
                    "type": "string",
                    "enum": ["acuteRelief", "dampnessClearing", "tonifying", "maintenance"],
                    "description": "acuteRelief=急症治标期，dampnessClearing=祛邪疏通期，tonifying=缓调扶正期，maintenance=顺时固本期"
                ],
                "phaseName": [
                    "type": "string",
                    "description": "阶段名称，例如：急性祛湿恢复期 或 日常顺时固本期"
                ],
                "therapeuticPrinciple": [
                    "type": "string",
                    "description": "中医治法总则，如：温中散寒、先护胃气，暂缓减重与生冷（10~28字）"
                ],
                "plannedDays": [
                    "type": "integer",
                    "description": "本阶段预计持续天数，急症治标期一般为2-3天，祛邪疏通期3-5天，稳态固本期7-14天"
                ],
                "exitCriteria": [
                    "type": "string",
                    "description": "可感知的转段判断标准，如：排便成形、胃脘暖和且晨起不困重"
                ],
                "nextStageHint": [
                    "type": "string",
                    "description": "达标后的下一调理阶段，如：转入祛邪疏通期，逐步恢复高蛋白与抗阻"
                ],
                "dietaryBoundary": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["greenLightFoods", "yellowLightLimit", "redLightAvoid", "flexibilityNote"],
                    "properties": [
                        "greenLightFoods": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "本阶段放心吃与饿了可加餐的3~5样安全食物"
                        ],
                        "yellowLightLimit": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "黄灯减量吃（如杂粮饭半碗、常温水果少量）"
                        ],
                        "redLightAvoid": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "红灯本阶段尽量避开的3~4样食物"
                        ],
                        "flexibilityNote": [
                            "type": "string",
                            "description": "一句缓解饮食焦虑的弹性说明（如饿了从绿灯加餐、不必死扣食谱）"
                        ]
                    ]
                ]
            ]
        ]
    }

    private static var plannedCardSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["category", "timeSlot", "title", "actionDetail", "reasoning", "corePrinciple", "flexibleSwapHint"],
            "properties": [
                "category": [
                    "type": "string",
                    "enum": ["diet", "fitness", "lifestyle"]
                ],
                "timeSlot": ["type": "string"],
                "title": ["type": "string"],
                "actionDetail": ["type": "string"],
                "reasoning": [
                    "type": "string",
                    "description": "不超过30字的大白话解释，说明结合了哪项体质特征或天气因素"
                ],
                "corePrinciple": [
                    "type": "string",
                    "description": "本餐或本运动的核心原则，说明做到什么就算达标"
                ],
                "flexibleSwapHint": [
                    "type": "string",
                    "description": "吃不惯时的安全替代建议或饿了如何加餐"
                ]
            ]
        ]
    }

    /// Gemini `responseSchema` 不支持 `type: ["string", "null"]` 数组写法，这里转为 `nullable: true` 格式
    static func geminiCompatibleSchema(from schema: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in schema {
            if key == "additionalProperties" {
                continue
            }
            if key == "type", let types = value as? [String] {
                let nonNull = types.first(where: { $0 != "null" }) ?? "string"
                result["type"] = nonNull
                if types.contains("null") {
                    result["nullable"] = true
                }
                continue
            }
            if let dict = value as? [String: Any] {
                result[key] = geminiCompatibleSchema(from: dict)
            } else if let array = value as? [[String: Any]] {
                result[key] = array.map { geminiCompatibleSchema(from: $0) }
            } else {
                result[key] = value
            }
        }
        return result
    }
}
