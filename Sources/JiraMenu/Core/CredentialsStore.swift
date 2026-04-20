import Foundation
import SwiftUI

/// Owns the lifecycle of Jira credentials: loads from the Keychain, holds
/// an in-memory copy, and exposes the "require Touch ID" preference.
///
/// When `requireBiometrics` is on, credentials are NOT auto-loaded at
/// startup — the UI presents a locked state and calls `unlock()` which
/// triggers the Touch ID prompt. The decrypted credentials then live in
/// `credentials` for the rest of the process so subsequent reads are silent.
@MainActor
final class CredentialsStore: ObservableObject {
    @Published private(set) var credentials: Credentials?
    @Published private(set) var isLocked: Bool = false
    @Published private(set) var unlockError: String?
    @Published var requireBiometrics: Bool {
        didSet {
            UserDefaults.standard.set(requireBiometrics, forKey: Self.biometricsKey)
        }
    }

    private static let biometricsKey = "jiramenu.requireBiometrics"
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        self.requireBiometrics = UserDefaults.standard.bool(forKey: Self.biometricsKey)
        if requireBiometrics {
            // Wait for explicit unlock so we don't fire a Touch ID prompt
            // before the user has even opened the popover.
            self.isLocked = true
        } else {
            self.credentials = try? keychain.load()
        }
    }

    /// Triggers the biometric prompt (on biometric items) and caches the
    /// result. Safe to call repeatedly — a successful unlock is idempotent.
    @discardableResult
    func unlock(prompt: String = "Unlock your Jira credentials") async -> Bool {
        do {
            let creds = try keychain.load(prompt: prompt)
            self.credentials = creds
            self.isLocked = false
            self.unlockError = nil
            return creds != nil
        } catch KeychainStore.KeychainError.userCancelled {
            self.unlockError = nil  // user dismissed; not an error worth shouting about
            return false
        } catch {
            self.unlockError = error.localizedDescription
            return false
        }
    }

    /// Persists new credentials with the requested protection level. Also
    /// updates the cached `requireBiometrics` preference so the next launch
    /// knows whether to show the locked state.
    func save(_ creds: Credentials, requireBiometrics: Bool) throws {
        try keychain.save(creds, protection: requireBiometrics ? .biometric : .standard)
        self.requireBiometrics = requireBiometrics
        self.credentials = creds
        self.isLocked = false
        self.unlockError = nil
    }
}
