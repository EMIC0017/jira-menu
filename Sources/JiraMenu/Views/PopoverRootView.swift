import SwiftUI
import AppKit

/// The popover's root view. Shows SettingsView until credentials exist,
/// then shows the search field + live result list. Clicking a row opens
/// the issue in the user's default browser.
struct PopoverRootView: View {
    @StateObject private var vm: SearchViewModel
    @State private var credentials: Credentials?
    @State private var showSettings = false
    private let store: KeychainStore

    init(store: KeychainStore = KeychainStore()) {
        self.store = store
        let initial = try? store.load()
        _credentials = State(initialValue: initial)
        let client = initial.map { JiraClient(credentials: $0) }
        _vm = StateObject(wrappedValue: SearchViewModel { input in
            guard let client else { return [] }
            return try await client.search(input)
        })
    }

    var body: some View {
        Group {
            if credentials == nil || showSettings {
                SettingsView(store: store) { creds in
                    credentials = creds
                    showSettings = false
                }
            } else {
                searchBody
            }
        }
        .frame(width: 460)
    }

    private var searchBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search Jira…", text: $vm.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                if vm.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Change credentials")
            }
            .padding(12)

            Divider()

            if let err = vm.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(10)
            } else if vm.results.isEmpty {
                Text(vm.query.isEmpty ? "Type to search" : "No results")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.results) { issue in
                            Button {
                                open(issue: issue)
                            } label: {
                                ResultRowView(issue: issue)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
    }

    private func open(issue: Issue) {
        guard let creds = credentials else { return }
        let url = creds.siteURL.appendingPathComponent("browse/\(issue.key)")
        NSWorkspace.shared.open(url)
    }
}
