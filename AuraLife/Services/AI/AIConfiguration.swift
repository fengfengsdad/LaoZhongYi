import Foundation

enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAICompatible = "openai"
    case anthropicClaude = "claude"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI / 兼容接口"
        case .anthropicClaude:
            return "Anthropic Claude"
        case .gemini:
            return "Google Gemini"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAICompatible:
            return "https://api.openai.com/v1"
        case .anthropicClaude:
            return "https://api.anthropic.com/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAICompatible:
            return "gpt-4o-mini"
        case .anthropicClaude:
            return "claude-sonnet-4-20250514"
        case .gemini:
            return "gemini-3.5-flash-lite"
        }
    }

    var keychainAccount: String {
        "api_key_\(rawValue)"
    }
}

struct AIConfiguration: Sendable {
    var provider: AIProvider
    var baseURL: String
    var model: String
    var apiKey: String
    var enableStreaming: Bool
    var enableProxy: Bool
    var proxyHost: String
    var proxyPort: String

    var hasValidKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resolvedProxyPort: UInt16? {
        guard let port = UInt16(proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
            return nil
        }
        return port
    }

    static func load() -> AIConfiguration {
        let defaults = UserDefaults.standard
        let providerRaw = defaults.string(forKey: Keys.provider) ?? AIProvider.openAICompatible.rawValue
        let provider = AIProvider(rawValue: providerRaw) ?? .openAICompatible
        let baseURL = defaults.string(forKey: Keys.baseURL(for: provider)) ?? provider.defaultBaseURL
        let model = defaults.string(forKey: Keys.model(for: provider)) ?? provider.defaultModel
        let enableStreaming = defaults.object(forKey: Keys.enableStreaming) as? Bool ?? true
        let enableProxy = defaults.object(forKey: Keys.enableProxy) as? Bool ?? false
        let proxyHost = defaults.string(forKey: Keys.proxyHost) ?? "127.0.0.1"
        let proxyPort = defaults.string(forKey: Keys.proxyPort) ?? "7890"
        let apiKey = KeychainHelper.read(account: provider.keychainAccount)

        return AIConfiguration(
            provider: provider,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            enableStreaming: enableStreaming,
            enableProxy: enableProxy,
            proxyHost: proxyHost,
            proxyPort: proxyPort
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(provider.rawValue, forKey: Keys.provider)
        defaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.baseURL(for: provider))
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.model(for: provider))
        defaults.set(enableStreaming, forKey: Keys.enableStreaming)
        defaults.set(enableProxy, forKey: Keys.enableProxy)
        defaults.set(proxyHost.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.proxyHost)
        defaults.set(proxyPort.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.proxyPort)
        KeychainHelper.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), account: provider.keychainAccount)
    }

    private enum Keys {
        static let provider = "auralife.ai.provider"
        static let enableStreaming = "auralife.ai.enableStreaming"
        static let enableProxy = "auralife.ai.enableProxy"
        static let proxyHost = "auralife.ai.proxyHost"
        static let proxyPort = "auralife.ai.proxyPort"
        static func baseURL(for provider: AIProvider) -> String { "auralife.ai.baseURL.\(provider.rawValue)" }
        static func model(for provider: AIProvider) -> String { "auralife.ai.model.\(provider.rawValue)" }
    }
}
