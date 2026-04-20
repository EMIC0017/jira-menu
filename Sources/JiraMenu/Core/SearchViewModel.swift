import Foundation
import Combine

/// Drives the popover's search state. Debounces keystrokes, delegates the
/// actual lookup to a closure (so tests can swap in a fake), and publishes
/// results, loading state, and errors for SwiftUI to observe.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [Issue] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    typealias Searcher = (ParsedInput) async throws -> [Issue]

    private let search: Searcher
    private var subscriptions = Set<AnyCancellable>()
    private var currentTask: Task<Void, Never>?

    init(
        debounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(250),
        search: @escaping Searcher
    ) {
        self.search = search
        $query
            .removeDuplicates()
            .debounce(for: debounce, scheduler: DispatchQueue.main)
            .sink { [weak self] q in self?.run(query: q) }
            .store(in: &subscriptions)
    }

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
        let search = self.search
        currentTask = Task { [weak self] in
            do {
                let issues = try await search(parsed)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.results = FuzzyScorer.rank(query: query, issues: issues)
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
}
