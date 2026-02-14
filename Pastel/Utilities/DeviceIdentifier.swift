import Foundation

/// Generates and persists a stable per-device UUID in UserDefaults.
///
/// Each device gets its own unique ID on first access. Stored in local UserDefaults
/// (NOT NSUbiquitousKeyValueStore) so each device retains a distinct identity even
/// when iCloud sync is enabled. Used to stamp originDeviceID on ClipboardItems.
enum DeviceIdentifier {
    private static let key = "pastelDeviceUUID"

    /// Stable per-device UUID. Generated on first access, persisted in UserDefaults.
    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}
