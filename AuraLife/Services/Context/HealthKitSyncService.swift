import Foundation
import HealthKit

struct HealthKitSnapshotData: Sendable {
    let stepsToday: Int?
    let sleepHoursLastNight: Double?
    let latestWeightKG: Double?
    let statusMessage: String
}

@MainActor
final class HealthKitSyncService {
    static let shared = HealthKitSyncService()

    private let healthStore = HKHealthStore()

    private init() {}

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func syncTodayMetrics() async -> HealthKitSnapshotData {
        guard isAvailable else {
            AILog.warning("HealthKit", "当前设备不支持 HealthKit")
            return HealthKitSnapshotData(
                stepsToday: nil,
                sleepHoursLastNight: nil,
                latestWeightKG: nil,
                statusMessage: "当前设备不支持 HealthKit"
            )
        }

        let stepType = HKQuantityType(.stepCount)
        let weightType = HKQuantityType(.bodyMass)
        let sleepType = HKCategoryType(.sleepAnalysis)
        let readTypes: Set<HKObjectType> = [stepType, weightType, sleepType]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            AILog.warning("HealthKit", "授权请求失败: \(error.localizedDescription)")
            return HealthKitSnapshotData(
                stepsToday: nil,
                sleepHoursLastNight: nil,
                latestWeightKG: nil,
                statusMessage: "HealthKit 未授权：\(error.localizedDescription)"
            )
        }

        async let steps = fetchTodaySteps(type: stepType)
        async let sleep = fetchLastNightSleepHours(type: sleepType)
        async let weight = fetchLatestWeightKG(type: weightType)

        let (resolvedSteps, resolvedSleep, resolvedWeight) = await (steps, sleep, weight)

        var parts: [String] = []
        if let resolvedSteps { parts.append("步数 \(resolvedSteps)") }
        if let resolvedSleep { parts.append(String(format: "睡眠 %.1fh", resolvedSleep)) }
        if let resolvedWeight { parts.append(String(format: "体重 %.1fkg", resolvedWeight)) }

        let summary = parts.isEmpty
            ? "已连接 HealthKit（暂无今日步数/睡眠记录）"
            : "已同步 HealthKit：\(parts.joined(separator: " · "))"

        AILog.info("HealthKit", summary)
        return HealthKitSnapshotData(
            stepsToday: resolvedSteps,
            sleepHoursLastNight: resolvedSleep,
            latestWeightKG: resolvedWeight,
            statusMessage: summary
        )
    }

    private func fetchTodaySteps(type: HKQuantityType) async -> Int? {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: .now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let count = statistics?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: count.map { Int($0.rounded()) })
            }
            healthStore.execute(query)
        }
    }

    private func fetchLastNightSleepHours(type: HKCategoryType) async -> Double? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let windowStart = calendar.date(byAdding: .hour, value: -12, to: startOfToday) ?? startOfToday
        let windowEnd = calendar.date(byAdding: .hour, value: 12, to: startOfToday) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]

                let totalSeconds = categorySamples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                guard totalSeconds > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestWeightKG(type: HKQuantityType) async -> Double? {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, _ in
                guard let quantitySample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let kg = quantitySample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg > 0 ? kg : nil)
            }
            healthStore.execute(query)
        }
    }
}
