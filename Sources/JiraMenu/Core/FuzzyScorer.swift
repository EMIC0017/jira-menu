import Foundation

/// Ranks Jira issues against a user query with simple additive buckets.
/// Higher is better; 0 means no match.
enum FuzzyScorer {
    static func score(query: String, against issue: Issue) -> Int {
        let q = query.lowercased()
        guard !q.isEmpty else { return 0 }

        let key = issue.key.lowercased()
        let summary = issue.summary.lowercased()
        var total = 0

        if key == q { total += 1000 }
        else if key.hasPrefix(q) { total += 500 }
        else if key.contains(q) { total += 100 }

        let summaryWords = summary.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if summaryWords.contains(where: { $0.hasPrefix(q) }) {
            total += 50
        } else if summary.contains(q) {
            total += 10
        }

        return total
    }

    static func rank(query: String, issues: [Issue]) -> [Issue] {
        guard !query.isEmpty else { return issues }
        return issues
            .map { ($0, score(query: query, against: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
}
