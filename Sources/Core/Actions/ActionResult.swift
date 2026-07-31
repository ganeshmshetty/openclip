import Foundation

public enum ActionResult: Sendable {
    case success
    case failure(Error)
    case paste(String)
    case openURL(URL)
    case copy(String)
    case none
}
