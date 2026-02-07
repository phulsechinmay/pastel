import Foundation

enum ContentType: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case url
    case image
    case file
    case code
    case color
}
