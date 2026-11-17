import Foundation
import Observation
import OSLog

enum AILogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct AILogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: AILogLevel
    let category: String
    let message: String

    var formattedLine: String {
        let time = Self.timeFormatter.string(from: timestamp)
        return "[\(time)][\(level.rawValue)][\(category)] \(message)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

@MainActor
@Observable
final class AILogStore {
    static let shared = AILogStore()

    private(set) var entries: [AILogEntry] = []
    private let maxEntries = 300

    private init() {}

    func append(_ entry: AILogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func exportText() -> String {
        entries.map(\.formattedLine).joined(separator: "\n")
    }
}

enum AILog {
    private static let osLogger = Logger(subsystem: "com.auralife.app", category: "AI")

    static func debug(_ category: String, _ message: String) {
        log(.debug, category: category, message)
    }

    static func info(_ category: String, _ message: String) {
        log(.info, category: category, message)
    }

    static func warning(_ category: String, _ message: String) {
        log(.warning, category: category, message)
    }

    static func error(_ category: String, _ message: String) {
        log(.error, category: category, message)
    }

    static func maskSecret(_ secret: String) -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else {
            return trimmed.isEmpty ? "<empty>" : "****(\(trimmed.count) chars)"
        }
        return "\(trimmed.prefix(4))****\(trimmed.suffix(4)) (len=\(trimmed.count))"
    }

    private static func log(_ level: AILogLevel, category: String, _ message: String) {
        let entry = AILogEntry(timestamp: .now, level: level, category: category, message: message)
        let formatted = entry.formattedLine

        // 1. 输出到 Xcode 标准输出，方便在控制台直接检索
        print("[AuraLife]\(formatted)")

        // 2. 输出到系统 os.Logger（Console.app / Xcode Structured Console）
        switch level {
        case .debug:
            osLogger.debug("\(formatted, privacy: .public)")
        case .info:
            osLogger.info("\(formatted, privacy: .public)")
        case .warning:
            osLogger.warning("\(formatted, privacy: .public)")
        case .error:
            osLogger.error("\(formatted, privacy: .public)")
        }

        // 3. 同步写入 App 内实时诊断日志面板
        Task { @MainActor in
            AILogStore.shared.append(entry)
        }
    }
}
