import SwiftData
import SwiftUI

struct ProfileAndSettingsView: View {
    @AppStorage("auralife.onboarding.completed") private var hasCompletedOnboarding: Bool = true
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserConstitutionProfile]
    @Query(sort: \DailyContextSnapshot.date, order: .forward) private var snapshots: [DailyContextSnapshot]

    @State private var isShowingProfileEditor: Bool = false
    @State private var isShowingWeatherContext: Bool = false
    @State private var isShowingNotifications: Bool = false
    @State private var isShowingAISettings: Bool = false
    @State private var isShowingAILogs: Bool = false
    @State private var captureMode: DiagnosticCaptureMode = .tongue
    @State private var isShowingTongueCapture: Bool = false
    @State private var isAILiveConfigured: Bool = AIConfiguration.load().hasValidKey
    @State private var isNotificationsEnabled: Bool = NotificationPreferences.load().isEnabled
    @State private var toastMessage: String?

    private var activeProfile: UserConstitutionProfile? {
        profiles.first
    }

    private var todaySnapshot: DailyContextSnapshot? {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return snapshots.first(where: { Calendar.current.startOfDay(for: $0.date) >= startOfToday }) ?? snapshots.first
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let profile = activeProfile {
                            profileOverviewCard(profile)
                        }
                        ecologyAndRemindersSection
                        aiEngineSection
                        rebuildSection
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .background(AuraTheme.canvasBackground.ignoresSafeArea())

                if let toastMessage {
                    Text(toastMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AuraTheme.primaryText.opacity(0.88), in: Capsule())
                        .padding(.top, 8)
                }
            }
            .navigationTitle("画像与设置")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                isAILiveConfigured = AIConfiguration.load().hasValidKey
                isNotificationsEnabled = NotificationPreferences.load().isEnabled
            }
            .sheet(isPresented: $isShowingProfileEditor) {
                if let profile = activeProfile {
                    ProfileSheetView(profile: profile)
                }
            }
            .sheet(isPresented: $isShowingWeatherContext) {
                if let snapshot = todaySnapshot {
                    ContextEnvironmentSheet(
                        snapshot: snapshot,
                        profile: activeProfile,
                        onRefreshWeather: {
                            await refreshWeather()
                        },
                        onSyncHealthKit: {
                            await syncHealthKit()
                        },
                        onApplyWeatherToPlan: {
                            toastMessage = "已保存最新气象预设，回「今日」即可按天气微调"
                        }
                    )
                }
            }
            .sheet(isPresented: $isShowingNotifications) {
                NotificationSettingsSheet(
                    snapshots: snapshots,
                    onPreferencesChanged: {
                        isNotificationsEnabled = NotificationPreferences.load().isEnabled
                        return await GentleNotificationService.shared.syncNotifications(for: snapshots)
                    }
                )
            }
            .sheet(isPresented: $isShowingAISettings) {
                AISettingsSheet {
                    isAILiveConfigured = AIConfiguration.load().hasValidKey
                    showToast(isAILiveConfigured ? "已切换至云端 LLM 引擎" : "当前使用离线演示引擎")
                }
            }
            .sheet(isPresented: $isShowingAILogs) {
                AILogSheet()
            }
            .sheet(isPresented: $isShowingTongueCapture) {
                TongueCaptureSheet(mode: captureMode) { _, quality in
                    let label = captureMode == .tongue ? "舌象" : "面色"
                    showToast("\(label)照度评估：\(quality.isWarning ? "光线欠佳，建议重拍" : "自然光良好")")
                }
            }
        }
    }

    private func profileOverviewCard(_ profile: UserConstitutionProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.primaryConstitution)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(AuraTheme.primaryText)

                    Text(
                        String(
                            format: "身高 %.1fcm · 体重 %.1fkg → 目标 %.1fkg · BMI %.1f",
                            profile.heightCM,
                            profile.weightKG,
                            profile.targetWeightKG,
                            profile.bmi
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
                }

                Spacer()

                Text("置信度 \(profile.constitutionConfidencePercent)%")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(profile.constitutionConfidencePercent >= 80 ? AuraTheme.sageGreen : AuraTheme.warmGinger)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        (profile.constitutionConfidencePercent >= 80 ? AuraTheme.sageGreen : AuraTheme.warmGinger).opacity(0.13),
                        in: Capsule()
                    )
            }

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(profile.constitutionTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AuraTheme.warmGinger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AuraTheme.warmGinger.opacity(0.12), in: Capsule())
                }
                Text("就餐：\(profile.diningEnvironment)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AuraTheme.sageGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AuraTheme.sageGreen.opacity(0.12), in: Capsule())
            }

            Button {
                isShowingProfileEditor = true
            } label: {
                Label("编辑体征、忌口或导入体检报告", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AuraTheme.sageGreen, in: Capsule())
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var ecologyAndRemindersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("生态感知与温和提醒")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            settingRowButton(
                icon: "cloud.sun.fill",
                tint: AuraTheme.warmGinger,
                title: "城市气象与 HealthKit 体征",
                subtitle: todaySnapshot.map { "\($0.city) \(Int($0.weatherTempC.rounded()))°C \($0.weatherCondition) · 湿度 \(Int($0.weatherHumidity.rounded()))%" } ?? "同步天气与步数睡眠"
            ) {
                isShowingWeatherContext = true
            }

            settingRowButton(
                icon: isNotificationsEnabled ? "bell.badge.fill" : "bell",
                tint: AuraTheme.sageGreen,
                title: "关键时段顺时轻提醒",
                subtitle: isNotificationsEnabled ? "已开启 · 仅提醒未完成顺时节点" : "未开启 · 点击配置提前量与测试提醒"
            ) {
                isShowingNotifications = true
            }

            settingRowButton(
                icon: "camera.viewfinder",
                tint: AuraTheme.inkSlate,
                title: "自然光舌象拍摄质检",
                subtitle: "校验光线照度，辅助对比舌苔变化"
            ) {
                captureMode = .tongue
                isShowingTongueCapture = true
            }

            settingRowButton(
                icon: "face.smiling",
                tint: AuraTheme.warmGinger,
                title: "自然光素颜面色自检",
                subtitle: "校验自然光照度，辅助观察面色光泽与浮肿"
            ) {
                captureMode = .face
                isShowingTongueCapture = true
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var aiEngineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI 模型与诊断")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            settingRowButton(
                icon: isAILiveConfigured ? "sparkles" : "cpu",
                tint: isAILiveConfigured ? AuraTheme.sageGreen : AuraTheme.warmGinger,
                title: "AI 动态引擎配置",
                subtitle: isAILiveConfigured ? "已配置云端模型与流式输出" : "当前使用离线演示引擎（可填入 Key）"
            ) {
                isShowingAISettings = true
            }

            settingRowButton(
                icon: "terminal",
                tint: AuraTheme.inkSlate,
                title: "查看 AI 请求诊断日志",
                subtitle: "排查网络超时、SSE 分片与 JSON 解析状态"
            ) {
                isShowingAILogs = true
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var rebuildSection: some View {
        Button {
            hasCompletedOnboarding = false
        } label: {
            Label("重新运行首次四诊合参建档引导", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AuraTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func settingRowButton(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AuraTheme.primaryText)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AuraTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
            }
            .padding(10)
            .background(AuraTheme.subtleSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func refreshWeather() async -> String? {
        guard let weather = await WeatherContextService.shared.fetchCurrentWeather() else { return nil }
        for snap in snapshots {
            snap.city = weather.city
            snap.weatherTempC = weather.tempC
            snap.weatherCondition = weather.condition
            snap.weatherHumidity = weather.humidityPercent
            snap.weatherWindSpeedKmh = weather.windSpeedKmh
            snap.weatherSource = weather.source
        }
        try? modelContext.save()
        return "已更新 \(weather.city) \(Int(weather.tempC.rounded()))°C \(weather.condition)"
    }

    private func syncHealthKit() async -> String {
        let health = await HealthKitSyncService.shared.syncTodayMetrics()
        if let today = todaySnapshot {
            today.healthStepCount = health.stepsToday
            today.healthSleepHours = health.sleepHoursLastNight
            today.healthLatestWeightKG = health.latestWeightKG
        }
        if let weight = health.latestWeightKG, let profile = activeProfile {
            profile.weightKG = weight
            profile.updatedAt = .now
        }
        try? modelContext.save()
        return health.statusMessage
    }

    private func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            await MainActor.run {
                if toastMessage == text { toastMessage = nil }
            }
        }
    }
}

#Preview {
    ProfileAndSettingsView()
        .modelContainer(PreviewSupport.makeContainer())
}
