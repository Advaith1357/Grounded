//
//  KeychainStore.swift
//  Grounded
//
//  Minimal Keychain read/write for the Gemini API key — no third-party
//  packages, just the Security framework. The Kernel settings sheet's
//  SecureField writes here; GeminiService reads from here first (falling back
//  to the compiled `Secrets.geminiAPIKey` placeholder — see its doc comment —
//  so the existing dev setup keeps working until you paste a key in Settings).
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.grounded.app.gemini"
    private static let account = "gemini-api-key"

    static func saveGeminiAPIKey(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        guard !key.isEmpty else { return }

        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadGeminiAPIKey() -> String? {
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
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }
}
