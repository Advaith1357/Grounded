//
//  KeychainStore.swift
//  Grounded
//
//  Minimal Keychain read/write — no third-party packages, just the Security
//  framework. Holds the Gemini API key (written by the Kernel sheet's
//  SecureField; GeminiService reads it first and falls back to the compiled
//  `Secrets.geminiAPIKey` placeholder) and the friends-server bearer token.
//

import Foundation
import Security

enum KeychainStore {

    // MARK: - Gemini API key

    static func saveGeminiAPIKey(_ key: String) {
        save(key, service: "com.grounded.app.gemini", account: "gemini-api-key")
    }

    static func loadGeminiAPIKey() -> String? {
        load(service: "com.grounded.app.gemini", account: "gemini-api-key")
    }

    // MARK: - Friends server token

    static func saveFriendsToken(_ token: String) {
        save(token, service: "com.grounded.app.friends", account: "friends-token")
    }

    static func loadFriendsToken() -> String? {
        load(service: "com.grounded.app.friends", account: "friends-token")
    }

    static func deleteFriendsToken() {
        save("", service: "com.grounded.app.friends", account: "friends-token")
    }

    // MARK: - Generic

    /// Saving an empty string deletes the item.
    private static func save(_ value: String, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        guard !value.isEmpty else { return }

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
