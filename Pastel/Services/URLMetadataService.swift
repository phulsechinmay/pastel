import Foundation
import LinkPresentation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// Fetches URL page metadata (title, favicon, og:image) using LPMetadataProvider
/// and persists results to ClipboardItem fields via SwiftData.
///
/// Static service matching ColorDetectionService pattern. All SwiftData operations
/// run on @MainActor. LPMetadataProvider is created fresh per fetch (not Sendable).
struct URLMetadataService {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "URLMetadataService"
    )

    // MARK: - Public API

    /// Whether metadata should be fetched for the given URL string.
    ///
    /// Returns false if:
    /// - The "fetchURLMetadata" user default is disabled
    /// - The URL cannot be parsed
    /// - The scheme is not http or https
    /// - The host is localhost, loopback, or a private/link-local IP address
    static func shouldFetchMetadata(for urlString: String) -> Bool {
        // Check user preference (default: true -- matches @AppStorage default in settings)
        let enabled = UserDefaults.standard.object(forKey: "fetchURLMetadata") as? Bool ?? true
        guard enabled else { return false }

        // Parse URL
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased()
        else { return false }

        // Only http and https
        guard scheme == "http" || scheme == "https" else { return false }

        // Skip private/local addresses
        if isPrivateHost(host) { return false }

        return true
    }

    /// Fetch URL metadata and update the ClipboardItem in SwiftData.
    ///
    /// Called as fire-and-forget from ClipboardMonitor after saving a URL item.
    /// Handles duplicate reuse, LPMetadataProvider fetch with 5s timeout, and
    /// favicon/og:image disk caching.
    @MainActor
    static func fetchMetadata(
        for urlString: String,
        itemID: PersistentIdentifier,
        modelContext: ModelContext
    ) async {
        // Pre-flight checks
        guard shouldFetchMetadata(for: urlString) else { return }
        guard let url = URL(string: urlString) else { return }

        // Resolve the item from SwiftData
        guard let item = modelContext.model(for: itemID) as? ClipboardItem else {
            logger.warning("Could not find ClipboardItem for URL metadata fetch")
            return
        }

        // Check for duplicate: reuse metadata from a previous item with the same URL
        if reuseDuplicateMetadata(for: urlString, currentItem: item, modelContext: modelContext) {
            return
        }

        // Fetch metadata via LPMetadataProvider (created locally -- NOT Sendable)
        do {
            let metadata = try await fetchLinkMetadata(for: url)

            // Extract title
            item.urlTitle = metadata.title

            // Extract and save favicon
            if let iconProvider = metadata.iconProvider {
                if let iconData = await loadImageData(from: iconProvider) {
                    item.urlFaviconPath = await ImageStorageService.shared.saveFavicon(data: iconData)
                }
            }

            // Extract and save og:image
            if let imageProvider = metadata.imageProvider {
                if let imageData = await loadImageData(from: imageProvider) {
                    item.urlPreviewImagePath = await ImageStorageService.shared.savePreviewImage(data: imageData)
                }
            }

            item.urlMetadataFetched = true
            try modelContext.save()
            logger.info("Fetched URL metadata for \(urlString): title=\(metadata.title ?? "nil")")

        } catch {
            // Mark as failed so we don't retry endlessly
            item.urlMetadataFetched = false
            try? modelContext.save()
            logger.warning("URL metadata fetch failed for \(urlString): \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Check if the host is a private/local/loopback address.
    private static func isPrivateHost(_ host: String) -> Bool {
        // Exact matches
        let blockedHosts: Set<String> = ["localhost", "127.0.0.1", "[::1]"]
        if blockedHosts.contains(host) { return true }

        // IPv6 loopback without brackets
        if host == "::1" { return true }

        // IPv6 link-local (fe80::)
        if host.hasPrefix("fe80:") { return true }

        // Private IPv4 ranges
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            // 10.0.0.0/8
            if parts[0] == 10 { return true }
            // 192.168.0.0/16
            if parts[0] == 192 && parts[1] == 168 { return true }
            // 172.16.0.0/12 (172.16-31.x.x)
            if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        }

        return false
    }

    /// Reuse metadata from a previous ClipboardItem with the same URL text.
    ///
    /// Avoids redundant network calls when copying the same URL again.
    /// Returns true if metadata was reused, false otherwise.
    @MainActor
    private static func reuseDuplicateMetadata(
        for urlString: String,
        currentItem: ClipboardItem,
        modelContext: ModelContext
    ) -> Bool {
        let currentID = currentItem.persistentModelID

        // Query for another item with the same textContent and successful metadata
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.textContent == urlString &&
                item.urlMetadataFetched == true
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let results = try? modelContext.fetch(descriptor),
              let existing = results.first,
              existing.persistentModelID != currentID
        else { return false }

        // Copy metadata from existing item
        currentItem.urlTitle = existing.urlTitle
        currentItem.urlFaviconPath = existing.urlFaviconPath
        currentItem.urlPreviewImagePath = existing.urlPreviewImagePath
        currentItem.urlMetadataFetched = true
        try? modelContext.save()

        logger.info("Reused cached URL metadata for \(urlString)")
        return true
    }

    /// Fetch link metadata using LPMetadataProvider with a 5-second timeout.
    @MainActor
    private static func fetchLinkMetadata(for url: URL) async throws -> LPLinkMetadata {
        let provider = LPMetadataProvider()
        provider.timeout = 5.0
        return try await provider.startFetchingMetadata(for: url)
    }

    /// Load image data from an NSItemProvider using a continuation wrapper.
    @MainActor
    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            // Use loadDataRepresentation for the most general image type
            _ = provider.loadDataRepresentation(for: .image) { data, error in
                if let error {
                    logger.debug("Failed to load image from NSItemProvider: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
