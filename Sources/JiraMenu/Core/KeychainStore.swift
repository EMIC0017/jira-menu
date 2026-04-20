import Foundation
import Security

struct KeychainStore {
    let service: String

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    init(service: String = "dev.ericmorin.jiramenu") {
        self.service = service
    }

    func save(_ credentials: Credentials) throws {
        let payload: [String: String] = [
            "siteURL": credentials.siteURL.absoluteString,
            "email": credentials.email,
            "apiToken": credentials.apiToken,
        ]
        let data = try JSONEncoder().encode(payload)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func load() throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        let payload = try JSONDecoder().decode([String: String].self, from: data)
        guard
            let urlString = payload["siteURL"],
            let url = URL(string: urlString),
            let email = payload["email"],
            let token = payload["apiToken"]
        else { return nil }
        return Credentials(siteURL: url, email: email, apiToken: token)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
