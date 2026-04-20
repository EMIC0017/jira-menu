import Foundation

struct Credentials: Equatable {
    let siteURL: URL
    let email: String
    let apiToken: String

    var basicAuthHeader: String {
        let raw = "\(email):\(apiToken)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}
