import Foundation

/// Thin wrapper over Jira Cloud's REST API v3 search endpoint.
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
    static func buildJQL(for input: ParsedInput) -> String? {
        switch input {
        case .empty:
            return nil
        case .issueKey(let key):
            return "key = \(key)"
        case .issueURL(let key):
            return "key = \(key)"
        case .freeText(let text):
            let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
            return "text ~ \"\(escaped)\" ORDER BY updated DESC"
        }
    }

    func search(_ input: ParsedInput, maxResults: Int = 25) async throws -> [Issue] {
        guard let jql = Self.buildJQL(for: input) else { return [] }

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
        guard let http = response as? HTTPURLResponse else { throw ClientError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.httpStatus(http.statusCode)
        }
        return try decode(data)
    }

    private func decode(_ data: Data) throws -> [Issue] {
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
