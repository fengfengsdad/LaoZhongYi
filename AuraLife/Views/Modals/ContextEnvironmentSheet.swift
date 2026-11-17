import SwiftData
import SwiftUI

struct ContextEnvironmentSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var snapshot: DailyContextSnapshot
    var profile: UserConstitutionProfile?
    let onRefreshWeather: () async -> String?
    let onSyncHealthKit: () async -> String
    let onApplyWeatherToPlan: () -> Void

    @State private var isRefreshingWeather = false
    @State private var isSyncingHealth = false
    @State private var statusMessage: String?

    private struct WeatherPreset: Identifiable {
        let id = UUID()
        let city: String
        let tempC: Double
        let condition: String
        let humidity: Double
        let windKmh: Double
    }

    private let presets: [WeatherPreset] = [
        WeatherPreset(city: "深圳", tempC: 24, condition: "晴", humidity: 68, windKmh: 9),
        WeatherPreset(city: "北京", tempC: 6, condition: "大风", humidity: 32, windKmh: 28),
        WeatherPreset(city: "成都", tempC: 16, condition: "小雨", humidity: 86, windKmh: 10),
        WeatherPreset(city: "上海", tempC: 28, condition: "多云", humidity: 82, windKmh: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weatherSection
                    solarTermSection
                    healthKitSection
                    presetSimulationSection
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("气象 · 节气 · 体征感知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AuraTheme.sageGreen)
                }
            }
        }
    }

    private var weatherSection: some View {
        let swimOK = LocalContextPlanner.isOutdoorSwimmingSuitable(
            tempC: snapshot.weatherTempC,
            condition: snapshot.weatherCondition,
            windSpeedKmh: snapshot.weatherWindSpeedKmh,
            isAcuteRecovery: snapshot.isAcuteRecovery
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("实时气象上下文", systemImage: "cloud.sun.fill")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                Text(snapshot.weatherSource)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AuraTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AuraTheme.subtleSurface, in: Capsule())
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("\(Int(snapshot.weatherTempC.rounded()))°C")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(AuraTheme.primaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.city) · \(snapshot.weatherCondition)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AuraTheme.primaryText)
                    Text("湿度 \(Int(snapshot.weatherHumidity.rounded()))% · 风速 \(Int(snapshot.weatherWindSpeedKmh.rounded()))km/h")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                Image(systemName: swimOK ? "figure.pool.swim" : "house.fill")
                    .font(.caption)
                    .foregroundStyle(swimOK ? AuraTheme.sageGreen : AuraTheme.warmGinger)
                Text(
                    swimOK
                    ? "当前气候适宜室外游泳，可放宽室外有氧限制"
                    : "当前气候或恢复阶段不宜下水，将自动切为居家温和导引"
                )
                .font(.caption)
                .foregroundStyle(AuraTheme.primaryText.opacity(0.85))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    Task {
                        isRefreshingWeather = true
                        defer { isRefreshingWeather = false }
                        if let summary = await onRefreshWeather() {
                            statusMessage = summary
                        } else {
                            statusMessage = "未获取到在线气象数据，可使用下方场景预设测试。"
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRefreshingWeather {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(isRefreshingWeather ? "获取中…" : "拉取定位天气")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AuraTheme.sageGreen, in: Capsule())
                }
                .disabled(isRefreshingWeather)

                Button {
                    dismiss()
                    onApplyWeatherToPlan()
                } label: {
                    Text("按天气重排今日")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AuraTheme.warmGinger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AuraTheme.warmGinger.opacity(0.14), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var solarTermSection: some View {
        let term = snapshot.resolvedSolarTerm

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("二十四节气顺时提示", systemImage: "leaf.fill")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)
                Spacer()
                Text(term.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AuraTheme.sageGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AuraTheme.sageGreen.opacity(0.13), in: Capsule())
            }

            Text(term.guidance)
                .font(.subheadline)
                .foregroundStyle(AuraTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var healthKitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("HealthKit 体征同步", systemImage: "heart.text.square.fill")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                Button {
                    Task {
                        isSyncingHealth = true
                        defer { isSyncingHealth = false }
                        statusMessage = await onSyncHealthKit()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isSyncingHealth {
                            ProgressView().controlSize(.mini).tint(AuraTheme.inkSlate)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isSyncingHealth ? "同步中" : "同步健康数据")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AuraTheme.inkSlate)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AuraTheme.inkSlate.opacity(0.13), in: Capsule())
                }
                .disabled(isSyncingHealth)
            }

            HStack(spacing: 10) {
                healthMetricTile(
                    title: "今日步数",
                    value: snapshot.healthStepCount.map { "\($0) 步" } ?? "未同步"
                )
                healthMetricTile(
                    title: "昨晚睡眠",
                    value: snapshot.healthSleepHours.map { String(format: "%.1f 小时", $0) } ?? "未同步"
                )
                healthMetricTile(
                    title: "最新体重",
                    value: (snapshot.healthLatestWeightKG ?? profile?.weightKG).map { String(format: "%.1f kg", $0) } ?? "--"
                )
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.sageGreen)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private func healthMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AuraTheme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTheme.primaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var presetSimulationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("气候场景快速验证")
                .font(.headline)
                .foregroundStyle(AuraTheme.primaryText)

            Text("切换不同城市气候后点击「按天气重排今日」，可直观验证低温/大风/高湿下运动与祛湿方案的动态联动。")
                .font(.caption)
                .foregroundStyle(AuraTheme.secondaryText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(presets) { preset in
                    Button {
                        snapshot.city = preset.city
                        snapshot.weatherTempC = preset.tempC
                        snapshot.weatherCondition = preset.condition
                        snapshot.weatherHumidity = preset.humidity
                        snapshot.weatherWindSpeedKmh = preset.windKmh
                        snapshot.weatherSource = "场景模拟"
                        HapticFeedback.impact(.light)
                        statusMessage = "已切换为 \(preset.city) \(Int(preset.tempC))°C \(preset.condition)（湿度 \(Int(preset.humidity))%）"
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(preset.city) · \(Int(preset.tempC))°C \(preset.condition)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AuraTheme.primaryText)
                            Text("湿度 \(Int(preset.humidity))% · 风速 \(Int(preset.windKmh))km/h")
                                .font(.caption2)
                                .foregroundStyle(AuraTheme.secondaryText)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AuraTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let snapshots = (try? container.mainContext.fetch(FetchDescriptor<DailyContextSnapshot>())) ?? []
    let profiles = (try? container.mainContext.fetch(FetchDescriptor<UserConstitutionProfile>())) ?? []

    return ContextEnvironmentSheet(
        snapshot: snapshots.first!,
        profile: profiles.first,
        onRefreshWeather: { "已更新深圳 24°C 晴" },
        onSyncHealthKit: { "已同步 HealthKit 数据" },
        onApplyWeatherToPlan: {}
    )
}
