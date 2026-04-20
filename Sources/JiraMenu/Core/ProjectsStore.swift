import Foundation

/// Loads and caches the list of projects available on the current Jira site.
/// Injected as an environment object so the filter window can share state
/// with the popover.
@MainActor
final class ProjectsStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private var clientProvider: () -> JiraClient? = { nil }

    func configure(clientProvider: @escaping () -> JiraClient?) {
        self.clientProvider = clientProvider
    }

    func invalidate() {
        projects = []
        errorMessage = nil
    }

    func loadIfNeeded() async {
        guard projects.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        guard let client = clientProvider() else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            projects = try await client.projects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
