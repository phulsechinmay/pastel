import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// Fetches URL page metadata (title, favicon, og:image) using URLSession + HTML parsing
/// and persists results to ClipboardItem fields via SwiftData.
///
/// Static service matching ColorDetectionService pattern. All SwiftData operations
/// run on @MainActor. URLSession uses ephemeral configuration with short timeouts.
struct URLMetadataService {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pastel.Pastel",
        category: "URLMetadataService"
    )

    // MARK: - URLSession Configuration

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        ]
        return URLSession(configuration: config)
    }()

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
    /// Handles duplicate reuse, URLSession HTML fetch with parsing, and
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

        // Fetch metadata via URLSession + HTML parsing
        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                item.urlMetadataFetched = false
                saveWithLogging(modelContext, operation: "URL metadata fetch")
                logger.warning("URL metadata fetch got non-success status for \(urlString)")
                return
            }

            guard let html = String(data: data, encoding: .utf8) else {
                item.urlMetadataFetched = false
                saveWithLogging(modelContext, operation: "URL metadata failure")
                logger.warning("URL metadata fetch could not decode HTML as UTF-8 for \(urlString)")
                return
            }

            let parsed = parseHTML(html, baseURL: url)

            // Set title
            item.urlTitle = parsed.title

            // Download and save favicon
            if let faviconURL = parsed.faviconURL {
                do {
                    let (faviconData, _) = try await session.data(from: faviconURL)
                    item.urlFaviconPath = await ImageStorageService.shared.saveFavicon(data: faviconData)
                } catch {
                    logger.warning("Favicon download failed for \(urlString): \(error.localizedDescription)")
                }
            }

            // Download and save og:image
            if let ogImageURL = parsed.ogImageURL {
                do {
                    let (imageData, _) = try await session.data(from: ogImageURL)
                    item.urlPreviewImagePath = await ImageStorageService.shared.savePreviewImage(data: imageData)
                } catch {
                    logger.warning("og:image download failed for \(urlString): \(error.localizedDescription)")
                }
            }

            item.urlMetadataFetched = true
            try modelContext.save()
            logger.info("Fetched URL metadata for \(urlString): title=\(parsed.title ?? "nil")")

        } catch {
            // Mark as failed so we don't retry endlessly
            item.urlMetadataFetched = false
            saveWithLogging(modelContext, operation: "URL metadata failure")
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
        saveWithLogging(modelContext, operation: "URL favicon save")

        logger.info("Reused cached URL metadata for \(urlString)")
        return true
    }

    /// Parse HTML to extract title, og:image URL, and favicon URL.
    ///
    /// Uses simple string operations for lightweight extraction. Handles common
    /// HTML patterns for meta tags and link tags.
    private static func parseHTML(_ html: String, baseURL: URL) -> (title: String?, ogImageURL: URL?, faviconURL: URL?) {
        let title = extractTitle(from: html)
        let ogImageURL = extractOGImage(from: html, baseURL: baseURL)
        let faviconURL = extractFavicon(from: html, baseURL: baseURL)
        return (title, ogImageURL, faviconURL)
    }

    // MARK: - HTML Parsing Helpers

    /// Extract the page title from <title>...</title> tags.
    private static func extractTitle(from html: String) -> String? {
        guard let openRange = html.range(of: "<title", options: .caseInsensitive) else {
            return nil
        }

        // Find the closing > of the opening tag (handles <title> and <title attr="...">)
        guard let tagCloseRange = html.range(of: ">", range: openRange.upperBound..<html.endIndex) else {
            return nil
        }

        guard let closeRange = html.range(of: "</title>", options: .caseInsensitive, range: tagCloseRange.upperBound..<html.endIndex) else {
            return nil
        }

        let rawTitle = String(html[tagCloseRange.upperBound..<closeRange.lowerBound])
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : decodeHTMLEntities(trimmed)
    }

    /// Extract og:image URL from <meta property="og:image" content="..."> tag.
    private static func extractOGImage(from html: String, baseURL: URL) -> URL? {
        // Search for meta tags with og:image property
        // Handles both attribute orders:
        //   <meta property="og:image" content="...">
        //   <meta content="..." property="og:image">
        let lowercased = html.lowercased()

        var searchStart = lowercased.startIndex
        while let metaRange = lowercased.range(of: "<meta ", options: .caseInsensitive, range: searchStart..<lowercased.endIndex) {
            guard let tagEnd = lowercased.range(of: ">", range: metaRange.upperBound..<lowercased.endIndex) else {
                break
            }

            let tagContent = String(html[metaRange.lowerBound..<tagEnd.upperBound])
            let tagContentLower = tagContent.lowercased()

            // Check if this meta tag has property="og:image"
            if tagContentLower.range(of: "property", options: .caseInsensitive) != nil &&
               tagContentLower.range(of: "og:image", options: .caseInsensitive) != nil {
                // Extract content attribute value
                if let contentValue = extractAttributeValue(from: tagContent, attribute: "content") {
                    if let resolved = resolveURL(contentValue, baseURL: baseURL) {
                        return resolved
                    }
                }
            }

            searchStart = tagEnd.upperBound
        }

        return nil
    }

    /// Extract favicon URL from <link rel="icon" href="..."> tags.
    private static func extractFavicon(from html: String, baseURL: URL) -> URL? {
        let lowercased = html.lowercased()

        var searchStart = lowercased.startIndex
        while let linkRange = lowercased.range(of: "<link ", options: .caseInsensitive, range: searchStart..<lowercased.endIndex) {
            guard let tagEnd = lowercased.range(of: ">", range: linkRange.upperBound..<lowercased.endIndex) else {
                break
            }

            let tagContent = String(html[linkRange.lowerBound..<tagEnd.upperBound])
            let tagContentLower = tagContent.lowercased()

            // Check if rel attribute contains "icon" (covers "icon", "shortcut icon", "apple-touch-icon")
            if let relValue = extractAttributeValue(from: tagContent, attribute: "rel") {
                if relValue.lowercased().contains("icon") {
                    if let hrefValue = extractAttributeValue(from: tagContent, attribute: "href") {
                        if let resolved = resolveURL(hrefValue, baseURL: baseURL) {
                            return resolved
                        }
                    }
                }
            }

            searchStart = tagEnd.upperBound
        }

        // Fallback: /favicon.ico
        if let scheme = baseURL.scheme, let host = baseURL.host {
            return URL(string: "\(scheme)://\(host)/favicon.ico")
        }

        return nil
    }

    /// Extract the value of an HTML attribute from a tag string.
    ///
    /// Handles both single and double quotes around attribute values.
    private static func extractAttributeValue(from tag: String, attribute: String) -> String? {
        // Look for attribute="value" or attribute='value'
        let patterns = ["\(attribute)=\"", "\(attribute)='"]
        let tagLower = tag.lowercased()

        for pattern in patterns {
            guard let attrRange = tagLower.range(of: pattern, options: .caseInsensitive) else {
                continue
            }

            let valueStart = tag.index(attrRange.upperBound, offsetBy: 0)
            let quote = pattern.last!
            guard let quoteEnd = tag.range(of: String(quote), range: valueStart..<tag.endIndex) else {
                continue
            }

            let value = String(tag[valueStart..<quoteEnd.lowerBound])
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    /// Resolve a URL string against a base URL.
    private static func resolveURL(_ urlString: String, baseURL: URL) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Absolute URL
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        // Relative URL -- resolve against base
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    /// Decode basic HTML entities in a string.
    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        return result
    }
}
