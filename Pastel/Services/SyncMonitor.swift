import CloudKit
import CoreData
import OSLog

@MainActor
@Observable
final class SyncMonitor {
    enum SyncState: Equatable {
        case disabled
        case synced
        case syncing
        case error(String)
        case accountUnavailable

        static func == (lhs: SyncState, rhs: SyncState) -> Bool {
            switch (lhs, rhs) {
            case (.disabled, .disabled),
                 (.synced, .synced),
                 (.syncing, .syncing),
                 (.accountUnavailable, .accountUnavailable):
                return true
            case let (.error(a), .error(b)):
                return a == b
            default:
                return false
            }
        }
    }

    var state: SyncState = .disabled
    var iCloudAccountName: String?

    private var eventObserver: Any?
    private var accountObserver: Any?
    private var syncedWorkItem: DispatchWorkItem?

    private let logger = Logger(
        subsystem: "app.pastel.Pastel",
        category: "SyncMonitor"
    )

    func startMonitoring() {
        // Subscribe to CloudKit sync events
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract sendable data from event before crossing to MainActor
            let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event
            let hasEnded = event?.endDate != nil
            let errorMessage = event?.error?.localizedDescription
            MainActor.assumeIsolated {
                self?.handleSyncChange(hasEnded: hasEnded, errorMessage: errorMessage)
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

    private func handleSyncChange(hasEnded: Bool, errorMessage: String?) {
        if !hasEnded {
            // Event in progress -- cancel any pending synced transition
            syncedWorkItem?.cancel()
            syncedWorkItem = nil
            state = .syncing
        } else if let errorMessage {
            syncedWorkItem?.cancel()
            syncedWorkItem = nil
            state = .error(errorMessage)
            logger.warning("Sync error: \(errorMessage)")
        } else {
            // Event completed -- debounce the transition to .synced (1s)
            // to avoid flickering when multiple events complete in sequence
            syncedWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.state = .synced
            }
            syncedWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
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
