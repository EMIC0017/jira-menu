import SwiftUI
import AppKit

/// The popover's root view. Reads all state from app-level environment
/// objects so closing and reopening the popover doesn't tear down the
/// view model, credentials, or caches. Settings and Filter are in-popover
/// subviews (not separate windows) so the popover keeps focus.
struct PopoverRootView: View {
    enum Mode { case search, settings, filter }

    @EnvironmentObject private var credentialsStore: CredentialsStore
    @EnvironmentObject private var filterStore: ProjectFilterStore
    @EnvironmentObject private var projectsStore: ProjectsStore
    @EnvironmentObject private var vm: SearchViewModel

    @State private var mode: Mode = .search
    @State private var assignedExpanded = true
    @State private var watchingExpanded = false
    @State private var openExpanded = true
    @State private var closedExpanded = false

    var body: some View {
        Group {
            if credentialsStore.isLocked {
                lockedBody
            } else if credentialsStore.credentials == nil {
                SettingsView(store: credentialsStore, canCancel: false, onDone: {})
            } else {
                switch mode {
                case .search:
                    searchBody
                case .settings:
                    SettingsView(store: credentialsStore, canCancel: true, onDone: { mode = .search })
                case .filter:
                    FilterPanel(onDone: { mode = .search })
                }
            }
        }
        .frame(width: 520, height: 640)
        .onReceive(filterStore.$selected) { keys in
            vm.projectKeys = Array(keys).sorted()
            vm.filterChanged()
        }
    }

    /// First screen the user sees when "Require Touch ID" is on. We wait for
    /// them to tap Unlock before calling the Keychain — that way the Touch ID
    /// sheet only appears in response to an explicit user action, never as a
    /// surprise when the popover opens.
    private var lockedBody: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("JiraMenu is locked")
                .font(.headline)
            Text("Use Touch ID to unlock your Jira credentials.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let err = credentialsStore.unlockError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Button("Unlock") {
                Task { await credentialsStore.unlock() }
            }
            .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .padding(24)
        .task {
            // Auto-trigger the prompt once on first open — users who turned on
            // Touch ID did so specifically to avoid an extra click. Re-opens
            // after a failure fall back to the explicit button above.
            if credentialsStore.unlockError == nil {
                await credentialsStore.unlock()
            }
        }
    }

    private var searchBody: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            content
        }
        .task {
            if vm.assigned.isEmpty { await vm.loadAssigned() }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Jira…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
            if vm.isLoading {
                ProgressView().controlSize(.small)
            }
            Button { mode = .filter } label: {
                Image(systemName: filterStore.selected.isEmpty
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
            }
            .buttonStyle(.borderless)
            .help(filterStore.selected.isEmpty
                  ? "Filter by project"
                  : "Filtering: \(filterStore.keysArray.joined(separator: ", "))")
            Button { mode = .settings } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Change credentials")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit JiraMenu")
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if let err = vm.errorMessage {
            Text(err)
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(10)
        } else if !vm.query.isEmpty {
            searchResults
        } else {
            idleLists
        }
    }

    private var searchResults: some View {
        Group {
            if vm.results.isEmpty && !vm.isLoading {
                Text("No results")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !vm.openResults.isEmpty {
                            resultGroup(
                                title: "Open",
                                issues: vm.openResults,
                                isExpanded: $openExpanded
                            )
                        }
                        if !vm.closedResults.isEmpty {
                            if !vm.openResults.isEmpty { Divider() }
                            resultGroup(
                                title: "Closed",
                                issues: vm.closedResults,
                                isExpanded: $closedExpanded
                            )
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func resultGroup(
        title: String,
        issues: [Issue],
        isExpanded: Binding<Bool>
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(spacing: 0) {
                ForEach(issues) { issue in
                    rowButton(issue)
                    Divider()
                }
            }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Text("\(issues.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 12)
    }

    private var idleLists: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                idleSection("Assigned to me",
                            issues: vm.assigned,
                            isExpanded: $assignedExpanded,
                            emptyHint: nil)

                Divider()

                idleSection("Watching",
                            issues: vm.watching,
                            isExpanded: $watchingExpanded,
                            emptyHint: nil)
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: watchingExpanded) { nowOn in
            if nowOn && vm.watching.isEmpty {
                Task { await vm.loadWatching() }
            }
        }
    }

    @ViewBuilder
    private func idleSection(
        _ title: String,
        issues: [Issue],
        isExpanded: Binding<Bool>,
        emptyHint: String?
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            if let hint = emptyHint, issues.isEmpty {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.leading, 12)
            } else {
                sectionBody(issues)
            }
        } label: {
            Text(title)
                .font(.subheadline.bold())
                .padding(.vertical, 6)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func sectionBody(_ issues: [Issue]) -> some View {
        if issues.isEmpty {
            Text("Loading…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .padding(.leading, 12)
        } else {
            VStack(spacing: 0) {
                ForEach(issues) { issue in
                    Button { open(issue: issue) } label: {
                        ResultRowView(issue: issue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rowButton(_ issue: Issue) -> some View {
        Button { open(issue: issue) } label: {
            ResultRowView(issue: issue)
        }
        .buttonStyle(.plain)
    }

    private func open(issue: Issue) {
        guard let creds = credentialsStore.credentials else { return }
        let url = creds.siteURL.appendingPathComponent("browse/\(issue.key)")
        NSWorkspace.shared.open(url)
    }
}
