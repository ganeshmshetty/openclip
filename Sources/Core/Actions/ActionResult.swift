import Foundation

public enum ActionResult: Sendable {
    case success
    case failure(Error)
    case simulatePaste
    case openURL(URL)
    case copy(String)
    case cut(String)
    case showServices(String)
    case none
}
