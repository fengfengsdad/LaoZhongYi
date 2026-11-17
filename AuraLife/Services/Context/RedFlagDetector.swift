import Foundation

enum RedFlagCategory: String, Sendable {
    case giBleeding = "消化道出血风险"
    case cardiopulmonary = "心肺急症风险"
    case acuteAbdomenOrFever = "急腹症 / 感染高危"
}

struct RedFlagAssessment: Identifiable, Sendable {
    let id = UUID()
    let userInput: String
    let category: RedFlagCategory
    let matchedKeywords: [String]
    let headline: String
    let medicalGuidance: String
    let suggestedDepartment: String
    let falsePositiveHint: String
    let allowsOverrideAsMild: Bool
}

enum RedFlagDetector {
    static func evaluate(input: String) -> RedFlagAssessment? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        // 若用户明确在问句中说明“刚吃了猪血/铁剂所以黑便”，也提示核对但允许放行
        let giKeywords = ["黑便", "大便发黑", "大便黑", "柏油样", "柏油便", "便血", "带血", "拉血", "吐血", "呕血"]
        let matchedGI = giKeywords.filter { normalized.contains($0) }
        if !matchedGI.isEmpty {
            return RedFlagAssessment(
                userInput: normalized,
                category: .giBleeding,
                matchedKeywords: matchedGI,
                headline: "检测到消化道出血高危信号，暂不建议自行食疗",
                medicalGuidance: "出现黑便、柏油样便或便血/呕血属于器质性红线信号，不能当作单纯“湿热”或“积食”用饮食压制，建议今天尽快线下医院排查原因。",
                suggestedDepartment: "建议科室与检查：消化内科 · 大便潜血试验 + 血常规",
                falsePositiveHint: "排查提示：若过去 48 小时内曾食用猪血/鸭血、动物肝脏、大量黑芝麻或服用铁剂/铋剂（如枸橼酸铋钾），也可能造成大便发黑。",
                allowsOverrideAsMild: true
            )
        }

        let cardiopulmonaryKeywords = ["胸痛", "胸闷气短", "压榨性胸痛", "喘不上气", "呼吸困难", "心悸出冷汗", "眼前发黑", "晕厥"]
        let matchedCP = cardiopulmonaryKeywords.filter { normalized.contains($0) }
        if !matchedCP.isEmpty {
            return RedFlagAssessment(
                userInput: normalized,
                category: .cardiopulmonary,
                matchedKeywords: matchedCP,
                headline: "检测到心肺急症预警信号，请立即停止运动",
                medicalGuidance: "胸痛、明显胸闷气短、呼吸困难或伴冷汗/晕厥需优先排除心肺急性问题，请立即原地静坐休息，避免任何导引、游泳或抗阻训练。",
                suggestedDepartment: "建议科室与检查：急诊科 / 心内科 · 心电图 + 心肌酶排查",
                falsePositiveHint: "若仅为轻微久坐叹气感或明确情绪压力所致，建议仍先休息观察，持续不缓解请及时就医。",
                allowsOverrideAsMild: false
            )
        }

        let acuteKeywords = ["剧烈腹痛", "绞痛", "肚子剧痛", "高烧", "高热", "38.5", "39度", "突发剧烈腰痛", "剧烈腰痛", "视物旋转", "喷射性呕吐"]
        let matchedAcute = acuteKeywords.filter { normalized.contains($0) }
        if !matchedAcute.isEmpty {
            return RedFlagAssessment(
                userInput: normalized,
                category: .acuteAbdomenOrFever,
                matchedKeywords: matchedAcute,
                headline: "检测到急症/高热红线信号，请优先线下就医",
                medicalGuidance: "剧烈腹痛、突发剧烈腰痛、持续高热或视物旋转可能涉及阑尾炎、胆囊炎、泌尿系结石或急性感染，AI 食养方案不能替代医疗诊断。",
                suggestedDepartment: "建议科室与检查：急诊科 / 消化科 / 泌尿外科 · 血常规与超声排查",
                falsePositiveHint: "在明确诊断前请暂缓进补、姜茶或剧烈活动，少量温水小口抿服即可。",
                allowsOverrideAsMild: false
            )
        }

        return nil
    }
}
