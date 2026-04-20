import Foundation

struct Issue: Identifiable, Equatable, Codable {
    let key: String
    let summary: String
    let status: String
    let issueType: String
    /// Nil until the issue is resolved. Jira's canonical "closed" signal —
    /// status names vary per workflow, `resolution` does not.
    let resolution: String?

    var id: String { key }

    var isClosed: Bool { resolution != nil }

    init(key: String, summary: String, status: String, issueType: String, resolution: String? = nil) {
        self.key = key
        self.summary = summary
        self.status = status
        self.issueType = issueType
        self.resolution = resolution
    }
}
