// ActionResult.swift
// OpenClip
//
// Defines the value enum representing execution results and platform side-effects returned by actions.
// Specifies outcomes such as copy, cut, paste, URL opening, system service triggers, or simple success/failure.
import Foundation

public enum ActionResult: Sendable {
    case success
    case failure(Error)
    case simulatePaste
    case openURL(URL)
    case copy(String)
    case cut(String)
    case paste(String)
    case showServices(String)
    case none
}
