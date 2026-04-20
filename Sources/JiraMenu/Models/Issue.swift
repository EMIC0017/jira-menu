import Foundation

struct Issue: Identifiable, Equatable, Codable {
    let key: String
    let summary: String
    let status: String
    let issueType: String

    var id: String { key }
}
