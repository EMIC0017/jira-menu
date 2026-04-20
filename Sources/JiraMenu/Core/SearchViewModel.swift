import Foundation
import Combine

/// Drives the popover's state: debounced keystroke-driven search + two idle
/// lists (assigned to me, watching). All network calls are delegated to
/// closures so tests can swap them for fakes.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [Issue] = []
    @Published private(set) var assigned: [Issue] = []
    @Published private(set) var watching: [Issue] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    var openResults: [Issue] { results.filter { !$0.isClosed } }
    var closedResults: [Issue] { results.filter { $0.isClosed } }

    typealias IssueLoader = (ParsedInput, [String]) async throws -> [Issue]
    typealias IdleLoader = ([String]) async throws -> [Issue]

    static let maxResults = 10

    private let searchFn: IssueLoader
    private let assignedFn: IdleLoader
    private let watchingFn: IdleLoader
    private var subscriptions = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?
    var projectKeys: [String] = []

    init(
        debounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(250),
        search: @escaping IssueLoader,
        assigned: @escaping IdleLoader = { _ in [] },
        watching: @escaping IdleLoader = { _ in [] }
    ) {
        self.searchFn = search
        self.assignedFn = assigned
        self.watchingFn = watching
        $query
            .removeDuplicates()
            .debounce(for: debounce, scheduler: DispatchQueue.main)
            .sink { [weak self] q in self?.run(query: q) }
            .store(in: &subscriptions)
    }

    // MARK: - Search

    private func run(query: String) {
        currentTask?.cancel()
        let parsed = InputParser.parse(query)
        if parsed == .empty {
            results = []
            isLoading = false
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        let searchFn = self.searchFn
        let projectKeys = self.projectKeys
        currentTask = Task { [weak self] in
            do {
                let issues = try await searchFn(parsed, projectKeys)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    let ranked = FuzzyScorer.rank(query: query, issues: issues)
                    self.results = Array(ranked.prefix(Self.maxResults))
                    self.isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.results = []
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Idle lists

    func loadAssigned() async {
        do {
            let issues = try await assignedFn(projectKeys)
            assigned = Array(issues.prefix(Self.maxResults))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadWatching() async {
        do {
            let issues = try await watchingFn(projectKeys)
            watching = Array(issues.prefix(Self.maxResults))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Called when the project filter changes — clears all idle caches so
    /// the next disclosure-group expand reloads with the new filter applied.
    func filterChanged() {
        assigned = []
        watching = []
        if !query.isEmpty { run(query: query) }
    }
}
