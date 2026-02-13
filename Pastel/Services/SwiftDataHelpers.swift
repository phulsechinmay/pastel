import SwiftData
import OSLog

private let swiftDataLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
    category: "SwiftData"
)

@MainActor
func saveWithLogging(_ modelContext: ModelContext, operation: String) {
    do {
        try modelContext.save()
    } catch {
        swiftDataLogger.error("Save failed during \(operation): \(error.localizedDescription)")
    }
}
