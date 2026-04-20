import SwiftUI
import AppKit

/// The popover's root view. Shows SettingsView until credentials exist,
/// then shows the search field + live result list. Clicking a row opens
/// the issue in the user's default browser.
struct PopoverRootView: View {
    @StateObject private var vm: SearchViewModel
    @StateObject private var filterStore = ProjectFilterStore()
    @State private var credentials: Credentials?
    @State private var showSettings = false
    @State private var showFilter = false
    @State private var projects: [Project] = []
    @State private var projectsLoading = false
    @State private var projectsError: String?
    private let store: KeychainStore

    init(store: KeychainStore = KeychainStore()) {
        self.store = store
        let initial = try? store.load()
        _credentials = State(initialValue: initial)
        let client = initial.map { JiraClient(credentials: $0) }
        _vm = StateObject(wrappedValue: SearchViewModel(
            search: { input, keys in
                guard let client else { return [] }
                return try await client.search(input, projectKeys: keys)
            },
            assigned: { keys in
                guard let client else { return [] }
                return try await client.assignedToMe(projectKeys: keys)
            },
            watching: { keys in
                guard let client else { return [] }
                return try await client.watching(projectKeys: keys)
            }
        ))
    }

    var body: some View {
        Group {
            if credentials == nil || showSettings {
                SettingsView(store: store) { creds in
                    credentials = creds
                    showSettings = false
                    projects = []  // force reload for new creds
                }
            } else {
                searchBody
            }
        }
        .frame(width: 460)
        .onReceive(filterStore.$selected) { keys in
            vm.projectKeys = Array(keys).sorted()
            vm.filterChanged()
        }
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
                    if projects.isEmpty { Task { await loadProjects() } }
                    showFilter = true
                } label: {
                    Image(systemName: filterStore.selected.isEmpty
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(filterStore.selected.isEmpty
                      ? "Filter by project"
                      : "Filtering: \(filterStore.keysArray.joined(separator: ", "))")
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Change credentials")
            }
            .padding(12)

            Divider()

            content
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(
                projects: projects,
                initialSelection: filterStore.selected,
                isLoading: projectsLoading,
                errorMessage: projectsError,
                onApply: { keys in
                    filterStore.set(keys)
                    showFilter = false
                },
                onCancel: { showFilter = false }
            )
        }
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
                    LazyVStack(spacing: 0) {
                        ForEach(vm.results) { issue in
                            rowButton(issue)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
    }

    private var idleLists: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                section(
                    title: "Assigned to me",
                    issues: vm.assigned,
                    initiallyExpanded: true,
                    load: { await vm.loadAssigned() }
                )
                Divider()
                section(
                    title: "Watching",
                    issues: vm.watching,
                    initiallyExpanded: false,
                    load: { await vm.loadWatching() }
                )
            }
        }
        .frame(maxHeight: 440)
    }

    private func section(
        title: String,
        issues: [Issue],
        initiallyExpanded: Bool,
        load: @escaping () async -> Void
    ) -> some View {
        ExpandableSection(
            title: title,
            issues: issues,
            initiallyExpanded: initiallyExpanded,
            load: load,
            openIssue: open(issue:)
        )
    }

    private func rowButton(_ issue: Issue) -> some View {
        Button { open(issue: issue) } label: {
            ResultRowView(issue: issue)
        }
        .buttonStyle(.plain)
    }

    private func open(issue: Issue) {
        guard let creds = credentials else { return }
        let url = creds.siteURL.appendingPathComponent("browse/\(issue.key)")
        NSWorkspace.shared.open(url)
    }

    private func loadProjects() async {
        guard let creds = credentials else { return }
        projectsLoading = true
        projectsError = nil
        defer { projectsLoading = false }
        do {
            projects = try await JiraClient(credentials: creds).projects()
        } catch {
            projectsError = error.localizedDescription
        }
    }
}

private struct ExpandableSection: View {
    let title: String
    let issues: [Issue]
    let initiallyExpanded: Bool
    let load: () async -> Void
    let openIssue: (Issue) -> Void

    @State private var expanded: Bool = false
    @State private var didLoad = false

    init(
        title: String,
        issues: [Issue],
        initiallyExpanded: Bool,
        load: @escaping () async -> Void,
        openIssue: @escaping (Issue) -> Void
    ) {
        self.title = title
        self.issues = issues
        self.initiallyExpanded = initiallyExpanded
        self.load = load
        self.openIssue = openIssue
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if issues.isEmpty {
                Text(didLoad ? "Nothing here" : "Loading…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.leading, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(issues) { issue in
                        Button { openIssue(issue) } label: {
                            ResultRowView(issue: issue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } label: {
            Text(title)
                .font(.subheadline.bold())
                .padding(.vertical, 6)
        }
        .padding(.horizontal, 12)
        .task {
            guard expanded && !didLoad else { return }
            await load()
            didLoad = true
        }
        .onChange(of: expanded) { nowExpanded in
            if nowExpanded && !didLoad {
                Task {
                    await load()
                    didLoad = true
                }
            }
        }
    }
}
