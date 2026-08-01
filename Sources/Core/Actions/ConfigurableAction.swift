import Foundation

public protocol ConfigurableAction: Action {
    var configurationViewID: String { get }
    var preferenceIconName: String { get }
}
