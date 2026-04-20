import SwiftUI

/// First-run form for entering Jira Cloud site + email + API token, and the
/// "change credentials" form for later edits. Saves directly to the Keychain.
struct SettingsView: View {
    let store: KeychainStore
    let onSaved: (Credentials) -> Void

    @State private var siteURL: String = ""
    @State private var email: String = ""
    @State private var apiToken: String = ""
    @State private var errorMessage: String?

    init(store: KeychainStore = KeychainStore(), onSaved: @escaping (Credentials) -> Void) {
        self.store = store
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to Jira")
                .font(.title2).bold()

            HStack(spacing: 4) {
                Text("Need a token?")
                Link("Create one on Atlassian →",
                     destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
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

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            HStack {
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            if let existing = try? store.load() {
                siteURL = existing.siteURL.absoluteString
                email = existing.email
                apiToken = existing.apiToken
            }
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
            try store.save(creds)
            errorMessage = nil
            onSaved(creds)
        } catch {
            errorMessage = "Could not save to Keychain: \(error.localizedDescription)"
        }
    }
}
