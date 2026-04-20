import Foundation

/// Persists the set of project keys the user wants to restrict searches to.
/// Empty set means "search all projects".
final class ProjectFilterStore: ObservableObject {
    private let defaults: UserDefaults
    private let key = "dev.ericmorin.jiramenu.projectFilter"

    @Published private(set) var selected: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.stringArray(forKey: key) ?? []
        self.selected = Set(raw)
    }

    func set(_ keys: Set<String>) {
        selected = keys
        defaults.set(Array(keys).sorted(), forKey: key)
    }

    func clear() { set([]) }

    var keysArray: [String] { Array(selected).sorted() }
}
