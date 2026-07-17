//
//  KeychainStore.swift
//  PrismMusic
//
//  Thin wrapper over the Security framework for storing sensitive strings
//  (currently just the Yandex token). Synchronous on purpose — the values
//  are tiny so the convenience of `let token = KeychainStore.get(...)`
//  outweighs the cost.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.prism.music"

    private static var accessGroup: String? {
        // Return nil to avoid SecItemAdd/SecItemCopyMatching error -34018 on simulators
        // and environments without explicit shared provisioning profiles.
        return nil
    }

    private static var appIdentifierPrefix: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "bundleSeedID",
            kSecAttrService as String: "bundleSeedID",
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "bundleSeedID",
                kSecAttrService as String: "bundleSeedID",
                kSecValueData as String: "dummy".data(using: .utf8)!
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        if status == errSecSuccess,
           let dict = result as? [String: Any],
           let accessGroup = dict[kSecAttrAccessGroup as String] as? String {
            let components = accessGroup.components(separatedBy: ".")
            if !components.isEmpty {
                return components[0]
            }
        }
        return nil
    }

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup = self.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        // Delete any existing item first so we don't have to choose between Add and Update.
        SecItemDelete(query as CFDictionary)

        if value.isEmpty {
            return  // empty value == "clear the slot"
        }
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup = self.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
