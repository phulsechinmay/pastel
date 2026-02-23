import CloudKit
import CoreData
import OSLog
import SwiftData

@MainActor
@Observable
final class SyncMonitor {
    enum SyncPhase: Equatable {
        case setup
        case importing(isInitial: Bool)
        case exporting
    }

    enum SyncState: Equatable {
        case disabled
        case synced
        case syncing(phase: SyncPhase)
        case error(String)
        case accountUnavailable

        static func == (lhs: SyncState, rhs: SyncState) -> Bool {
            switch (lhs, rhs) {
            case (.disabled, .disabled),
                 (.synced, .synced),
                 (.accountUnavailable, .accountUnavailable):
                return true
            case let (.syncing(a), .syncing(b)):
                return a == b
            case let (.error(a), .error(b)):
                return a == b
            default:
                return false
            }
        }
    }

    var state: SyncState = .disabled
    var iCloudAccountName: String?

    /// Last successful sync completion date (for "Last synced: X ago" display)
    var lastSyncDate: Date?

    /// Number of items imported during the last sync cycle
    var lastImportedCount: Int = 0

    /// Number of items exported during the last sync cycle
    var lastExportedCount: Int = 0

    private var eventObserver: Any?
    private var accountObserver: Any?
    private var syncedWorkItem: DispatchWorkItem?

    /// Whether the first import has completed since app launch (for initial sync detection)
    private var hasCompletedFirstImport = false

    /// Item count snapshot taken before an import event starts
    private var preImportItemCount: Int = 0

    /// Timestamp of the last successful export end (for counting local items since)
    private var lastExportEndDate: Date?

    /// ModelContext for item count queries (set via configure(modelContext:))
    private var modelContext: ModelContext?

    /// Start time of a setup event (for suppressing short setup displays)
    private var setupStartDate: Date?

    /// Work item for delayed setup state transition
    private var setupDelayWorkItem: DispatchWorkItem?

    private let logger = Logger(
        subsystem: "app.pastel.Pastel",
        category: "SyncMonitor"
    )

    /// Configure the SyncMonitor with a ModelContext for item count queries.
    /// Call this from PastelApp lifecycle after creating the SyncMonitor.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func startMonitoring() {
        // Subscribe to CloudKit sync events
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            // Extract sendable values before crossing to MainActor
            let eventType = event.type
            let endDate = event.endDate
            let error = event.error
            MainActor.assumeIsolated {
                self?.handleSyncEvent(type: eventType, endDate: endDate, error: error)
            }
        }

        // Subscribe to iCloud account changes
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAccountStatus()
            }
        }

        // Initial account check
        Task { await checkAccountStatus() }
    }

    private func handleSyncEvent(
        type: NSPersistentCloudKitContainer.EventType,
        endDate: Date?,
        error: (any Error)?
    ) {
        if endDate == nil {
            // Event started — cancel any pending synced transition
            syncedWorkItem?.cancel()
            syncedWorkItem = nil

            // Reset counts when transitioning from non-syncing to syncing
            if case .syncing = state {} else {
                lastImportedCount = 0
                lastExportedCount = 0
            }

            switch type {
            case .setup:
                // Only show "Setting up..." if setup takes > 2 seconds
                setupStartDate = Date()
                setupDelayWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.state = .syncing(phase: .setup)
                }
                setupDelayWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)

            case .import:
                setupDelayWorkItem?.cancel()
                if preImportItemCount == 0 {
                    preImportItemCount = currentItemCount()
                }
                state = .syncing(phase: .importing(isInitial: !hasCompletedFirstImport))

            case .export:
                setupDelayWorkItem?.cancel()
                state = .syncing(phase: .exporting)

            @unknown default:
                setupDelayWorkItem?.cancel()
                state = .syncing(phase: .importing(isInitial: false))
            }
        } else if let error {
            // Event failed
            syncedWorkItem?.cancel()
            syncedWorkItem = nil
            setupDelayWorkItem?.cancel()
            let message = friendlyErrorMessage(from: error)
            state = .error(message)
            logger.warning("Sync error (\(String(describing: type))): \(message)")
        } else {
            // Event succeeded
            setupDelayWorkItem?.cancel()

            switch type {
            case .import:
                let postCount = currentItemCount()
                lastImportedCount += max(0, postCount - preImportItemCount)
                preImportItemCount = 0
                hasCompletedFirstImport = true

            case .export:
                lastExportedCount = countLocalItemsSince(lastExportEndDate)
                lastExportEndDate = endDate

            case .setup:
                break

            @unknown default:
                break
            }

            lastSyncDate = endDate

            // Debounce the transition to .synced (1s) to avoid flickering
            syncedWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.state = .synced
            }
            syncedWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

    // MARK: - Helpers

    private func currentItemCount() -> Int {
        guard let modelContext else { return 0 }
        return (try? modelContext.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
    }

    private func countLocalItemsSince(_ date: Date?) -> Int {
        guard let modelContext else { return 0 }
        let deviceID = DeviceIdentifier.current
        let sinceDate = date ?? .distantPast
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { item in
                item.originDeviceID == deviceID && item.timestamp > sinceDate
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func friendlyErrorMessage(from error: any Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }
        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return "No internet connection"
        case .notAuthenticated:
            return "Not signed in to iCloud"
        case .quotaExceeded:
            return "iCloud storage full"
        case .serviceUnavailable, .serverResponseLost:
            return "iCloud temporarily unavailable"
        case .requestRateLimited, .zoneBusy:
            return "iCloud busy — will retry"
        case .partialFailure:
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error] {
                let hasQuota = partialErrors.values.contains { ($0 as? CKError)?.code == .quotaExceeded }
                if hasQuota { return "iCloud storage full" }
            }
            return "Partial sync failure — will retry"
        default:
            let desc = ckError.localizedDescription
            return desc.count > 60 ? String(desc.prefix(57)) + "..." : desc
        }
    }

    private func checkAccountStatus() async {
        let container = CKContainer(identifier: "iCloud.app.pastel.Pastel")

        guard let status = try? await container.accountStatus(),
              status == .available else {
            state = .accountUnavailable
            iCloudAccountName = nil
            logger.info("iCloud account not available")
            return
        }

        // Try to get user name without prompting for permission
        // Use completion-handler wrappers since async variants are unavailable in Swift 6.2
        do {
            let recordID: CKRecord.ID = try await withCheckedThrowingContinuation { continuation in
                container.fetchUserRecordID { recordID, error in
                    if let recordID {
                        continuation.resume(returning: recordID)
                    } else {
                        continuation.resume(throwing: error ?? CKError(.internalError))
                    }
                }
            }
            let identity: CKUserIdentity = try await withCheckedThrowingContinuation { continuation in
                container.discoverUserIdentity(withUserRecordID: recordID) { identity, error in
                    if let identity {
                        continuation.resume(returning: identity)
                    } else {
                        continuation.resume(throwing: error ?? CKError(.internalError))
                    }
                }
            }
            let name = identity.nameComponents.flatMap {
                PersonNameComponentsFormatter().string(from: $0)
            }
            iCloudAccountName = name
        } catch {
            iCloudAccountName = nil
        }

        // Only update state if not already tracking sync events
        if state == .disabled || state == .accountUnavailable {
            state = .synced
        }
    }

    func stopMonitoring() {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
        eventObserver = nil
        accountObserver = nil
        syncedWorkItem?.cancel()
        syncedWorkItem = nil
        state = .disabled
    }
}
