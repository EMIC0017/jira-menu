import Foundation

/// Thin wrapper over Jira Cloud's REST API v3.
/// Uses `POST /rest/api/3/search/jql` with a JSON body — the legacy
/// `GET /rest/api/3/search` was deprecated in 2024.
struct JiraClient {
    let credentials: Credentials
    let session: URLSession

    init(credentials: Credentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    enum ClientError: Error {
        case invalidURL
        case httpStatus(Int)
        case decoding
    }

    /// Builds a JQL string appropriate to the parsed input. Returns nil when
    /// we shouldn't hit the network (empty input).
    static func buildJQL(for input: ParsedInput, projectKeys: [String] = []) -> String? {
        let core: String?
        switch input {
        case .empty:
            core = nil
        case .issueKey(let key), .issueURL(let key):
            core = "key = \(key)"
        case .freeText(let text):
            let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
            core = "text ~ \"\(escaped)\""
        }
        guard let core else { return nil }
        let filter = projectFilterClause(projectKeys)
        let where_ = [core, filter].compactMap { $0 }.joined(separator: " AND ")
        return "\(where_) ORDER BY updated DESC"
    }

    /// JQL for "issues assigned to the current user", optionally filtered by project.
    static func assignedToMeJQL(projectKeys: [String] = []) -> String {
        let base = "assignee = currentUser() AND resolution = Unresolved"
        return combine(base, projectFilterClause(projectKeys)) + " ORDER BY updated DESC"
    }

    /// JQL for "issues the current user is watching".
    static func watchingJQL(projectKeys: [String] = []) -> String {
        let base = "watcher = currentUser()"
        return combine(base, projectFilterClause(projectKeys)) + " ORDER BY updated DESC"
    }

    private static func projectFilterClause(_ keys: [String]) -> String? {
        guard !keys.isEmpty else { return nil }
        let list = keys.map { "\"\($0)\"" }.joined(separator: ", ")
        return "project in (\(list))"
    }

    private static func combine(_ a: String, _ b: String?) -> String {
        guard let b else { return a }
        return "\(a) AND \(b)"
    }

    // MARK: - Search

    func search(_ input: ParsedInput, projectKeys: [String] = [], maxResults: Int = 25) async throws -> [Issue] {
        guard let jql = Self.buildJQL(for: input, projectKeys: projectKeys) else { return [] }
        return try await runJQL(jql, maxResults: maxResults)
    }

    func assignedToMe(projectKeys: [String] = [], maxResults: Int = 10) async throws -> [Issue] {
        try await runJQL(Self.assignedToMeJQL(projectKeys: projectKeys), maxResults: maxResults)
    }

    func watching(projectKeys: [String] = [], maxResults: Int = 10) async throws -> [Issue] {
        try await runJQL(Self.watchingJQL(projectKeys: projectKeys), maxResults: maxResults)
    }

    // MARK: - Projects

    func projects() async throws -> [Project] {
        struct Envelope: Decodable {
            let values: [Project]
            let isLast: Bool?
            let nextPage: String?
            let total: Int?
        }

        var all: [Project] = []
        var startAt = 0
        let pageSize = 50
        // Hard ceiling so a runaway endpoint can't spin forever.
        while all.count < 2000 {
            let url = credentials.siteURL.appendingPathComponent("rest/api/3/project/search")
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                URLQueryItem(name: "startAt", value: "\(startAt)"),
                URLQueryItem(name: "maxResults", value: "\(pageSize)"),
                URLQueryItem(name: "orderBy", value: "name"),
            ]
            var request = URLRequest(url: comps.url!)
            request.httpMethod = "GET"
            request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            try Self.validate(response)
            let page = try JSONDecoder().decode(Envelope.self, from: data)
            all.append(contentsOf: page.values)

            let done = page.isLast == true
                || page.values.count < pageSize
                || (page.total.map { all.count >= $0 } ?? false)
            if done { break }
            startAt += page.values.count
        }

        return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Internals

    private func runJQL(_ jql: String, maxResults: Int) async throws -> [Issue] {
        let url = credentials.siteURL.appendingPathComponent("rest/api/3/search/jql")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "jql": jql,
            "fields": ["summary", "status", "issuetype"],
            "maxResults": maxResults,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decodeIssues(data)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.httpStatus(http.statusCode)
        }
    }

    private func decodeIssues(_ data: Data) throws -> [Issue] {
        struct Envelope: Decodable {
            let issues: [RawIssue]
        }
        struct RawIssue: Decodable {
            let key: String
            let fields: Fields
        }
        struct Fields: Decodable {
            let summary: String
            let status: Named
            let issuetype: Named
        }
        struct Named: Decodable { let name: String }

        let env = try JSONDecoder().decode(Envelope.self, from: data)
        return env.issues.map {
            Issue(
                key: $0.key,
                summary: $0.fields.summary,
                status: $0.fields.status.name,
                issueType: $0.fields.issuetype.name
            )
        }
    }
}
