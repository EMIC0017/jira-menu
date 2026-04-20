import XCTest
@testable import JiraMenu

final class FuzzyScorerTests: XCTestCase {
    private func issue(_ key: String, _ summary: String) -> Issue {
        Issue(key: key, summary: summary, status: "Open", issueType: "Task")
    }

    func test_exactKeyMatchScoresHighest() {
        let score = FuzzyScorer.score(query: "PROJ-1", against: issue("PROJ-1", "anything"))
        let lower = FuzzyScorer.score(query: "PROJ-1", against: issue("PROJ-10", "anything"))
        XCTAssertGreaterThan(score, lower)
    }

    func test_keyPrefixBeatsContains() {
        let prefix = FuzzyScorer.score(query: "eng", against: issue("ENG-5", "xyz"))
        let contains = FuzzyScorer.score(query: "eng", against: issue("AB-1", "engineering fix"))
        XCTAssertGreaterThan(prefix, contains)
    }

    func test_summaryWordMatchBeatsNoMatch() {
        let match = FuzzyScorer.score(query: "login", against: issue("AB-1", "Fix login bug"))
        let none = FuzzyScorer.score(query: "login", against: issue("AB-1", "Unrelated work"))
        XCTAssertGreaterThan(match, none)
    }

    func test_caseInsensitive() {
        let upper = FuzzyScorer.score(query: "LOGIN", against: issue("AB-1", "fix login"))
        let lower = FuzzyScorer.score(query: "login", against: issue("AB-1", "fix login"))
        XCTAssertEqual(upper, lower)
    }

    func test_emptyQueryScoresZero() {
        XCTAssertEqual(FuzzyScorer.score(query: "", against: issue("AB-1", "x")), 0)
    }

    func test_rank_sortsHighestFirstAndDropsZeros() {
        let issues = [
            issue("AB-1", "unrelated"),
            issue("LOGIN-1", "whatever"),
            issue("CD-2", "fix login screen"),
        ]
        let ranked = FuzzyScorer.rank(query: "login", issues: issues)
        XCTAssertEqual(ranked.map(\.key), ["LOGIN-1", "CD-2"])
    }
}
