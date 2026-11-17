import Foundation
import UserNotifications

extension Notification.Name {
    static let auraLifeCompleteCardFromNotification = Notification.Name("auralife.notification.completeCard")
}

struct NotificationPreferences: Sendable {
    var isEnabled: Bool
    var leadMinutes: Int

    static func load() -> NotificationPreferences {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? false
        let leadMinutes = defaults.object(forKey: Keys.leadMinutes) as? Int ?? 10
        return NotificationPreferences(isEnabled: isEnabled, leadMinutes: leadMinutes)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        defaults.set(leadMinutes, forKey: Keys.leadMinutes)
    }

    private enum Keys {
        static let isEnabled = "auralife.notifications.enabled"
        static let leadMinutes = "auralife.notifications.leadMinutes"
    }
}

struct ScheduledReminderPreview: Identifiable, Sendable {
    let id: String
    let cardID: UUID
    let title: String
    let body: String
    let fireDate: Date
    let category: ActionCategory
}

enum TimeSlotParser {
    /// 将自然中文时段（如 "上午 09:30"、"下午 16:30-17:30"、"睡前"）解析为对应日期的提醒触发时间
    static func targetDate(for timeSlot: String, on day: Date, leadMinutes: Int) -> Date? {
        let calendar = Calendar.current
        let baseComponents = calendar.dateComponents([.year, .month, .day], from: day)

        let (hour, minute) = extractHourMinute(from: timeSlot)
        var targetComponents = baseComponents
        targetComponents.hour = hour
        targetComponents.minute = minute
        targetComponents.second = 0

        guard let exactDate = calendar.date(from: targetComponents) else {
            return nil
        }
        return calendar.date(byAdding: .minute, value: -max(0, leadMinutes), to: exactDate)
    }

    static func extractHourMinute(from timeSlot: String) -> (hour: Int, minute: Int) {
        let pattern = #"(\d{1,2})[:：](\d{2})"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: timeSlot, range: NSRange(timeSlot.startIndex..., in: timeSlot)),
           match.numberOfRanges >= 3,
           let hourRange = Range(match.range(at: 1), in: timeSlot),
           let minuteRange = Range(match.range(at: 2), in: timeSlot),
           var hour = Int(timeSlot[hourRange]),
           let minute = Int(timeSlot[minuteRange]) {
            if (timeSlot.contains("下午") || timeSlot.contains("晚上") || timeSlot.contains("傍晚")) && hour < 12 {
                hour += 12
            } else if timeSlot.contains("中午") && hour >= 1 && hour <= 10 {
                hour += 12
            }
            return (min(23, max(0, hour)), min(59, max(0, minute)))
        }

        if timeSlot.contains("晨") || timeSlot.contains("早") {
            return (8, 0)
        }
        if timeSlot.contains("上午") {
            return (9, 30)
        }
        if timeSlot.contains("中午") || timeSlot.contains("午") {
            return (12, 0)
        }
        if timeSlot.contains("下午") {
            return (16, 30)
        }
        if timeSlot.contains("傍晚") {
            return (18, 0)
        }
        if timeSlot.contains("睡前") || timeSlot.contains("晚") {
            return (21, 30)
        }
        return (10, 0)
    }

    /// 判断某卡片是否处于当前或即将到来的执行窗口（仅用于今日时间轴柔和视觉高亮）
    static func isCurrentOrNextWindow(
        timeSlot: String,
        on day: Date,
        now: Date = .now
    ) -> Bool {
        let calendar = Calendar.current
        guard calendar.isDate(day, inSameDayAs: now) else { return false }
        let (hour, minute) = extractHourMinute(from: timeSlot)
        guard let slotDate = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        ) else {
            return false
        }
        let deltaMinutes = slotDate.timeIntervalSince(now) / 60.0
        return deltaMinutes >= -75 && deltaMinutes <= 90
    }
}

