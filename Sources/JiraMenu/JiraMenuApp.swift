import SwiftUI
import AppKit

@main
struct JiraMenuApp: App {
    @StateObject private var credentialsStore: CredentialsStore
    @StateObject private var filterStore: ProjectFilterStore
    @StateObject private var projectsStore: ProjectsStore
    @StateObject private var searchVM: SearchViewModel

    init() {
        let credentials = CredentialsStore()
        let filter = ProjectFilterStore()
        let projects = ProjectsStore()
        projects.configure {
            credentials.credentials.map { JiraClient(credentials: $0) }
        }

        let vm = SearchViewModel(
            search: { input, keys in
                guard let creds = credentials.credentials else { return [] }
                return try await JiraClient(credentials: creds).search(input, projectKeys: keys)
            },
            assigned: { keys in
                guard let creds = credentials.credentials else { return [] }
                return try await JiraClient(credentials: creds).assignedToMe(projectKeys: keys)
            },
            watching: { keys in
                guard let creds = credentials.credentials else { return [] }
                return try await JiraClient(credentials: creds).watching(projectKeys: keys)
            }
        )

        _credentialsStore = StateObject(wrappedValue: credentials)
        _filterStore = StateObject(wrappedValue: filter)
        _projectsStore = StateObject(wrappedValue: projects)
        _searchVM = StateObject(wrappedValue: vm)
    }

    /// Computed lazily the first time `body` runs. SwiftUI doesn't re-evaluate
    /// the label closure on every frame, so building an NSImage here is cheap.
    private var menuBarIcon: NSImage { jiraLoupeMenuBarImage() }

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environmentObject(credentialsStore)
                .environmentObject(filterStore)
                .environmentObject(projectsStore)
                .environmentObject(searchVM)
        } label: {
            Image(nsImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
