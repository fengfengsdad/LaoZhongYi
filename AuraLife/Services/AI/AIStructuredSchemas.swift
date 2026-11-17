import Foundation

enum AIStructuredSchemas {
    static let multiDayPlanSchemaName = "auralife_multi_day_plan"
    static let adjustmentSchemaName = "auralife_contextual_adjustment"
    static let cardSwapSchemaName = "auralife_card_swap"

    static var multiDayPlanSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["summary", "days"],
            "properties": [
                "summary": [
                    "type": "string",
                    "description": "多日动态规划总览说明，不超过60字"
                ],
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
                                "description": "例如：急性祛湿恢复期 (第1/3天) 或 日常稳态调理期"
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
            "required": ["proposedPhase", "detectedSymptoms", "summary", "diffs"],
            "properties": [
                "proposedPhase": [
                    "type": "string",
                    "description": "例如：急性祛湿恢复期 (第1/3天) 或 日常稳态调理期"
                ],
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
                    "minItems": 1,
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