@MainActor
final class GentleNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = GentleNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "auralife.card."
    private let categoryIdentifier = "AURALIFE_GENTLE_ACTION"
    private let completeActionIdentifier = "AURALIFE_MARK_COMPLETE"
    private let snoozeActionIdentifier = "AURALIFE_SNOOZE_15M"

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self

        let completeAction = UNNotificationAction(
            identifier: completeActionIdentifier,
            title: "标记已完成",
            options: []
        )
        let snoozeAction = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "15分钟后再提醒",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [completeAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            AILog.info("Notify", "系统通知授权结果: \(granted)")
            return granted
        } catch {
            AILog.error("Notify", "通知授权请求失败: \(error.localizedDescription)")
            return false
        }
    }

    func buildPreviewSchedule(
        from snapshots: [DailyContextSnapshot],
        preferences: NotificationPreferences = .load()
    ) -> [ScheduledReminderPreview] {
        let now = Date.now
        var items: [ScheduledReminderPreview] = []

        for snapshot in snapshots {
            for card in snapshot.sortedCards where !card.isCompleted {
                guard let fireDate = TimeSlotParser.targetDate(
                    for: card.timeSlot,
                    on: snapshot.date,
                    leadMinutes: preferences.leadMinutes
                ) else {
                    continue
                }

                guard fireDate > now else { continue }

                let identifier = "\(identifierPrefix)\(card.id.uuidString)"
                items.append(
                    ScheduledReminderPreview(
                        id: identifier,
                        cardID: card.id,
                        title: "顺时轻提醒 · \(card.title)",
                        body: "\(card.reasoning)（\(card.timeSlot)）",
                        fireDate: fireDate,
                        category: card.category
                    )
                )
            }
        }

        return items.sorted { $0.fireDate < $1.fireDate }
    }

    @discardableResult
    func syncNotifications(for snapshots: [DailyContextSnapshot]) async -> Int {
        let prefs = NotificationPreferences.load()
        await clearAuraLifePendingNotifications()

        guard prefs.isEnabled else {
            AILog.info("Notify", "温和提醒开关未开启，已清空待发送提醒")
            return 0
        }

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            AILog.warning("Notify", "系统通知未授权，跳过调度")
            return 0
        }

        let previews = buildPreviewSchedule(from: snapshots, preferences: prefs)
        let calendar = Calendar.current
        var scheduledCount = 0

        for item in previews.prefix(24) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = categoryIdentifier
            content.userInfo = ["cardID": item.cardID.uuidString]

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)

            do {
                try await center.add(request)
                scheduledCount += 1
            } catch {
                AILog.error("Notify", "添加通知失败 \(item.title): \(error.localizedDescription)")
            }
        }

        AILog.info("Notify", "已同步 \(scheduledCount) 条温和顺时提醒")
        return scheduledCount
    }

    func sendTestGentleNotification(for card: ActionCard?) async -> Bool {
        var status = await authorizationStatus()
        if status == .notDetermined {
            let granted = await requestAuthorization()
            if !granted { return false }
            status = await authorizationStatus()
        }

        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "顺时轻提醒 · \(card?.title ?? "生姜陈皮温胃水")"
        content.body = card?.reasoning ?? "痰湿兼轻微气虚，此时适合小口温饮助脾胃运化。"
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        if let cardID = card?.id {
            content.userInfo = ["cardID": cardID.uuidString]
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)test.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            AILog.info("Notify", "已发送 3 秒后触发的测试通知")
            return true
        } catch {
            AILog.error("Notify", "测试通知发送失败: \(error.localizedDescription)")
            return false
        }
    }

    private func clearAuraLifePendingNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let cardIDString = userInfo["cardID"] as? String

        if response.actionIdentifier == completeActionIdentifier,
           let cardIDString,
           let uuid = UUID(uuidString: cardIDString) {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .auraLifeCompleteCardFromNotification,
                    object: nil,
                    userInfo: ["cardID": uuid]
                )
            }
        } else if response.actionIdentifier == snoozeActionIdentifier {
            let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent
            if let content {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
                let snoozeRequest = UNNotificationRequest(
                    identifier: "auralife.card.snooze.\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(snoozeRequest)
            }
        }
    }
}
