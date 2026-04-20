import XCTest
@testable import JiraMenu

final class InputParserTests: XCTestCase {
    func test_emptyInput() {
        XCTAssertEqual(InputParser.parse(""), .empty)
        XCTAssertEqual(InputParser.parse("   "), .empty)
    }

    func test_fullIssueKey() {
        XCTAssertEqual(InputParser.parse("PROJ-123"), .issueKey("PROJ-123"))
        XCTAssertEqual(InputParser.parse("proj-123"), .issueKey("PROJ-123"))
        XCTAssertEqual(InputParser.parse("  ENG-9  "), .issueKey("ENG-9"))
    }

    func test_urlWithBrowseKey() {
        let url = "https://acme.atlassian.net/browse/ENG-42"
        XCTAssertEqual(InputParser.parse(url), .issueURL("ENG-42"))
    }

    func test_urlWithQueryParams() {
        let url = "https://acme.atlassian.net/browse/PSO-7?focusedCommentId=1000"
        XCTAssertEqual(InputParser.parse(url), .issueURL("PSO-7"))
    }

    func test_freeTextNumbersAlone() {
        XCTAssertEqual(InputParser.parse("123"), .freeText("123"))
    }

    func test_freeTextWords() {
        XCTAssertEqual(InputParser.parse("login bug"), .freeText("login bug"))
    }

    func test_partialKeyIsFreeText() {
        XCTAssertEqual(InputParser.parse("PROJ"), .freeText("PROJ"))
    }
}
