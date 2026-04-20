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
    ///
    /// Free-text uses `summary ~` (not `text ~`) so matches in descriptions
    /// and comments don't pollute results — the user explicitly wanted
    /// subject-line search. Single-word queries get a trailing `*` for
    /// prefix matching ("cart" → "cart*"); multi-word queries stay as a
    /// phrase since JQL doesn't cleanly accept wildcards inside a phrase.
    static func buildJQL(for input: ParsedInput, projectKeys: [String] = []) -> String? {
        let core: String?
        switch input {
        case .empty:
            core = nil
        case .issueKey(let key), .issueURL(let key):
            core = "key = \(key)"
        case .freeText(let text):
            core = summaryMatchClause(for: text)
        }
        guard let core else { return nil }
        let filter = projectFilterClause(projectKeys)
        let where_ = [core, filter].compactMap { $0 }.joined(separator: " AND ")
        return "\(where_) ORDER BY updated DESC"
    }

    /// JQL for "free-text search restricted to tickets I'm involved in". Runs
    /// alongside the global `buildJQL` so tickets assigned to / reported by /
    /// watched by the current user always appear in the result pool, even
    /// when global `ORDER BY updated DESC` would push them past the maxResults
    /// cutoff. Returns nil for non-free-text inputs.
    static func personalFreeTextJQL(_ text: String, projectKeys: [String] = []) -> String {
        let scope = "(assignee = currentUser() OR reporter = currentUser() OR watcher = currentUser())"
        let core = summaryMatchClause(for: text)
        let filter = projectFilterClause(projectKeys)
        let where_ = [scope, core, filter].compactMap { $0 }.joined(separator: " AND ")
        return "\(where_) ORDER BY updated DESC"
    }

    /// Single-word → `summary ~ "term*"` (prefix match). Multi-word →
    /// `summary ~ "the whole phrase"` because JQL doesn't cleanly support
    /// wildcards inside a phrase. Quotes in the input are escaped.
    private static func summaryMatchClause(for text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        let wildcard = text.contains(" ") ? "" : "*"
        return "summary ~ \"\(escaped)\(wildcard)\""
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

    func search(_ input: ParsedInput, projectKeys: [String] = [], maxResults: Int = 50) async throws -> [Issue] {
        switch input {
        case .empty:
            return []
        case .issueKey(let key):
            // Partial keys ("ETS-4" → "ETS-45") need prefix matching on the key field,
            // which JQL doesn't expose directly. Picker is Jira's own autocomplete for
            // this; its history bias is fine here since users typically look up keys
            // they've been working on.
            return try await pickerSearch(query: key, projectKeys: projectKeys, maxResults: maxResults)
        case .issueURL:
            guard let jql = Self.buildJQL(for: input, projectKeys: projectKeys) else { return [] }
            return try await runJQL(jql, maxResults: maxResults)
        case .freeText(let text):
            // Fan out: global `summary ~` + personal-scope `summary ~`. Merge personal-
            // first so the user's own tickets always reach FuzzyScorer even if they're
            // older than the global ORDER BY updated cap would include.
            guard let globalJQL = Self.buildJQL(for: input, projectKeys: projectKeys) else { return [] }
            let personalJQL = Self.personalFreeTextJQL(text, projectKeys: projectKeys)
            async let globalTask = runJQL(globalJQL, maxResults: maxResults)
            async let personalTask = runJQL(personalJQL, maxResults: 25)
            let (global, personal) = try await (globalTask, personalTask)
            return Self.mergeUnique(personal, global)
        }
    }

    /// Concatenates lists by `Issue.key`, preserving the order of the first
    /// occurrence. Used to merge personal + global search results without
    /// showing duplicates.
    static func mergeUnique(_ lists: [Issue]...) -> [Issue] {
        var seen = Set<String>()
        var merged: [Issue] = []
        for list in lists {
            for issue in list where seen.insert(issue.key).inserted {
                merged.append(issue)
            }
        }
        return merged
    }

    /// Uses `/rest/api/3/issue/picker` for relevance-ranked prefix/fuzzy matching,
    /// then hydrates status + issuetype with a single `key in (...)` JQL call.
    func pickerSearch(query: String, projectKeys: [String] = [], maxResults: Int = 25) async throws -> [Issue] {
        let keys = try await pickerKeys(query: query)
        guard !keys.isEmpty else { return [] }
        let limited = Array(keys.prefix(maxResults))
        return try await hydrate(keys: limited, projectKeys: projectKeys)
    }

    private func pickerKeys(query: String) async throws -> [String] {
        let url = credentials.siteURL.appendingPathComponent("rest/api/3/issue/picker")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "showSubTasks", value: "true"),
        ]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "GET"
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        struct Envelope: Decodable { let sections: [Section] }
        struct Section: Decodable { let issues: [PickerIssue] }
        struct PickerIssue: Decodable { let key: String }

        let env = try JSONDecoder().decode(Envelope.self, from: data)
        var seen = Set<String>()
        var ordered: [String] = []
        for section in env.sections {
            for issue in section.issues {
                if seen.insert(issue.key).inserted { ordered.append(issue.key) }
            }
        }
        return ordered
    }

    private func hydrate(keys: [String], projectKeys: [String]) async throws -> [Issue] {
        let list = keys.map { "\"\($0)\"" }.joined(separator: ", ")
        var jql = "key in (\(list))"
        if let filter = Self.projectFilterClause(projectKeys) {
            jql = "\(jql) AND \(filter)"
        }
        let hydrated = try await runJQL(jql, maxResults: keys.count)
        let byKey = Dictionary(uniqueKeysWithValues: hydrated.map { ($0.key, $0) })
        return keys.compactMap { byKey[$0] }
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
            "fields": ["summary", "status", "issuetype", "resolution"],
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
            let resolution: Named?
        }
        struct Named: Decodable { let name: String }

        let env = try JSONDecoder().decode(Envelope.self, from: data)
        return env.issues.map {
            Issue(
                key: $0.key,
                summary: $0.fields.summary,
                status: $0.fields.status.name,
                issueType: $0.fields.issuetype.name,
                resolution: $0.fields.resolution?.name
            )
        }
    }
}
