# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，记录 **AuraLife** 的各阶段功能演进与变更历史。

---

## [Unreleased] - develop

### Added (Phase 9 优先级 1：首次建档引导、4+2 问诊与标准化舌象)
- 新增 `OnboardingFlowView` 四步首次使用建档流程（支持 `#Preview`）：基础体征与饮食/运动偏好（含「示例体验」入口）→ 四诊合参辨体质 → 环境定位与通知授权 → 初诊结果与首日方案生成。
- 新增 `TongueCaptureSheet`（`AVFoundation` 自然白光自动白平衡拍摄引导 + `CoreImage` 照度质检 + 模拟器相册兜底），并在 `project.pbxproj` 补充 `NSCameraUsageDescription` 权限说明。
- 在 `AIStructuredModels`、`AIStructuredSchemas`、`AIPromptBuilder`、`AIService` 与 `LocalContextPlanner` 中新增「4+2 自适应十问歌追问」（`auralife_onboarding_followup`）及「四诊合参初诊定方」（`auralife_onboarding_assessment`），支持上热下寒、寒湿、湿热等精细辨证与「置信度 + 3 天以方测证试探校准」。

### Changed (Phase 9 优先级 1)
- 为 `UserConstitutionProfile` 新增 `constitutionConfidencePercent`、`assessmentMethod` 与 `needsCalibrationTrial` 字段；在 `TodayTimelineView` 复诊转段时自动根据反馈校准置信度。
- 升级 `ContentView` 自动区分新用户建档与存量用户平滑进入；在 `ProfileSheetView` 展示置信度与「重新运行首次四诊合参建档引导」入口。
- 更新 `.cursor/rules/auralife.mdc`，补充 Phase 9（含优先级 1～3）完整规划。

### Planned (Phase 9 后续优先级)
- **Phase 9 优先级 2**：扩展 `HealthKitSyncService` 读取近 14 天静息心率、HRV、睡眠规律与经期趋势，交叉验证寒热虚实。
- **Phase 9 优先级 3**：接入 Apple `Speech` 框架实现语音口述问诊与状态打卡。

### Added (Phase 8：体质画像动态演化与个人医案档案)
- 新增 `ConstitutionEvolutionRecord` SwiftData 模型，按周期沉淀证型评估、治法总则、主体质分值趋势、演化总结与耐受反馈；在 `UserConstitutionProfile` 中新增 `toleranceNotes` 持久化字段并在 `MockDataSeeder` 注入初始建档基线。
- 在 `AIStructuredModels`、`AIStructuredSchemas` 与 `LocalContextPlanner` 中为复诊转段新增 `evolutionSpec`（`AIConstitutionEvolutionPayload`），支持好转转段时自动温和更新体质标签与评分。

### Changed (Phase 8)
- 升级 `AIPromptBuilder` 将 `toleranceNotes`（既往食材/运动耐受反馈）纳入长期体质画像 Prompt，使后续规划越用越贴合个体反应。
- 升级 `PhaseFollowUpSheet` 展示体质演化与耐受沉淀预览；在 `TodayTimelineView` 确认转段时自动写回 `UserConstitutionProfile` 并创建 `ConstitutionEvolutionRecord`。
- 升级 `ProfileSheetView` 新增「体质演化轨迹 & 耐受记忆」柱状趋势与反馈标签；将 `AdjustmentHistorySheet` 升级为「调理医案档案」（支持「调理医案」与「微调流水」双标签切换）。

### Added (Phase 7：周期复诊转段闭环)
- 新增 `FollowUpOutcome`（明显好转 / 略有改善需巩固 / 仍有不适或新变化）与 `RegimenPhase.shouldSuggestFollowUp` 复诊节点判定逻辑。
- 新增 `PhaseFollowUpBannerCard`（今日时间轴复诊提示卡）与 `PhaseFollowUpSheet`（复诊评估与转段预览弹窗，支持 `#Preview`）。
- 在 `AIStructuredModels`、`AIStructuredSchemas`、`AIPromptBuilder` 与 `AIService` 中新增 `evaluatePhaseFollowUp` 接口与 `auralife_phase_transition` Schema，在 `LocalContextPlanner` 中完善四阶段逐级推演逻辑（`急症治标 → 祛邪疏通 → 缓调扶正 → 顺时固本`）。

### Changed (Phase 7)
- 升级 `RegimenPhaseRoadmapSheet`，支持在阶段路线图中随时手动发起「阶段复诊 / 评估转段」。
- 升级 `TodayTimelineView`，支持自动归档旧阶段、开启或顺延阶段、重排当日卡片、记录 `ChatAdjustmentLog` 并同步刷新温和通知。

### Added (Phase 6：两段式轻问诊与寒热虚实辨证追问)
- 新增 `SymptomTriageSheet` 轻问诊弹窗（支持 `#Preview`），针对存在寒热虚实歧义的症状输入提供 1～2 道极简点选胶囊题与可选体感补充。
- 在 `AIStructuredModels` 与 `AIStructuredSchemas` 中新增 `resolutionStatus`（`needsClarification` / `readyToAdjust`）、`clarificationReason` 与 `triageQuestions` 双分支结构化输出。
- 在 `LocalContextPlanner` 中实现「同症异治」离线演示辨证逻辑：寒湿偏盛推荐温中焦米姜水，湿热积滞自动撤姜改用冬瓜荷叶淡饮与清疏导滞。

### Changed (Phase 6)
- 升级 `AIPromptBuilder`、`AIService` 与 `TodayTimelineView`，实现偏好调整直出 Diff、模糊症状先追问再定方的两段式动态微调流，并将辨证结论记入 `ChatAdjustmentLog` 与 `AdjustmentDiffSheet`。
- 在 `QuickCheckInBar` 快捷状态词中新增「昨晚吃坏肚子了」，便于直接触发两段式轻问诊体验。

### Added (Phase 5：中医分期与治法模型)
- 新增 `RegimenPhase` SwiftData 模型与 `RegimenStageKind` 四期临床枚举（`急症治标期` / `祛邪疏通期` / `缓调扶正期` / `顺时固本期`），记录治法总则、预计周期、转段标准（Exit Criteria）、下一阶段方向与生命周期状态。
- 新增 `RegimenPhaseRoadmapSheet` 视图，展示当前调理阶段进度条、治法总则、转段标准、中医四阶段演进路线图与历史阶段记录。
- 为 `DailyContextSnapshot` 关联 `regimenPhase` 与 `therapeuticPrinciple`（支持 SwiftData 轻量级迁移），并在 `MockDataSeeder` 中为存量数据自动补全初始阶段关联。

### Changed (Phase 5)
- 升级 `AIStructuredModels` 与 `AIStructuredSchemas`，在多日规划（`AIMultiDayPlanResponse`）与动态微调（`AIAdjustmentResponse`）中强制输出 `phaseSpec`（分期、治法总则、预计天数、转段标准）。
- 升级 `AIPromptBuilder`、`AIService` 与 `LocalContextPlanner`，将当前中医分期与治法总则注入全部 LLM Prompt 与离线演示引擎。
- 升级首页 `RecoveryBannerView` 与 `AdjustmentDiffSheet`，展示当前分期进度（如 `第 1/3 天`）及「治则」横条，应用微调时自动归档旧阶段并切换至新阶段。

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
