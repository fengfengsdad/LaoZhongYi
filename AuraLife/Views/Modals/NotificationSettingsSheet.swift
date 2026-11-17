import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let snapshots: [DailyContextSnapshot]
    let onPreferencesChanged: () async -> Int

    @State private var prefs = NotificationPreferences.load()
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var scheduledPreviews: [ScheduledReminderPreview] = []
    @State private var feedbackMessage: String?

    private let leadOptions = [0, 10, 15]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusHeaderCard
                    preferencesCard
                    upcomingScheduleCard
                }
                .padding(16)
            }
            .background(AuraTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle("顺时温和提醒")
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
            .task {
                await refreshState()
            }
        }
    }

    private var statusHeaderCard: some View {
        let isAuthorized = authStatus == .authorized || authStatus == .provisional || authStatus == .ephemeral

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: prefs.isEnabled && isAuthorized ? "bell.badge.fill" : "bell.slash")
                    .font(.title2)
                    .foregroundStyle(prefs.isEnabled && isAuthorized ? AuraTheme.sageGreen : AuraTheme.warmGinger)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle(isAuthorized: isAuthorized))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AuraTheme.primaryText)

                    Text("仅针对未完成的关键顺时节点推送轻柔提示，完成后自动撤销，避免无效打扰。")
                        .font(.caption)
                        .foregroundStyle(AuraTheme.secondaryText)
                }
            }

            if authStatus == .denied {
                Button("前往系统设置开启通知权限") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AuraTheme.warmGinger)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("开启关键时段温和提醒", isOn: $prefs.isEnabled)
                .font(.subheadline.weight(.semibold))
                .tint(AuraTheme.sageGreen)
                .onChange(of: prefs.isEnabled) { _, newValue in
                    Task {
                        if newValue {
                            let granted = await GentleNotificationService.shared.requestAuthorization()
                            if !granted {
                                prefs.isEnabled = false
                                feedbackMessage = "系统通知权限未授予，请在系统设置中允许通知。"
                            }
                        }
                        prefs.save()
                        let count = await onPreferencesChanged()
                        await refreshState()
                        if prefs.isEnabled {
                            feedbackMessage = "已同步 \(count) 条即将到来的顺时提醒"
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("提醒提前量")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)

                Picker("提醒提前量", selection: $prefs.leadMinutes) {
                    ForEach(leadOptions, id: \.self) { mins in
                        Text(mins == 0 ? "准点提醒" : "提前 \(mins) 分钟").tag(mins)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.leadMinutes) { _, _ in
                    prefs.save()
                    Task {
                        let count = await onPreferencesChanged()
                        await refreshState()
                        if prefs.isEnabled {
                            feedbackMessage = "已按新提前量更新 \(count) 条提醒"
                        }
                    }
                }
            }

            Button {
                Task {
                    let firstUncompleted = snapshots.first?.sortedCards.first(where: { !$0.isCompleted })
                    let ok = await GentleNotificationService.shared.sendTestGentleNotification(for: firstUncompleted)
                    feedbackMessage = ok
                        ? "已调度测试提醒，3 秒后将在顶部弹出（可下拉体验「标记已完成」快捷操作）"
                        : "未能发送测试通知，请确认系统通知权限已开启。"
                    if ok {
                        HapticFeedback.notify(.success)
                    }
                }
            } label: {
                Label("发送测试提醒（3 秒后弹出）", systemImage: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AuraTheme.warmGinger, in: Capsule())
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundStyle(AuraTheme.sageGreen)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private var upcomingScheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("待触发顺时队列")
                    .font(.headline)
                    .foregroundStyle(AuraTheme.primaryText)

                Spacer()

                Text("\(scheduledPreviews.count) 条")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AuraTheme.secondaryText)
            }

            if scheduledPreviews.isEmpty {
                Text("今日剩余时段暂无待提醒的未完成卡片（或需点击「生成3日计划」排入明日提醒）。")
                    .font(.caption)
                    .foregroundStyle(AuraTheme.secondaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(scheduledPreviews.prefix(8)) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.category.systemImage)
                                .font(.caption)
                                .foregroundStyle(AuraTheme.accent(for: item.category))
                                .frame(width: 26, height: 26)
                                .background(AuraTheme.accent(for: item.category).opacity(0.14), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AuraTheme.primaryText)
                                    Spacer()
                                    Text(item.fireDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(AuraTheme.sageGreen)
                                }

                                Text(item.body)
                                    .font(.caption2)
                                    .foregroundStyle(AuraTheme.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                        .padding(10)
                        .background(AuraTheme.subtleSurface.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(AuraTheme.cardSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AuraTheme.hairline, lineWidth: 1))
    }

    private func statusTitle(isAuthorized: Bool) -> String {
        if !isAuthorized {
            return authStatus == .denied ? "系统通知已关闭" : "尚未开启系统通知授权"
        }
        return prefs.isEnabled ? "温和提醒已启用" : "已暂停顺时提醒"
    }

    private func refreshState() async {
        authStatus = await GentleNotificationService.shared.authorizationStatus()
        scheduledPreviews = GentleNotificationService.shared.buildPreviewSchedule(
            from: snapshots,
            preferences: prefs
        )
    }
}

#Preview {
    let container = PreviewSupport.makeContainer()
    let snapshots = (try? container.mainContext.fetch(FetchDescriptor<DailyContextSnapshot>())) ?? []

    return NotificationSettingsSheet(
        snapshots: snapshots,
        onPreferencesChanged: { 0 }
    )
}
