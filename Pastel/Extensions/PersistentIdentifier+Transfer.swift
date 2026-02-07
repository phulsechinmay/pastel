import SwiftData
import Foundation

extension PersistentIdentifier {
    /// Encode this identifier as a JSON string for drag-and-drop transfer.
    var asTransferString: String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }

    /// Decode a PersistentIdentifier from a JSON string produced by `asTransferString`.
    static func fromTransferString(_ string: String) -> PersistentIdentifier? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }
}
