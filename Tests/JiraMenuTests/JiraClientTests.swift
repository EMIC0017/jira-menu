import XCTest
@testable import JiraMenu

final class JiraClientTests: XCTestCase {
    private let creds = Credentials(
        siteURL: URL(string: "https://acme.atlassian.net")!,
        email: "me@acme.com",
        apiToken: "tok"
    )

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - buildJQL

    func test_buildJQL_emptyReturnsNil() {
        XCTAssertNil(JiraClient.buildJQL(for: .empty))
    }

    func test_buildJQL_issueKeyExactMatch() {
        XCTAssertEqual(JiraClient.buildJQL(for: .issueKey("PSO-12")), "key = PSO-12 ORDER BY updated DESC")
    }

    func test_buildJQL_issueURLExactMatch() {
        XCTAssertEqual(JiraClient.buildJQL(for: .issueURL("PSO-12")), "key = PSO-12 ORDER BY updated DESC")
    }

    func test_buildJQL_freeTextSingleWordGetsPrefixWildcard() {
        let jql = JiraClient.buildJQL(for: .freeText("cart"))
        XCTAssertEqual(jql, "summary ~ \"cart*\" ORDER BY updated DESC")
    }

    func test_buildJQL_freeTextMultiWordIsPhraseWithoutWildcard() {
        let jql = JiraClient.buildJQL(for: .freeText("login bug"))
        XCTAssertEqual(jql, "summary ~ \"login bug\" ORDER BY updated DESC")
    }

    func test_buildJQL_freeTextEscapesQuotes() {
        let jql = JiraClient.buildJQL(for: .freeText("say \"hi\""))
        XCTAssertEqual(jql, "summary ~ \"say \\\"hi\\\"\" ORDER BY updated DESC")
    }

    func test_buildJQL_includesProjectFilter() {
        let jql = JiraClient.buildJQL(for: .freeText("bug"), projectKeys: ["PSO", "ENG"])
        XCTAssertEqual(jql, "summary ~ \"bug*\" AND project in (\"PSO\", \"ENG\") ORDER BY updated DESC")
    }

    func test_assignedToMeJQL() {
        XCTAssertEqual(
            JiraClient.assignedToMeJQL(),
            "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC"
        )
        XCTAssertEqual(
            JiraClient.assignedToMeJQL(projectKeys: ["PSO"]),
            "assignee = currentUser() AND resolution = Unresolved AND project in (\"PSO\") ORDER BY updated DESC"
        )
    }

    func test_watchingJQL() {
        XCTAssertEqual(
            JiraClient.watchingJQL(),
            "watcher = currentUser() ORDER BY updated DESC"
        )
    }

    func test_personalFreeTextJQL_singleWord() {
        XCTAssertEqual(
            JiraClient.personalFreeTextJQL("scoreboard"),
            "(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser()) AND summary ~ \"scoreboard*\" ORDER BY updated DESC"
        )
    }

    func test_personalFreeTextJQL_multiWordHasNoWildcard() {
        XCTAssertEqual(
            JiraClient.personalFreeTextJQL("login bug"),
            "(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser()) AND summary ~ \"login bug\" ORDER BY updated DESC"
        )
    }

    func test_personalFreeTextJQL_includesProjectFilter() {
        XCTAssertEqual(
            JiraClient.personalFreeTextJQL("bug", projectKeys: ["PSO"]),
            "(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser()) AND summary ~ \"bug*\" AND project in (\"PSO\") ORDER BY updated DESC"
        )
    }

    func test_mergeUnique_preservesFirstOccurrenceOrder() {
        let a = Issue(key: "ETS-34", summary: "Review the scoreboard", status: "In Progress", issueType: "Task")
        let b = Issue(key: "ETS-50", summary: "Scoreboard polish", status: "Open", issueType: "Task")
        let c = Issue(key: "ETS-60", summary: "Closed scoreboard thing", status: "Done", issueType: "Task", resolution: "Done")
        let merged = JiraClient.mergeUnique([a, b], [b, c, a])
        XCTAssertEqual(merged.map(\.key), ["ETS-34", "ETS-50", "ETS-60"])
    }

    func test_search_freeText_mergesPersonalAndGlobalResults() async throws {
        var seenJQLs: [String] = []
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = Self.readBody(from: req) ?? Data()
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let jql = json?["jql"] as? String ?? ""
            seenJQLs.append(jql)
            // Personal query returns ETS-34 only (the old assigned ticket).
            // Global query returns fresher tickets without ETS-34.
            let response: String
            if jql.contains("assignee = currentUser()") {
                response = """
                {"issues":[
                  {"key":"ETS-34","fields":{"summary":"Review the scoreboard","status":{"name":"In Progress"},"issuetype":{"name":"Task"}}}
                ]}
                """
            } else {
                response = """
                {"issues":[
                  {"key":"ETS-99","fields":{"summary":"New scoreboard feature","status":{"name":"Open"},"issuetype":{"name":"Task"}}},
                  {"key":"ETS-98","fields":{"summary":"scoreboard polish","status":{"name":"Done"},"issuetype":{"name":"Task"},"resolution":{"name":"Done"}}}
                ]}
                """
            }
            return (resp, response.data(using: .utf8)!)
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        let issues = try await client.search(.freeText("scoreboard"))

        XCTAssertEqual(seenJQLs.count, 2, "expected both personal and global queries to run")
        // ETS-34 (from the personal query) must appear — that's the whole point of the fix.
        XCTAssertTrue(issues.contains(where: { $0.key == "ETS-34" }))
        // And the global matches must still be there, no duplicates.
        XCTAssertEqual(Set(issues.map(\.key)), Set(["ETS-34", "ETS-99", "ETS-98"]))
    }

