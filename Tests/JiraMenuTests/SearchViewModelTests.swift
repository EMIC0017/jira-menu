import XCTest
@testable import JiraMenu

@MainActor
final class SearchViewModelTests: XCTestCase {
    private let issueA = Issue(key: "AB-1", summary: "fix login", status: "Open", issueType: "Bug")
    private let issueB = Issue(key: "AB-2", summary: "ship it", status: "Done", issueType: "Task")

    // Very small debounce; tests wait slightly longer.
    private let debounce: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(10)

    func test_emptyQueryYieldsNoResultsAndNoCall() async throws {
        var callCount = 0
        let vm = SearchViewModel(debounce: debounce) { _ in
            callCount += 1
            return []
        }
        vm.query = ""
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.results, [])
        XCTAssertEqual(callCount, 0)
        XCTAssertFalse(vm.isLoading)
    }

    func test_nonEmptyQueryTriggersSearchAndRanksResults() async throws {
        let vm = SearchViewModel(debounce: debounce) { [issueA, issueB] input in
            XCTAssertEqual(input, .freeText("login"))
            return [issueA, issueB]
        }
        vm.query = "login"
        try await waitUntil { vm.results.isEmpty == false || vm.errorMessage != nil }
        XCTAssertEqual(vm.results.map(\.key), ["AB-1"])  // issueB doesn't match "login"
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func test_errorPopulatesErrorMessageAndClearsResults() async throws {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let vm = SearchViewModel(debounce: debounce) { _ in throw Boom() }
        vm.query = "anything"
        try await waitUntil { vm.errorMessage != nil }
        XCTAssertEqual(vm.errorMessage, "boom")
        XCTAssertEqual(vm.results, [])
        XCTAssertFalse(vm.isLoading)
    }

    func test_debounceCollapsesRapidKeystrokes() async throws {
        var callCount = 0
        let vm = SearchViewModel(debounce: .milliseconds(80)) { _ in
            callCount += 1
            return []
        }
        vm.query = "l"
        vm.query = "lo"
        vm.query = "log"
        vm.query = "logi"
        vm.query = "login"
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(callCount, 1, "only final keystroke should trigger the search")
    }

    // MARK: - helpers

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition not met within \(timeout)s")
    }
}
