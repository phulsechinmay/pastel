import AppKit
import CryptoKit
import OSLog
import SwiftData

/// Core clipboard monitoring service that polls NSPasteboard for changes,
/// classifies content types, deduplicates consecutive copies, and persists
/// clipboard items to SwiftData.
///
/// All pasteboard reading happens on the main thread (NSPasteboard is NOT thread-safe).
/// Timer fires on the main run loop (default for Timer.scheduledTimer).
@MainActor
@Observable
final class ClipboardMonitor {

    // MARK: - Observable Properties

    /// Whether the monitor is actively capturing clipboard changes
    var isMonitoring: Bool = true

    /// Total count of captured clipboard items (reactive for UI binding)
    var itemCount: Int = 0

    /// When true, the next clipboard change will be skipped (self-paste loop prevention, Phase 3)
    var skipNextChange: Bool = false

    // MARK: - Private Properties

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    private var modelContext: ModelContext
    private var wakeObserver: NSObjectProtocol?

    /// Auto-expiration service for concealed clipboard items (password managers)
    private let expirationService: ExpirationService

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "ClipboardMonitor"
    )

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.expirationService = ExpirationService(modelContext: modelContext)

        // Load initial item count from SwiftData
        do {
            let descriptor = FetchDescriptor<ClipboardItem>()
            self.itemCount = try modelContext.fetchCount(descriptor)
        } catch {
            Self.logger.error("Failed to fetch initial item count: \(error.localizedDescription)")
            self.itemCount = 0
        }

        // Sync with current pasteboard state
        self.lastChangeCount = pasteboard.changeCount

        // Clean up any concealed items that expired while the app was not running
        expirationService.expireOverdueItems()
    }

    // No deinit needed: ClipboardMonitor lives for the app's lifetime.
    // Timer uses [weak self] so it won't retain the monitor.
    // Call stop() explicitly if cleanup is ever needed.

    // MARK: - Public Methods

    /// Start monitoring the clipboard for changes.
    ///
    /// Creates a 0.5s repeating timer on the main run loop and registers
    /// for system wake notifications to catch changes during sleep.
    func start() {
        // Re-sync with current pasteboard state
        lastChangeCount = pasteboard.changeCount

        // Create polling timer (0.5s interval per research recommendation)
        let pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }
        pollTimer.tolerance = 0.1 // Energy efficiency
        self.timer = pollTimer

        // Register for system wake to catch clipboard changes during sleep
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkForChanges()
            }
        }

        Self.logger.info("Clipboard monitoring started")
    }

    /// Stop monitoring the clipboard.
    func stop() {
        timer?.invalidate()
        timer = nil

        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }

        Self.logger.info("Clipboard monitoring stopped")
    }

    /// Toggle monitoring on/off.
    func toggleMonitoring() {
        isMonitoring.toggle()
        if isMonitoring {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Private Methods

    /// Check if the pasteboard has changed since last poll.
    private func checkForChanges() {
        guard isMonitoring else { return }

        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        // Phase 3 self-paste prevention: skip if flagged
        if skipNextChange {
            skipNextChange = false
            return
        }

        processPasteboardContent()
    }

    /// Process the current pasteboard content: classify, deduplicate, and persist.
    private func processPasteboardContent() {
        // Classify content type
        guard let (contentType, isConcealed) = pasteboard.classifyContent() else {
            return // Empty, transient, or auto-generated -- skip
        }

        // Image capture follows an async path (disk I/O on background queue)
        if contentType == .image {
            processImageContent(isConcealed: isConcealed)
            return
        }

        // Read content based on type
        var textContent: String?
        var htmlContent: String?
        var rtfData: Data?
        var byteCount: Int = 0
        var primaryContent: String = "" // Used for hashing

        switch contentType {
        case .text, .richText:
            let result = pasteboard.readTextContent()
            textContent = result.text
            htmlContent = result.html
            rtfData = result.rtfData
            byteCount = result.byteCount
            primaryContent = result.text ?? ""

        case .url:
            let result = pasteboard.readURLContent()
            textContent = result.urlString
            byteCount = result.byteCount
            primaryContent = result.urlString ?? ""

        case .file:
            let result = pasteboard.readFileContent()
            textContent = result.filePath
            byteCount = result.byteCount
            primaryContent = result.filePath ?? ""

        case .image:
            return // Handled above, but needed for exhaustive switch
        }

        // Skip if no content was actually read
        guard !primaryContent.isEmpty else { return }

        // Capture source app
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let sourceAppBundleID = sourceApp?.bundleIdentifier
        let sourceAppName = sourceApp?.localizedName

        // Compute SHA256 content hash
        let hashData = Data(primaryContent.utf8)
        let digest = SHA256.hash(data: hashData)
        let contentHash = digest.compactMap { String(format: "%02x", $0) }.joined()

        // Consecutive duplicate check: fetch most recent item
        if isDuplicateOfMostRecent(contentHash: contentHash) { return }

        // Create and persist the clipboard item
        let item = ClipboardItem(
            textContent: textContent,
            htmlContent: htmlContent,
            rtfData: rtfData,
            contentType: contentType,
            timestamp: .now,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            characterCount: textContent?.count ?? 0,
            byteCount: byteCount,
            changeCount: pasteboard.changeCount,
            imagePath: nil,
            thumbnailPath: nil,
            isConcealed: isConcealed,
            expiresAt: isConcealed ? Date.now.addingTimeInterval(60) : nil,
            contentHash: contentHash
        )

        modelContext.insert(item)

        do {
            try modelContext.save()
            itemCount += 1
            Self.logger.info("Captured \(contentType.rawValue) item from \(sourceAppName ?? "unknown") (\(byteCount) bytes)")

            // Schedule expiration for concealed items (password managers)
            if isConcealed {
                expirationService.scheduleExpiration(for: item)
            }
        } catch {
            // Handle @Attribute(.unique) conflict gracefully -- non-consecutive duplicate
            Self.logger.warning("Failed to save clipboard item: \(error.localizedDescription)")
            // Rollback the insert to keep context consistent
            modelContext.rollback()
        }
    }

    // MARK: - Image Capture

    /// Process image content from the pasteboard asynchronously.
    ///
    /// Image data is read on the main thread (NSPasteboard is NOT thread-safe),
    /// then handed to ImageStorageService for background disk I/O. The ClipboardItem
    /// is created in the completion handler back on the main thread.
    private func processImageContent(isConcealed: Bool) {
        // Read image data on the main thread (NSPasteboard is NOT thread-safe)
        guard let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) else {
            Self.logger.warning("Image classified but no image data found on pasteboard")
            return
        }

        // Compute hash for dedup (first 4KB for speed)
        let contentHash = ImageStorageService.computeImageHash(data: imageData)

        // Consecutive duplicate check
        if isDuplicateOfMostRecent(contentHash: contentHash) { return }

        // Capture source app (must be on main thread)
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let sourceAppBundleID = sourceApp?.bundleIdentifier
        let sourceAppName = sourceApp?.localizedName
        let imageByteCount = imageData.count
        let currentChangeCount = pasteboard.changeCount

        // Save image to disk on background queue; completion fires on main thread
        ImageStorageService.shared.saveImage(data: imageData) { [weak self] imagePath, thumbnailPath in
            guard let self else { return }

            let item = ClipboardItem(
                textContent: nil,
                htmlContent: nil,
                rtfData: nil,
                contentType: .image,
                timestamp: .now,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                characterCount: 0,
                byteCount: imageByteCount,
                changeCount: currentChangeCount,
                imagePath: imagePath,
                thumbnailPath: thumbnailPath,
                isConcealed: isConcealed,
                expiresAt: isConcealed ? Date.now.addingTimeInterval(60) : nil,
                contentHash: contentHash
            )

            self.modelContext.insert(item)

            do {
                try self.modelContext.save()
                self.itemCount += 1
                Self.logger.info("Captured image from \(sourceAppName ?? "unknown") (\(imageByteCount) bytes, path: \(imagePath ?? "none"))")

                // Schedule expiration for concealed items
                if isConcealed {
                    self.expirationService.scheduleExpiration(for: item)
                }
            } catch {
                Self.logger.warning("Failed to save image clipboard item: \(error.localizedDescription)")
                self.modelContext.rollback()
            }
        }
    }

    // MARK: - Deduplication

    /// Check if the given content hash matches the most recent clipboard item.
    ///
    /// - Parameter contentHash: SHA256 hash of the content.
    /// - Returns: `true` if this is a consecutive duplicate and should be skipped.
    private func isDuplicateOfMostRecent(contentHash: String) -> Bool {
        do {
            var recentDescriptor = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            recentDescriptor.fetchLimit = 1
            let recentItems = try modelContext.fetch(recentDescriptor)

            if let lastItem = recentItems.first, lastItem.contentHash == contentHash {
                Self.logger.debug("Consecutive duplicate detected, skipping")
                return true
            }
        } catch {
            Self.logger.error("Failed to fetch recent item for dedup check: \(error.localizedDescription)")
            // Continue with insertion -- better to have a duplicate than lose data
        }
        return false
    }
}