    // MARK: - search (HTTP)

    func test_search_issueURL_sendsPOSTWithJSONBodyAndBasicAuth() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Self.emptyEnvelope)
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        _ = try await client.search(.issueURL("PSO-1"))

        let req = try XCTUnwrap(captured)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/rest/api/3/search/jql")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), creds.basicAuthHeader)

        // URLProtocol strips httpBody; streamed body lives on httpBodyStream.
        let bodyData = try XCTUnwrap(Self.readBody(from: req))
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(json?["jql"] as? String, "key = PSO-1 ORDER BY updated DESC")
        XCTAssertEqual(json?["fields"] as? [String], ["summary", "status", "issuetype", "resolution"])
        XCTAssertEqual(json?["maxResults"] as? Int, 50)
    }

    func test_search_issueURL_parsesIssues() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {
              "issues": [
                {
                  "key": "PSO-1",
                  "fields": {
                    "summary": "Fix login",
                    "status": {"name": "In Progress"},
                    "issuetype": {"name": "Bug"}
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (resp, body)
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        let issues = try await client.search(.issueURL("PSO-1"))

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0], Issue(key: "PSO-1", summary: "Fix login", status: "In Progress", issueType: "Bug"))
    }

    func test_search_throwsOnNon2xx() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        do {
            _ = try await client.search(.issueURL("X-1"))
            XCTFail("expected throw")
        } catch JiraClient.ClientError.httpStatus(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_search_freeText_fansOutGlobalAndPersonalJQL() async throws {
        var seenJQLs: [String] = []
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if let body = Self.readBody(from: req),
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let jql = json["jql"] as? String {
                seenJQLs.append(jql)
            }
            XCTAssertEqual(req.url?.path, "/rest/api/3/search/jql")
            return (resp, Self.emptyEnvelope)
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        _ = try await client.search(.freeText("cart"))

        XCTAssertEqual(seenJQLs.count, 2, "expected both global and personal queries")
        XCTAssertTrue(seenJQLs.contains("summary ~ \"cart*\" ORDER BY updated DESC"),
                      "missing global JQL in \(seenJQLs)")
        XCTAssertTrue(seenJQLs.contains("(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser()) AND summary ~ \"cart*\" ORDER BY updated DESC"),
                      "missing personal JQL in \(seenJQLs)")
    }

    func test_search_issueKey_routesThroughPickerThenHydrates() async throws {
        var pickerRequest: URLRequest?
        var hydrateRequest: URLRequest?

        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if req.url?.path == "/rest/api/3/issue/picker" {
                pickerRequest = req
                let body = #"{"sections":[{"issues":[{"key":"ETS-4"},{"key":"ETS-45"}]}]}"#.data(using: .utf8)!
                return (resp, body)
            }
            hydrateRequest = req
            let body = """
            {"issues":[
              {"key":"ETS-4","fields":{"summary":"a","status":{"name":"Open"},"issuetype":{"name":"Bug"}}},
              {"key":"ETS-45","fields":{"summary":"b","status":{"name":"Done"},"issuetype":{"name":"Task"},"resolution":{"name":"Done"}}}
            ]}
            """.data(using: .utf8)!
            return (resp, body)
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        let issues = try await client.search(.issueKey("ETS-4"))

        let picker = try XCTUnwrap(pickerRequest)
        XCTAssertEqual(picker.httpMethod, "GET")
        XCTAssertEqual(picker.url?.path, "/rest/api/3/issue/picker")
        XCTAssertEqual(picker.url?.query?.contains("query=ETS-4"), true)

        let hydrate = try XCTUnwrap(hydrateRequest)
        XCTAssertEqual(hydrate.httpMethod, "POST")
        let bodyData = try XCTUnwrap(Self.readBody(from: hydrate))
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(json?["jql"] as? String, "key in (\"ETS-4\", \"ETS-45\")")

        XCTAssertEqual(issues.map(\.key), ["ETS-4", "ETS-45"])
        XCTAssertFalse(issues[0].isClosed)
        XCTAssertTrue(issues[1].isClosed)
    }

    func test_search_emptyInputSkipsNetwork() async throws {
        MockURLProtocol.handler = { _ in
            XCTFail("should not hit network on empty input")
            return (HTTPURLResponse(), Data())
        }
        let client = JiraClient(credentials: creds, session: .mocked())
        let issues = try await client.search(.empty)
        XCTAssertTrue(issues.isEmpty)
    }

    // MARK: - helpers

    private static let emptyEnvelope = "{\"issues\":[]}".data(using: .utf8)!

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
