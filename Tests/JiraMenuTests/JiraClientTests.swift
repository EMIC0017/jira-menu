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
        XCTAssertEqual(JiraClient.buildJQL(for: .issueKey("PSO-12")), "key = PSO-12")
    }

    func test_buildJQL_issueURLExactMatch() {
        XCTAssertEqual(JiraClient.buildJQL(for: .issueURL("PSO-12")), "key = PSO-12")
    }

    func test_buildJQL_freeTextUsesTextOperator() {
        let jql = JiraClient.buildJQL(for: .freeText("login bug"))
        XCTAssertEqual(jql, "text ~ \"login bug\" ORDER BY updated DESC")
    }

    func test_buildJQL_freeTextEscapesQuotes() {
        let jql = JiraClient.buildJQL(for: .freeText("say \"hi\""))
        XCTAssertEqual(jql, "text ~ \"say \\\"hi\\\"\" ORDER BY updated DESC")
    }

    // MARK: - search (HTTP)

    func test_search_sendsPOSTWithJSONBodyAndBasicAuth() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Self.emptyEnvelope)
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        _ = try await client.search(.freeText("login"))

        let req = try XCTUnwrap(captured)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/rest/api/3/search/jql")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), creds.basicAuthHeader)

        // URLProtocol strips httpBody; streamed body lives on httpBodyStream.
        let bodyData = try XCTUnwrap(Self.readBody(from: req))
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(json?["jql"] as? String, "text ~ \"login\" ORDER BY updated DESC")
        XCTAssertEqual(json?["fields"] as? [String], ["summary", "status", "issuetype"])
        XCTAssertEqual(json?["maxResults"] as? Int, 25)
    }

    func test_search_parsesIssues() async throws {
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
                },
                {
                  "key": "PSO-2",
                  "fields": {
                    "summary": "Ship it",
                    "status": {"name": "Done"},
                    "issuetype": {"name": "Task"}
                  }
                }
              ]
            }
            """.data(using: .utf8)!
            return (resp, body)
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        let issues = try await client.search(.freeText("anything"))

        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues[0], Issue(key: "PSO-1", summary: "Fix login", status: "In Progress", issueType: "Bug"))
        XCTAssertEqual(issues[1], Issue(key: "PSO-2", summary: "Ship it", status: "Done", issueType: "Task"))
    }

    func test_search_throwsOnNon2xx() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        let client = JiraClient(credentials: creds, session: .mocked())
        do {
            _ = try await client.search(.freeText("x"))
            XCTFail("expected throw")
        } catch JiraClient.ClientError.httpStatus(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
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
