import Foundation

/// Classifies a raw search string into a ParsedInput case so downstream code
/// can build the right JQL or skip the network round-trip entirely.
enum InputParser {
    private static let issueKeyPattern = "^[A-Z][A-Z0-9]*-\\d+$"

    static func parse(_ raw: String) -> ParsedInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }

        if trimmed.contains("/browse/"),
           let tail = trimmed.components(separatedBy: "/browse/").last,
           let key = tail.components(separatedBy: "?").first,
           !key.isEmpty {
            return .issueURL(key)
        }

        let upper = trimmed.uppercased()
        if upper.range(of: issueKeyPattern, options: .regularExpression) != nil {
            return .issueKey(upper)
        }

        return .freeText(raw)
    }
}
