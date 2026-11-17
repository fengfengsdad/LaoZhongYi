import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.auralife.app.ai"

    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let deleteStatus = SecItemDelete(query as CFDictionary)

        guard !value.isEmpty else {
            AILog.info("Keychain", "已清空 \(account) 的密钥 (deleteStatus=\(deleteStatus))")
            return
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            AILog.error("Keychain", "保存 \(account) 失败，OSStatus=\(addStatus)")
        } else {
            AILog.info("Keychain", "已保存 \(account): \(AILog.maskSecret(value))")
        }
    }

    static func read(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                AILog.warning("Keychain", "读取 \(account) 返回 OSStatus=\(status)")
            }
            return ""
        }
        return value
    }
}
