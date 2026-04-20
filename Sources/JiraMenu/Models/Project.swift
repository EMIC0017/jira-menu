import Foundation

struct Project: Identifiable, Equatable, Codable {
    let key: String
    let name: String
    var id: String { key }
}
