# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，记录 **AuraLife** 的各阶段功能演进与变更历史。

---

## [Unreleased] - develop

### Added (Phase 5：中医分期与治法模型)
- 新增 `RegimenPhase` SwiftData 模型与 `RegimenStageKind` 四期临床枚举（`急症治标期` / `祛邪疏通期` / `缓调扶正期` / `顺时固本期`），记录治法总则、预计周期、转段标准（Exit Criteria）、下一阶段方向与生命周期状态。
- 新增 `RegimenPhaseRoadmapSheet` 视图，展示当前调理阶段进度条、治法总则、转段标准、中医四阶段演进路线图与历史阶段记录。
- 为 `DailyContextSnapshot` 关联 `regimenPhase` 与 `therapeuticPrinciple`（支持 SwiftData 轻量级迁移），并在 `MockDataSeeder` 中为存量数据自动补全初始阶段关联。

### Changed (Phase 5)
- 升级 `AIStructuredModels` 与 `AIStructuredSchemas`，在多日规划（`AIMultiDayPlanResponse`）与动态微调（`AIAdjustmentResponse`）中强制输出 `phaseSpec`（分期、治法总则、预计天数、转段标准）。
- 升级 `AIPromptBuilder`、`AIService` 与 `LocalContextPlanner`，将当前中医分期与治法总则注入全部 LLM Prompt 与离线演示引擎。
- 升级首页 `RecoveryBannerView` 与 `AdjustmentDiffSheet`，展示当前分期进度（如 `第 1/3 天`）及「治则」横条，应用微调时自动归档旧阶段并切换至新阶段。

### Planned
- **Phase 6**：两段式轻问诊与寒热虚实辨证追问（Interactive Triage）
- **Phase 7**：周期复诊转段闭环（Follow-up & Stage Transition）
- **Phase 8**：体质画像动态演化与个人医案（Constitution Evolution）

---

## [0.1.0] - 2026-11-16 (main)

### Added (Phase 1：MVP 骨架与本地数据)
- 创建 `AuraLife.xcodeproj`（iOS 17.0+ / Swift 6.0 / SwiftData），建立 `UserConstitutionProfile`、`DailyContextSnapshot`、`ActionCard`、`ChatAdjustmentLog` 四大核心模型。
- 建立治愈系东方极简自适应主题 `AuraTheme`（温润米白/墨黑底色 + 鼠尾草绿/暖姜黄/黛青灰）与 `HapticFeedback` 触觉反馈。
- 实现首页 `TodayTimelineView` 与 `SwipeableActionCard`（左滑完成、右滑换一换、点击展开详情），内置 `MockDataSeeder` 与 `PreviewSupport`。
- 实现 `ProfileSheetView` 与 `ConstitutionReportParser`，支持粘贴第三方体质报告文本或通过 `Vision` OCR 识别截图自动提取体质标签。

### Added (Phase 2：LLM 动态引擎与诊断工具)
- 封装 `AIService`、`AIConfiguration`、`KeychainHelper` 与 `AIPromptBuilder`，支持 OpenAI / 兼容接口、Anthropic Claude 与 Google Gemini。
- 基于 `AIStructuredSchemas` 强制执行 Structured Outputs（JSON Schema）与原生 `URLSession` SSE 流式输出，内置三层决策漏斗与离线演示引擎兜底。
- 支持未来 3 日顺时规划生成（`生成3日计划`）、跨日微调确认 `AdjustmentDiffSheet` 与单卡异步局部「换一换」。
- 新增 `AISettingsSheet`（支持 Keychain 存储密钥、HTTP 代理配置与一键连通性测试）及 `AILogSheet` / `AILogger`（Console + App 内实时请求诊断日志）。

### Added (Phase 3：生态感知与多模态)
- 接入 `WeatherContextService`（`CoreLocation` + `WeatherKit` + Open-Meteo 实时气象兜底）与 `SolarTermCalculator`（二十四节气顺时提示）。
- 接入 `HealthKitSyncService` 读取今日步数、昨晚睡眠时长与最新体重，并将环境/体征上下文全面注入 AI Prompt。
- 新增 `PhotoCheckInIntent`（自动识别 / 舌象苔色 / 餐食打卡 / 体检报告）与 `ContextEnvironmentSheet`（含 4 套城市气候模拟预设）。

### Added (Phase 4：温和通知与体验打磨)
- 新增 `GentleNotificationService` 与 `TimeSlotParser`，支持按中文时段标签与提前量调度本地提醒，提供通知内「标记已完成」与「15分钟后再提醒」快捷操作。
- 新增 `NotificationSettingsSheet` 提醒配置与测试页；升级 `SwipeableActionCard` 增加「当下顺时」焦点高亮与全天完成收尾提示卡片。
- 保存 `.cursor/rules/auralife.mdc` 规范与 Phase 5–8 演进路线图。
