import Foundation

public enum ExtensionOptionType: String, Codable, Sendable {
    case string
    case boolean
    case multiple
    case secret
}

public struct ExtensionOption: Identifiable, Codable, Sendable {
    public var id: String { identifier }
    public let identifier: String
    public let label: String
    public let type: ExtensionOptionType
    public let defaultValue: String?
    public let options: [String]? // For 'multiple' picker choices
    
    public init(
        identifier: String,
        label: String,
        type: ExtensionOptionType = .string,
        defaultValue: String? = nil,
        options: [String]? = nil
    ) {
        self.identifier = identifier
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.options = options
    }
    
    enum CodingKeys: String, CodingKey {
        case identifier
        case label
        case type
        case defaultValue = "default value"
        case options
    }
}
