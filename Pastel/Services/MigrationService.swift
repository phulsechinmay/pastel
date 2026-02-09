import Foundation
import SwiftData

@MainActor
final class MigrationService {
    static func migrateLabelsIfNeeded(modelContext: ModelContext) {
        let key = "hasCompletedLabelMigration"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }

        for item in items {
            if let singleLabel = item.label {
                if !item.labels.contains(where: {
                    $0.persistentModelID == singleLabel.persistentModelID
                }) {
                    item.labels.append(singleLabel)
                }
                item.label = nil
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
