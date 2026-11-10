import Foundation
import Security

/// A Healthchecks project; API keys are per project, so watching several takes one key each.
nonisolated struct Project: Codable, Identifiable, Sendable {
    var id = UUID()
    let name: String
    let apiKey: String

    private struct KeychainFailure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? }
    }

    /// The whole list is one Keychain item, since it carries the API keys.
    private static var keychainItem: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.damirkairov.HealthchecksX",
            kSecAttrAccount as String: "projects",
        ]
    }

    static func saved() -> [Project] {
        var query = keychainItem
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([Project].self, from: data)) ?? []
    }

    static func save(_ projects: [Project]) throws {
        let data = try JSONEncoder().encode(projects)
        var status = SecItemUpdate(keychainItem as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(keychainItem.merging([kSecValueData as String: data]) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
    }
}
