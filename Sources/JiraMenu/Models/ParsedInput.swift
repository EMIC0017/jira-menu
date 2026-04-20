import Foundation

enum ParsedInput: Equatable {
    case empty
    case issueKey(String)
    case issueURL(String)
    case freeText(String)
}
