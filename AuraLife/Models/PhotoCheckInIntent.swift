import Foundation

enum PhotoCheckInIntent: String, CaseIterable, Identifiable, Sendable {
    case auto = "自动识别"
    case tongue = "舌象苔色"
    case meal = "餐食打卡"
    case report = "体检/体质报告"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .auto: return "sparkles"
        case .tongue: return "mouth"
        case .meal: return "fork.knife"
        case .report: return "doc.text.viewfinder"
        }
    }

    var defaultPromptHint: String {
        switch self {
        case .auto:
            return "上传了一张照片，请评估我的状态并微调今日计划"
        case .tongue:
            return "上传了舌象照片，请结合舌苔厚腻/齿痕情况调整今日祛湿与饮食计划"
        case .meal:
            return "上传了餐食照片，请评估这餐的寒热湿腻度并动态微调下一餐与运动安排"
        case .report:
            return "上传了体检或体质报告照片，请结合指标更新今日调理方案"
        }
    }
}
