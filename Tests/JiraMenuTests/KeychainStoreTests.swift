import XCTest
@testable import JiraMenu

final class KeychainStoreTests: XCTestCase {
    private let testService = "dev.ericmorin.jiramenu.test"
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: testService)
        try? store.delete()
    }

    override func tearDown() {
        try? store.delete()
        super.tearDown()
    }

    func test_roundTrip() throws {
        let creds = Credentials(
            siteURL: URL(string: "https://acme.atlassian.net")!,
            email: "me@acme.com",
            apiToken: "tok_abc"
        )
        try store.save(creds)
        let loaded = try store.load()
        XCTAssertEqual(loaded, creds)
    }

    func test_loadReturnsNilWhenMissing() throws {
        XCTAssertNil(try store.load())
    }

    func test_overwrite() throws {
        let c1 = Credentials(
            siteURL: URL(string: "https://a.atlassian.net")!,
            email: "a@a",
            apiToken: "1"
        )
        let c2 = Credentials(
            siteURL: URL(string: "https://b.atlassian.net")!,
            email: "b@b",
            apiToken: "2"
        )
        try store.save(c1)
        try store.save(c2)
        XCTAssertEqual(try store.load(), c2)
    }
}
