import Foundation
import Security
import LocalAuthentication

struct KeychainStore {
    let service: String

    /// How the Keychain item is protected at rest.
    enum Protection {
        /// Standard Keychain access — readable by this app while the user
        /// is logged in. No biometric prompt on read.
        case standard
        /// Requires user-presence (Touch ID or device password) on every
        /// read. Ties to "you right now," not to the app's code signature —
        /// so rebuilds survive without re-ACL prompts.
        case biometric
    }

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
        case accessControl(Error?)
        case userCancelled
    }

    init(service: String = "dev.ericmorin.jiramenu") {
        self.service = service
    }

    func save(_ credentials: Credentials, protection: Protection = .standard) throws {
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

        switch protection {
        case .standard:
            // "This device only" prevents iCloud Keychain / Time Machine migration
            // of what is effectively a per-device access token.
            attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .biometric:
            var cfError: Unmanaged<CFError>?
            guard let ac = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.userPresence],
                &cfError
            ) else {
                throw KeychainError.accessControl(cfError?.takeRetainedValue())
            }
            attrs[kSecAttrAccessControl as String] = ac
        }

        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Reads the stored credentials. If `prompt` is supplied and the item
    /// was saved with `.biometric` protection, the Touch ID / password
    /// sheet's subtitle is set to `prompt`. On non-biometric items the
    /// context is harmlessly ignored.
    func load(prompt: String? = nil) throws -> Credentials? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let prompt {
            let context = LAContext()
            context.localizedReason = prompt
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw KeychainError.userCancelled
        }
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

    /// Whether this machine can satisfy a biometric prompt. Used by the UI
    /// to hide/disable the "Require Touch ID" toggle on Macs without a
    /// fingerprint sensor (so the user isn't surprised by a password fallback).
    static var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}
