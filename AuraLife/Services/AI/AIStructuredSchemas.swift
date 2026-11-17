import Foundation

enum AIStructuredSchemas {
    static let multiDayPlanSchemaName = "auralife_multi_day_plan"
    static let adjustmentSchemaName = "auralife_contextual_adjustment"
    static let cardSwapSchemaName = "auralife_card_swap"
    static let phaseTransitionSchemaName = "auralife_phase_transition"

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
                    "enum": ["needsClarification", "readyToAdjust"],
                    "description": "当用户症状寒热虚实不明确且未补充追问时填 needsClarification；偏好类调整或信息已充足时填 readyToAdjust"
                ],
                "clarificationReason": [
                    "type": "string",
                    "description": "若为 needsClarification，用1句话解释为何需要补充辨证（不超过45字）；否则填空字符串"
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
                            "updatedReasoning"
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
                                "description": "例如：上午 09:30 或 下午 17:00-17:30"
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
            "required": ["title", "actionDetail", "reasoning"],
            "properties": [
                "title": ["type": "string"],
                "actionDetail": ["type": "string"],
                "reasoning": [
                    "type": "string",
                    "description": "不超过30字的大白话解释，说明结合了哪项体质特征或天气因素"
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
                "nextStageHint"
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
                ]
            ]
        ]
    }

    private static var plannedCardSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["category", "timeSlot", "title", "actionDetail", "reasoning"],
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
