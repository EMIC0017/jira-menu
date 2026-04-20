import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "launch at login" toggle.
/// Reads status fresh every time so a user flipping the switch from System
/// Settings → General → Login Items is reflected without a relaunch.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var errorMessage: String?

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success, false if the attempt failed (errorMessage populated).
    @discardableResult
    func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            refresh()
            return false
        }
    }
}
