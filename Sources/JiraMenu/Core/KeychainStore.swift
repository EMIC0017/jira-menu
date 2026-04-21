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

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case accessControl(Error?)
        case userCancelled

        /// Surface the actual OSStatus + its system-provided description so
        /// failures are diagnosable instead of showing Swift's default
        /// "Domain error 0" placeholder. Without this conformance Keychain
        /// bugs are effectively opaque.
        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let name = Self.osStatusName(status)
                let msg  = (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error"
                return "\(msg) (\(name), OSStatus \(status))"
            case .accessControl(let inner):
                return "Access-control creation failed: \(inner?.localizedDescription ?? "unknown")"
            case .userCancelled:
                return "User cancelled Keychain authentication."
            }
        }

        /// A short mnemonic for the most common Security framework statuses.
        /// Helps pattern-match an error code at a glance without needing
        /// to look up its hex representation.
        private static func osStatusName(_ status: OSStatus) -> String {
            switch status {
            case errSecSuccess:             return "errSecSuccess"
            case errSecDuplicateItem:       return "errSecDuplicateItem"
            case errSecItemNotFound:        return "errSecItemNotFound"
            case errSecAuthFailed:          return "errSecAuthFailed"
            case errSecUserCanceled:        return "errSecUserCanceled"
            case errSecInteractionNotAllowed: return "errSecInteractionNotAllowed"
            case errSecMissingEntitlement:  return "errSecMissingEntitlement"
            case errSecDecode:              return "errSecDecode"
            case errSecParam:               return "errSecParam"
            default:                        return "unknown"
            }
        }
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

        // Protection-specific attributes — either an `Accessible` flag (for
        // standard items) or a SecAccessControl (for biometric items).
        var protectionAttrs: [String: Any] = [:]
        switch protection {
        case .standard:
            // "This device only" prevents iCloud Keychain / Time Machine migration
            // of what is effectively a per-device access token.
            protectionAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
            protectionAttrs[kSecAttrAccessControl as String] = ac
        }

        // First try a plain Add. If an item already exists for this service
        // (duplicate), fall through to Update. The naive "delete-then-add"
        // pattern fails silently on biometric items because deletion of an
        // ACL-protected item without an auth context returns errSecAuthFailed,
        // leaving the stale item in place and making the subsequent Add
        // collide. Try-Add-then-Update sidesteps that.
        var addAttrs = baseQuery
        addAttrs[kSecValueData as String] = data
        for (k, v) in protectionAttrs { addAttrs[k] = v }

        let addStatus = SecItemAdd(addAttrs as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        guard addStatus == errSecDuplicateItem else {
            throw KeychainError.unexpectedStatus(addStatus)
        }

        // Duplicate → update. Update the data AND the protection attrs so
        // toggling the biometric flag takes effect on existing items.
        var updateAttrs: [String: Any] = [kSecValueData as String: data]
        for (k, v) in protectionAttrs { updateAttrs[k] = v }
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary,
                                          updateAttrs as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
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
