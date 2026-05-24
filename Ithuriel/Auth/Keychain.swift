import Foundation
import Security

enum Keychain {
    private static let service = "dev.ithuriel.agent"

    enum AccessMode {
        case silent
        case interactive
    }

    static func set(_ value: String, key: String) throws {
        if HackathonConfig.skipPermissionPrompts { return }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: "Keychain", code: Int(status)) }
    }

    static func get(_ key: String, mode: AccessMode = .interactive) -> String? {
        if HackathonConfig.skipPermissionPrompts { return nil }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if mode == .silent {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        if HackathonConfig.skipPermissionPrompts { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
