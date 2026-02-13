import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Custom UTType

extension UTType {
    static let pastelExport = UTType(exportedAs: "app.pastel.export")
}

// MARK: - Codable Transfer Structs

struct PastelExport: Codable, Sendable {
    let version: Int
    let exportDate: Date
    let items: [ExportedItem]
    let labels: [ExportedLabel]
}

struct ExportedItem: Codable, Sendable {
    let textContent: String?
    let htmlContent: String?
    let rtfData: Data?
    let contentType: String
    let timestamp: Date
    let sourceAppBundleID: String?
    let sourceAppName: String?
    let characterCount: Int
    let byteCount: Int
    let isConcealed: Bool
    let contentHash: String
    let title: String?
    let detectedLanguage: String?
    let detectedColorHex: String?
    let labelNames: [String]
}

struct ExportedLabel: Codable, Sendable {
    let name: String
    let colorName: String
    let sortOrder: Int
    let emoji: String?
}

struct ImportResult: Sendable {
    let importedCount: Int
    let skippedCount: Int
    let labelsCreated: Int
}

// MARK: - Import/Export Errors

enum ImportExportError: LocalizedError {
    case unsupportedVersion(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported export format version \(version). This file may have been created by a newer version of Pastel."
        case .decodingFailed(let detail):
            "Failed to read the export file: \(detail)"
        }
    }
}

// MARK: - ImportExportService

@MainActor
@Observable
final class ImportExportService {
    var isProcessing = false
    var progress: Double = 0.0
    var progressMessage = ""
    var lastExportCount = 0

    func exportHistory(modelContext: ModelContext) throws -> Data {
        isProcessing = true
        progress = 0.0
        progressMessage = "Preparing export..."

        defer {
            isProcessing = false
        }

        // Fetch non-concealed, non-image items
        let itemDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.isConcealed == false && item.contentType != "image"
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let items = try modelContext.fetch(itemDescriptor)
        lastExportCount = items.count

        // Fetch all labels
        let labelDescriptor = FetchDescriptor<Label>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let labels = try modelContext.fetch(labelDescriptor)

        progressMessage = "Exporting \(items.count) items..."
        progress = 0.3

        // Map to export structs
        let exportedItems = items.map { item in
            ExportedItem(
                textContent: item.textContent,
                htmlContent: item.htmlContent,
                rtfData: item.rtfData,
                contentType: item.contentType,
                timestamp: item.timestamp,
                sourceAppBundleID: item.sourceAppBundleID,
                sourceAppName: item.sourceAppName,
                characterCount: item.characterCount,
                byteCount: item.byteCount,
                isConcealed: item.isConcealed,
                contentHash: item.contentHash,
                title: item.title,
                detectedLanguage: item.detectedLanguage,
                detectedColorHex: item.detectedColorHex,
                labelNames: item.labels.map(\.name)
            )
        }

        let exportedLabels = labels.map { label in
            ExportedLabel(
                name: label.name,
                colorName: label.colorName,
                sortOrder: label.sortOrder,
                emoji: label.emoji
            )
        }

        progress = 0.6

        let export = PastelExport(
            version: 1,
            exportDate: .now,
            items: exportedItems,
            labels: exportedLabels
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(export)

        progress = 1.0
        progressMessage = "Exported \(items.count) items."

        return data
    }

    func importHistory(from data: Data, modelContext: ModelContext) throws -> ImportResult {
        isProcessing = true
        progress = 0.0
        progressMessage = "Reading export file..."

        defer {
            isProcessing = false
        }

        // Decode
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64

        let export: PastelExport
        do {
            export = try decoder.decode(PastelExport.self, from: data)
        } catch {
            throw ImportExportError.decodingFailed(error.localizedDescription)
        }

        // Version check
        guard export.version == 1 else {
            throw ImportExportError.unsupportedVersion(export.version)
        }

        // Phase 1: Label resolution
        progressMessage = "Resolving labels..."
        progress = 0.1

        var labelMap: [String: Label] = [:]
        let existingLabels = try modelContext.fetch(FetchDescriptor<Label>())
        for label in existingLabels {
            labelMap[label.name] = label
        }

        var labelsCreated = 0
        let maxOrder = existingLabels.map(\.sortOrder).max() ?? -1

        for (index, exportedLabel) in export.labels.enumerated() {
            if labelMap[exportedLabel.name] == nil {
                let newLabel = Label(
                    name: exportedLabel.name,
                    colorName: exportedLabel.colorName,
                    sortOrder: maxOrder + 1 + index,
                    emoji: exportedLabel.emoji
                )
                modelContext.insert(newLabel)
                labelMap[exportedLabel.name] = newLabel
                labelsCreated += 1
            }
        }
        try modelContext.save()

        // Phase 2: Item import with deduplication
        progressMessage = "Importing items..."
        progress = 0.2

        // Pre-load all existing content hashes for O(1) dedup lookups
        let allItemsDescriptor = FetchDescriptor<ClipboardItem>()
        let existingItems = try modelContext.fetch(allItemsDescriptor)
        var existingHashes = Set<String>(existingItems.map(\.contentHash))

        var importedCount = 0
        var skippedCount = 0
        let totalItems = export.items.count

        for (index, exportedItem) in export.items.enumerated() {
            // O(1) in-memory dedup check
            let hash = exportedItem.contentHash

            if existingHashes.contains(hash) {
                skippedCount += 1
            } else {
                let item = ClipboardItem(
                    textContent: exportedItem.textContent,
                    htmlContent: exportedItem.htmlContent,
                    rtfData: exportedItem.rtfData,
                    contentType: ContentType(rawValue: exportedItem.contentType) ?? .text,
                    timestamp: exportedItem.timestamp,
                    sourceAppBundleID: exportedItem.sourceAppBundleID,
                    sourceAppName: exportedItem.sourceAppName,
                    characterCount: exportedItem.characterCount,
                    byteCount: exportedItem.byteCount,
                    changeCount: 0,
                    isConcealed: exportedItem.isConcealed,
                    contentHash: exportedItem.contentHash
                )
                item.title = exportedItem.title
                item.detectedLanguage = exportedItem.detectedLanguage
                item.detectedColorHex = exportedItem.detectedColorHex

                // Wire label relationships
                for labelName in exportedItem.labelNames {
                    if let label = labelMap[labelName] {
                        item.labels.append(label)
                    }
                }

                modelContext.insert(item)
                existingHashes.insert(hash)
                importedCount += 1
            }

            // Batch save every 50 items
            if (index + 1) % 50 == 0 {
                try modelContext.save()
                let rawProgress = 0.2 + 0.8 * (Double(index + 1) / Double(totalItems))
                progress = rawProgress
                progressMessage = "Imported \(importedCount), skipped \(skippedCount)..."
            }
        }

        // Final save
        try modelContext.save()
        progress = 1.0
        progressMessage = "Imported \(importedCount), skipped \(skippedCount)."

        return ImportResult(
            importedCount: importedCount,
            skippedCount: skippedCount,
            labelsCreated: labelsCreated
        )
    }
}
