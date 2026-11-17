import SwiftData
import SwiftUI

struct RecoveryBannerView: View {
    let snapshot: DailyContextSnapshot
    let dayTitle: String
    let profile: UserConstitutionProfile?
    let activePhase: RegimenPhase?
    let completedCount: Int
    let totalCount: Int
    let isGeneratingMultiDay: Bool
    let isAILiveConfigured: Bool
    let isNotificationsEnabled: Bool
    let onTapWeatherContext: () -> Void
    let onTapPhaseRoadmap: () -> Void
    let onTapNotifications: () -> Void
    let onTapProfile: () -> Void
    let onTapHistory: () -> Void
    let onTapAISettings: () -> Void
    let onGenerateMultiDay: () -> Void

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: snapshot.date)
    }

    private var resolvedPhase: RegimenPhase? {
        snapshot.regimenPhase ?? activePhase
    }

    private var phaseBadgeLabel: String {
        if let phase = resolvedPhase {
            return phase.badgeText(for: snapshot.date)
        }
        return snapshot.recoveryPhase
    }

    private var phasePrincipleLabel: String {
        resolvedPhase?.therapeuticPrinciple ?? snapshot.therapeuticPrinciple
    }

    private var phaseColor: Color {
        if let phase = resolvedPhase {
            return phase.stageKind.accentColor
        }
        return snapshot.isAcuteRecovery ? AuraTheme.warmGinger : AuraTheme.sageGreen
    }

    private var weatherSymbol: String {
        let cond = snapshot.weatherCondition
        if cond.contains("雨") { return "cloud.rain.fill" }
        if cond.contains("风") { return "wind" }
        if cond.contains("雪") { return "cloud.snow.fill" }
        if cond.contains("阴") || cond.contains("多云") { return "cloud.sun.fill" }
        return "sun.max.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dateText) · \(snapshot.resolvedSolarTerm.name)")
                        .font(.subheadline)
                        .foregroundStyle(AuraTheme.secondaryText)

                    Text(dayTitle)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(AuraTheme.primaryText)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onTapNotifications) {
                        Image(systemName: isNotificationsEnabled ? "bell.badge.fill" : "bell")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isNotificationsEnabled ? AuraTheme.sageGreen : AuraTheme.secondaryText)
                            .frame(width: 34, height: 34)
                            .background(AuraTheme.subtleSurface, in: Circle())
                    }
                    .accessibilityLabel("顺时温和提醒设置")

                    Button(action: onTapAISettings) {
                        Image(systemName: isAILiveConfigured ? "sparkles" : "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isAILiveConfigured ? AuraTheme.sageGreen : AuraTheme.secondaryText)
                            .frame(width: 34, height: 34)
                            .background(AuraTheme.subtleSurface, in: Circle())
                    }
                    .accessibilityLabel("AI 模型与接口设置")

                    Button(action: onTapHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AuraTheme.secondaryText)
                            .frame(width: 34, height: 34)
                            .background(AuraTheme.subtleSurface, in: Circle())
                    }
                    .accessibilityLabel("动态调整记录")

                    Button(action: onTapProfile) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 13, weight: .medium))
                            Text(profile?.primaryConstitution ?? "画像")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(AuraTheme.primaryText)
                        .padding(.horizontal, 9)
                        .frame(height: 34)
                        .background(AuraTheme.subtleSurface, in: Capsule())
                    }
                    .accessibilityLabel("查看或导入体质画像")
                }
            }

            HStack(spacing: 8) {
                Button(action: onTapWeatherContext) {
                    Label(
                        "\(snapshot.city) · \(Int(snapshot.weatherTempC.rounded()))°C \(snapshot.weatherCondition)",
                        systemImage: weatherSymbol
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AuraTheme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AuraTheme.cardSurface, in: Capsule())
                    .overlay(
                        Capsule().stroke(AuraTheme.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看或切换天气、节气与 HealthKit 上下文")

                Button(action: onTapPhaseRoadmap) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(phaseColor)
                            .frame(width: 6, height: 6)
                        Text(phaseBadgeLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(phaseColor)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(phaseColor.opacity(0.75))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(phaseColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看中医分期与治法路线")

                Spacer(minLength: 0)

                Text("\(completedCount)/\(totalCount)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            Button(action: onTapPhaseRoadmap) {
                HStack(alignment: .center, spacing: 6) {
                    Text("治则")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(phaseColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(phaseColor.opacity(0.12), in: Capsule())

                    Text(phasePrincipleLabel)
                        .font(.caption)
                        .foregroundStyle(AuraTheme.primaryText.opacity(0.86))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AuraTheme.subtleSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                if !snapshot.userReportedSymptoms.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(snapshot.userReportedSymptoms, id: \.self) { symptom in
                                Text(symptom)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(AuraTheme.warmGinger)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AuraTheme.warmGinger.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                } else {
                    Button(action: onTapWeatherContext) {
                        HStack(spacing: 6) {
                            Image(systemName: "humidity")
                                .font(.caption2)
                            Text(healthSummaryText)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(AuraTheme.secondaryText)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                Button(action: onGenerateMultiDay) {
                    HStack(spacing: 5) {
                        if isGeneratingMultiDay {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(AuraTheme.sageGreen)
                        } else {
                            Image(systemName: "calendar.badge.plus")
                                .font(.caption2.weight(.semibold))
                        }
                        Text(isGeneratingMultiDay ? "编排中" : "生成3日计划")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(AuraTheme.sageGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AuraTheme.sageGreen.opacity(0.13), in: Capsule())
                }
                .disabled(isGeneratingMultiDay)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AuraTheme.hairline, lineWidth: 1)
        )
    }

    private var healthSummaryText: String {
        var parts = ["湿度 \(Int(snapshot.weatherHumidity.rounded()))%"]
        if let steps = snapshot.healthStepCount {
            parts.append("\(steps) 步")
        }
        if let sleep = snapshot.healthSleepHours {
            parts.append(String(format: "睡 %.1fh", sleep))
        }
        if parts.count == 1 {
            parts.append("点此同步 HealthKit")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let snapshots = (try? container.mainContext.fetch(FetchDescriptor<DailyContextSnapshot>())) ?? []
    let profiles = (try? container.mainContext.fetch(FetchDescriptor<UserConstitutionProfile>())) ?? []
    let phases = (try? container.mainContext.fetch(FetchDescriptor<RegimenPhase>())) ?? []

    return ZStack {
        AuraTheme.canvasBackground.ignoresSafeArea()
        if let snapshot = snapshots.first {
            RecoveryBannerView(
                snapshot: snapshot,
                dayTitle: "今日顺时调理",
                profile: profiles.first,
                activePhase: phases.first,
                completedCount: 1,
                totalCount: 4,
                isGeneratingMultiDay: false,
                isAILiveConfigured: false,
                isNotificationsEnabled: true,
                onTapWeatherContext: {},
                onTapPhaseRoadmap: {},
                onTapNotifications: {},
                onTapProfile: {},
                onTapHistory: {},
                onTapAISettings: {},
                onGenerateMultiDay: {}
            )
            .padding()
        }
    }
}
