import SwiftUI

/// First-run form for entering Jira Cloud credentials, and the
/// "change credentials" form for later edits. Reads/writes via
/// CredentialsStore so we don't thrash the Keychain.
struct SettingsView: View {
    let store: CredentialsStore
    let canCancel: Bool
    let onDone: () -> Void

    @State private var siteURL: String = ""
    @State private var email: String = ""
    @State private var apiToken: String = ""
    @State private var errorMessage: String?
    @State private var requireBiometrics: Bool = false
    @StateObject private var launch = LaunchAtLogin()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to Jira")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Need a token?")
                    Link("Open Atlassian tokens page →",
                         destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                }
                Text("Click \"Create API token\" (not the one with scopes).")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Form {
                TextField("Site URL", text: $siteURL, prompt: Text("https://acme.atlassian.net"))
                    .textFieldStyle(.roundedBorder)
                TextField("Email", text: $email, prompt: Text("you@company.com"))
                    .textFieldStyle(.roundedBorder)
                SecureField("API Token", text: $apiToken, prompt: Text("paste token"))
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            Toggle(isOn: Binding(
                get: { launch.isEnabled },
                set: { launch.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Start JiraMenu automatically when you log in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let launchErr = launch.errorMessage {
                Text(launchErr)
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }

            Toggle(isOn: $requireBiometrics) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require Touch ID to unlock credentials")
                    Text(KeychainStore.biometricsAvailable
                         ? "Prompts once per app launch. Applies next time credentials are saved."
                         : "This Mac has no biometric sensor — a password prompt will be used instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            HStack {
                if canCancel {
                    Button("Back", action: onDone)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let existing = store.credentials {
                siteURL = existing.siteURL.absoluteString
                email = existing.email
                apiToken = existing.apiToken
            }
            requireBiometrics = store.requireBiometrics
            launch.refresh()
        }
    }

    private var canSave: Bool {
        URL(string: siteURL.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard let url = URL(string: siteURL.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Site URL is not valid"
            return
        }
        let creds = Credentials(
            siteURL: url,
            email: email.trimmingCharacters(in: .whitespaces),
            apiToken: apiToken.trimmingCharacters(in: .whitespaces)
        )
        do {
            try store.save(creds, requireBiometrics: requireBiometrics)
            errorMessage = nil
            onDone()
        } catch {
            errorMessage = "Could not save to Keychain: \(error.localizedDescription)"
        }
    }
}
