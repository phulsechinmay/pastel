# Phase 15: Import/Export - Research

**Researched:** 2026-02-09
**Domain:** Data portability -- JSON export/import of clipboard history with label relationships
**Confidence:** HIGH

## Summary

Phase 15 implements export and import of clipboard history via a custom `.pastel` file format (JSON). The codebase already has all the building blocks: ClipboardItem and Label SwiftData models with well-defined properties, a Settings window with tab-based navigation, and established patterns for SwiftData CRUD operations. The implementation requires three new components: (1) a Codable transfer model that mirrors ClipboardItem/Label but is decoupled from SwiftData, (2) an ImportExportService that handles serialization, deduplication, and batch insertion, and (3) a Settings UI section with export/import buttons and progress feedback.

The most critical technical concern is SwiftData's `@Attribute(.unique)` on `contentHash`. When a duplicate contentHash is inserted, SwiftData silently **upserts** (overwrites existing properties) rather than throwing an error. This means naive insertion of imported items would corrupt existing data. The STATE.md already flags this: "One-at-a-time insert for import (SwiftData @Attribute(.unique) constraint)." The solution is to pre-check existence via FetchDescriptor before each insert, skipping items whose contentHash already exists in the database.

The file format uses standard Swift `Codable` with `JSONEncoder`/`JSONDecoder`, ISO 8601 dates, and base64-encoded RTF data. Images are excluded per DATA-03. NSSavePanel/NSOpenPanel provide native file dialogs. No external dependencies are needed.

**Primary recommendation:** Build a standalone `ImportExportService` with Codable transfer structs, pre-check deduplication (do NOT rely on SwiftData's upsert), and use NSSavePanel/NSOpenPanel for file dialogs with a custom `.pastel` UTType.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation (JSONEncoder/JSONDecoder) | Built-in | JSON serialization | Swift standard library, zero dependencies |
| AppKit (NSSavePanel/NSOpenPanel) | Built-in | File save/open dialogs | Native macOS file dialogs, already used in codebase pattern |
| UniformTypeIdentifiers (UTType) | Built-in | Custom .pastel file type | Apple's modern type system, replaces deprecated allowedFileTypes |
| SwiftData | Built-in | Database read/write | Already the persistence layer |
| CryptoKit (SHA256) | Built-in | Content hash verification | Already used in ClipboardMonitor for hashing |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| OSLog (Logger) | Built-in | Structured logging | Import/export progress and error logging |
| SwiftUI (ProgressView) | Built-in | Progress feedback | Determinate progress bar during import/export |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSSavePanel/NSOpenPanel | SwiftUI .fileExporter/.fileImporter | fileExporter requires Transferable/FileDocument conformance, adds complexity; NSSavePanel is simpler for one-shot operations and matches existing codebase pattern (SettingsWindowController uses NSWindow directly) |
| JSON | Property list (plist) | JSON is human-readable, widely portable, and better for large datasets; plist is Apple-only |
| Manual Codable structs | Making SwiftData models Codable | SwiftData @Model classes have complex relationship/persistence state that makes direct Codable conformance fragile; separate transfer structs are cleaner |

**Installation:**
No additional packages needed. All libraries are built-in to macOS 14+.

## Architecture Patterns

### Recommended Project Structure
```
Pastel/
  Services/
    ImportExportService.swift    # Export/import logic, Codable structs, file I/O
  Views/Settings/
    GeneralSettingsView.swift    # Add Import/Export section to "Data" area (existing file)
```

Two files total: one new service, one modification to existing settings view.

### Pattern 1: Codable Transfer Structs (Decoupled from SwiftData)
**What:** Define lightweight Codable structs that mirror SwiftData models but carry no persistence state.
**When to use:** Always, for any SwiftData import/export scenario.
**Example:**
```swift
// Source: Standard Swift Codable pattern
struct PastelExport: Codable {
    let version: Int  // Format version for future compatibility
    let exportDate: Date
    let items: [ExportedItem]
    let labels: [ExportedLabel]
}

struct ExportedItem: Codable {
    let textContent: String?
    let htmlContent: String?
    let rtfData: Data?          // Base64 encoded by JSONEncoder
    let contentType: String     // Raw value of ContentType enum
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
    let labelNames: [String]    // Label names (not IDs) for portability
}

struct ExportedLabel: Codable {
    let name: String
    let colorName: String
    let sortOrder: Int
    let emoji: String?
}
```

### Pattern 2: Pre-Check Deduplication (NOT SwiftData Upsert)
**What:** Before inserting each imported item, check if its contentHash already exists in the database.
**When to use:** Always during import. SwiftData's @Attribute(.unique) performs silent upsert which would corrupt existing items.
**Example:**
```swift
// Source: Codebase pattern from ClipboardMonitor.isDuplicateOfMostRecent
func itemExists(contentHash: String, modelContext: ModelContext) -> Bool {
    let descriptor = FetchDescriptor<ClipboardItem>(
        predicate: #Predicate<ClipboardItem> { item in
            item.contentHash == contentHash
        }
    )
    return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
}
```

### Pattern 3: Batch Import with Periodic Saves
**What:** Insert items one at a time but save in batches (e.g., every 50 items) to balance memory and performance.
**When to use:** When importing more than a few dozen items.
**Example:**
```swift
// Source: HackingWithSwift SwiftData batch insert pattern
var importedCount = 0
var skippedCount = 0

for (index, exportedItem) in exportedItems.enumerated() {
    if itemExists(contentHash: exportedItem.contentHash, modelContext: modelContext) {
        skippedCount += 1
        continue
    }

    let item = ClipboardItem(/* from exportedItem */)
    // Resolve labels by name
    for labelName in exportedItem.labelNames {
        if let label = labelMap[labelName] {
            item.labels.append(label)
        }
    }
    modelContext.insert(item)
    importedCount += 1

    // Batch save every 50 items
    if (index + 1) % 50 == 0 {
        try modelContext.save()
    }
}
try modelContext.save()  // Final save for remainder
```

### Pattern 4: Label Resolution by Name
**What:** Export labels as name+color+emoji, import by matching on name. Create missing labels automatically.
**When to use:** Always during import. Label names are the user-facing identity; PersistentIdentifier is machine-specific.
**Example:**
```swift
// Build label lookup map from existing labels
var labelMap: [String: Label] = [:]
let existingLabels = try modelContext.fetch(FetchDescriptor<Label>())
for label in existingLabels {
    labelMap[label.name] = label
}

// Create missing labels from export data
for exportedLabel in exportData.labels {
    if labelMap[exportedLabel.name] == nil {
        let newLabel = Label(
            name: exportedLabel.name,
            colorName: exportedLabel.colorName,
            sortOrder: exportedLabel.sortOrder,
            emoji: exportedLabel.emoji
        )
        modelContext.insert(newLabel)
        labelMap[exportedLabel.name] = newLabel
    }
}
try modelContext.save()
```

### Pattern 5: NSSavePanel/NSOpenPanel File Dialogs
**What:** Use native AppKit file dialogs for save/open operations with custom UTType filtering.
**When to use:** For export (NSSavePanel) and import (NSOpenPanel) file selection.
**Example:**
```swift
// Source: AppKit documentation, matches codebase pattern
import UniformTypeIdentifiers

extension UTType {
    static let pastelExport = UTType(exportedAs: "app.pastel.export")
}

func showExportPanel() -> URL? {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pastelExport]
    panel.nameFieldStringValue = "Clipboard History.pastel"
    panel.title = "Export Clipboard History"
    panel.message = "Choose where to save your clipboard history."
    panel.canCreateDirectories = true
    let response = panel.runModal()
    return response == .OK ? panel.url : nil
}

func showImportPanel() -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.pastelExport]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.title = "Import Clipboard History"
    let response = panel.runModal()
    return response == .OK ? panel.url : nil
}
```

### Anti-Patterns to Avoid
- **Making @Model classes Codable directly:** SwiftData models carry persistence state (relationships, model context references). Encoding them directly is fragile and may serialize internal SwiftData metadata. Use separate transfer structs.
- **Relying on @Attribute(.unique) for deduplication during import:** SwiftData upserts silently on unique constraint collision, overwriting the existing item's properties with imported values. This corrupts existing data (e.g., overwrites user-edited titles, labels).
- **Inserting all items then saving once:** Memory usage will spike for large histories (thousands of items). Save in batches.
- **Using PersistentIdentifier in export format:** PersistentIdentifiers are machine-specific. Use contentHash for deduplication and label names for relationship resolution.
- **Exporting image data:** Per DATA-03, export is text-only. Image items should be excluded from the export, and imagePath/thumbnailPath should not be serialized.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON serialization | Custom JSON string building | JSONEncoder/JSONDecoder with Codable | Handles escaping, nested objects, date formatting, Data base64 encoding automatically |
| File save/open dialogs | Custom file browser view | NSSavePanel/NSOpenPanel | Native macOS UX, handles permissions, directory creation, file overwrite confirmation |
| Content hashing | Custom hash function | CryptoKit SHA256 | Already used in ClipboardMonitor, proven correct, hardware-accelerated |
| Date formatting | Manual ISO 8601 string formatting | JSONEncoder.dateEncodingStrategy = .iso8601 | Handles timezone, fractional seconds, edge cases |
| Binary data encoding | Manual base64 conversion | JSONEncoder.dataEncodingStrategy = .base64 | Automatic for any Data? properties in Codable structs |
| Progress tracking | Custom progress calculation | @Observable property + SwiftUI ProgressView | Reactive UI update, determinate progress bar built-in |

**Key insight:** The entire import/export pipeline uses zero external dependencies. Foundation's Codable system, AppKit's file panels, and SwiftData's query API provide everything needed.

## Common Pitfalls

### Pitfall 1: SwiftData Silent Upsert on Unique Constraint
**What goes wrong:** Inserting an imported item with a contentHash that already exists in the database silently overwrites the existing item's properties (title, labels, timestamp, etc.) instead of skipping it.
**Why it happens:** SwiftData's @Attribute(.unique) performs upsert, not insert-or-fail. This is by design but undocumented/unexpected.
**How to avoid:** Always check `itemExists(contentHash:)` via FetchDescriptor BEFORE calling `modelContext.insert()`. Skip the item and increment `skippedCount` if it exists.
**Warning signs:** After import, existing items lose their user-assigned titles or labels. Item count doesn't increase as expected.

### Pitfall 2: Label Relationship Integrity During Import
**What goes wrong:** Imported items reference labels by name, but if two labels have the same name with different colors/emoji, the import silently uses whichever one exists.
**Why it happens:** Label names are not unique in the data model (no @Attribute(.unique) on Label.name).
**How to avoid:** Match labels by name during import. If a label with the same name exists, use the existing one (preserving user's color/emoji customization). Only create new labels for names that don't exist at all.
**Warning signs:** Imported labels override existing label colors/emoji. Duplicate label names appear.

### Pitfall 3: Image Items in Export
**What goes wrong:** Exporting image items that reference on-disk files creates a broken export -- the .pastel file references filenames that don't exist on the importing machine.
**Why it happens:** Images are stored on disk (~/Library/Application Support/Pastel/images/), not in the database. The export format can't include arbitrary binary files.
**How to avoid:** Filter out image-type items during export (contentType == "image"). Per DATA-03, export is text-based only.
**Warning signs:** Imported items reference imagePath values that produce broken thumbnails.

### Pitfall 4: Memory Pressure During Large Import
**What goes wrong:** Importing thousands of items without periodic saves causes memory to balloon because SwiftData keeps all pending changes in memory.
**Why it happens:** SwiftData's ModelContext accumulates inserted objects until save() is called.
**How to avoid:** Save in batches (every 50 items). This commits objects to SQLite and allows SwiftData to release in-memory representations.
**Warning signs:** App becomes unresponsive or crashes during import of large files.

### Pitfall 5: Main Thread Blocking During Import
**What goes wrong:** Import/export runs on the main thread, freezing the UI during the operation.
**Why it happens:** SwiftData ModelContext operations must happen on the actor they were created on. The main ModelContext is @MainActor.
**How to avoid:** For export, JSON encoding can happen on a background thread (Codable structs are value types). The SwiftData fetch happens on main thread but is fast. For import, use main thread with periodic `try await Task.yield()` or process in small batches with async/await to keep UI responsive. The ProgressView updates between yields.
**Warning signs:** Spinning beach ball during import/export. ProgressView doesn't animate.

### Pitfall 6: UTType Registration for .pastel Extension
**What goes wrong:** The .pastel file extension is not recognized by macOS, so files show generic icons and double-clicking doesn't open the app.
**Why it happens:** Custom UTTypes must be declared in Info.plist under UTExportedTypeDeclarations.
**How to avoid:** Add UTExportedTypeDeclarations to Info.plist with the custom UTType identifier and .pastel extension. Also register under CFBundleDocumentTypes if you want file association (optional for Phase 15 -- file association is nice-to-have, not required).
**Warning signs:** Files show blank/generic icon. NSSavePanel doesn't append .pastel extension.

### Pitfall 7: Concealed Items in Export
**What goes wrong:** Exported file contains sensitive/concealed clipboard content (passwords from password managers).
**Why it happens:** Concealed items (isConcealed == true) are stored in the database until they expire.
**How to avoid:** Exclude concealed items from export (filter where isConcealed == false). Users should not accidentally export passwords.
**Warning signs:** Passwords appear in plaintext in exported .pastel files.

## Code Examples

### Export Flow
```swift
// Source: Standard Swift Codable + SwiftData query pattern
@MainActor
func exportHistory(modelContext: ModelContext) throws -> Data {
    // Fetch all non-concealed, non-image items
    let itemDescriptor = FetchDescriptor<ClipboardItem>(
        predicate: #Predicate<ClipboardItem> { item in
            item.isConcealed == false && item.contentType != "image"
        },
        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )
    let items = try modelContext.fetch(itemDescriptor)

    // Fetch all labels
    let labelDescriptor = FetchDescriptor<Label>(sortBy: [SortDescriptor(\.sortOrder)])
    let labels = try modelContext.fetch(labelDescriptor)

    // Convert to export structs
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

    let export = PastelExport(
        version: 1,
        exportDate: .now,
        items: exportedItems,
        labels: exportedLabels
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(export)
}
```

### Import Flow
```swift
// Source: Standard Swift Codable + SwiftData insert pattern
struct ImportResult {
    let importedCount: Int
    let skippedCount: Int
    let labelsCreated: Int
}

@MainActor
func importHistory(
    from data: Data,
    modelContext: ModelContext,
    onProgress: @escaping (Double) -> Void
) throws -> ImportResult {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let export = try decoder.decode(PastelExport.self, from: data)

    // 1. Resolve labels (create missing ones)
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

    // 2. Import items with deduplication
    var importedCount = 0
    var skippedCount = 0
    let totalItems = export.items.count

    for (index, exportedItem) in export.items.enumerated() {
        // Pre-check: skip if contentHash already exists
        let hash = exportedItem.contentHash
        let checkDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { item in
                item.contentHash == hash
            }
        )
        if (try? modelContext.fetchCount(checkDescriptor)) ?? 0 > 0 {
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
                contentHash: exportedItem.contentHash
            )
            item.title = exportedItem.title
            item.detectedLanguage = exportedItem.detectedLanguage
            item.detectedColorHex = exportedItem.detectedColorHex

            // Resolve label relationships
            for labelName in exportedItem.labelNames {
                if let label = labelMap[labelName] {
                    item.labels.append(label)
                }
            }

            modelContext.insert(item)
            importedCount += 1
        }

        // Batch save every 50 items
        if (index + 1) % 50 == 0 {
            try modelContext.save()
            onProgress(Double(index + 1) / Double(totalItems))
        }
    }
    try modelContext.save()
    onProgress(1.0)

    return ImportResult(
        importedCount: importedCount,
        skippedCount: skippedCount,
        labelsCreated: labelsCreated
    )
}
```

### Settings UI Section
```swift
// Source: Matches existing GeneralSettingsView pattern (Data section)
// Add to GeneralSettingsView body, in the existing "Data" section

VStack(alignment: .leading, spacing: 6) {
    HStack {
        Text("Data")
            .font(.headline)
        Spacer()
        Button("Export...") {
            performExport()
        }
        Button("Import...") {
            performImport()
        }
        Button("Clear All History...") {
            showingClearConfirmation = true
        }
        .foregroundStyle(.red)
    }

    // Progress bar (visible during import/export)
    if isProcessing {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress)
            Text(progressMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

### Info.plist UTType Declaration
```xml
<!-- Add to Pastel/Resources/Info.plist -->
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>app.pastel.export</string>
        <key>UTTypeDescription</key>
        <string>Pastel Clipboard History</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.json</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>pastel</string>
            </array>
        </dict>
    </dict>
</array>
```

### UTType Extension
```swift
import UniformTypeIdentifiers

extension UTType {
    static let pastelExport = UTType(exportedAs: "app.pastel.export")
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSSavePanel.allowedFileTypes (string array) | NSSavePanel.allowedContentTypes (UTType array) | macOS 12 / 2021 | Must use UTType, not string extensions |
| Manual JSON string building | JSONEncoder/JSONDecoder with Codable | Swift 4 / 2017 | Automatic type-safe serialization |
| CoreData NSManagedObject Codable conformance | Separate transfer structs for SwiftData | SwiftData launch 2023 | @Model classes should not conform to Codable directly |

**Deprecated/outdated:**
- `NSSavePanel.allowedFileTypes`: Deprecated in macOS 12. Use `allowedContentTypes` with `UTType`.
- `.fileExporter` with `FileDocument`: Works but requires boilerplate protocol conformance. NSSavePanel is simpler for one-shot export (not a document-based app).

## Open Questions

1. **Should concealed items be included in export?**
   - What we know: Concealed items are from password managers, auto-expire after 60 seconds
   - What's unclear: User expectation -- would they expect passwords in export?
   - Recommendation: Exclude concealed items from export (isConcealed == false filter). Security-first default.

2. **Should file-type items be included in export?**
   - What we know: File items store a file path (e.g., /Users/name/Documents/file.pdf). The path is machine-specific.
   - What's unclear: Whether file paths are useful on another machine.
   - Recommendation: Include file items. The path text is still useful as a reference, and the item's other metadata (labels, timestamp) has value. The import won't recreate the file, but the history entry is preserved.

3. **Format version migration**
   - What we know: The export format includes a `version` field.
   - What's unclear: How to handle future format changes.
   - Recommendation: Start at version 1. Decoder should check version and fail gracefully with a user-facing message if version is unsupported. This defers complexity until actually needed.

## Sources

### Primary (HIGH confidence)
- ClipboardItem.swift, Label.swift, ContentType.swift, LabelColor.swift -- Codebase data models
- ClipboardMonitor.swift -- Content hashing pattern (SHA256), @Attribute(.unique) on contentHash
- GeneralSettingsView.swift, SettingsView.swift -- Settings UI patterns
- AppState.swift -- Service architecture and ModelContext wiring

### Secondary (MEDIUM confidence)
- [HackingWithSwift - SwiftData unique attributes](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-make-unique-attributes-in-a-swiftdata-model) -- Confirmed upsert behavior on unique collision
- [HackingWithSwift - SwiftData batch insert](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-batch-insert-large-amounts-of-data-efficiently) -- Batch save pattern for memory management
- [SerialCoder.dev - Save and Open Panels](https://serialcoder.dev/text-tutorials/macos-tutorials/save-and-open-panels-in-swiftui-based-macos-apps/) -- NSSavePanel/NSOpenPanel usage pattern
- [Apple Developer Documentation - allowedContentTypes](https://developer.apple.com/documentation/appkit/nssavepanel/allowedcontenttypes) -- Modern UTType-based file filtering
- [Rhonabwy - Custom file types](https://rhonabwy.com/2023/07/22/getting-your-custom-file-type-recognized-by-ios-and-macos/) -- UTExportedTypeDeclarations in Info.plist
- [Apple Developer Documentation - UTType](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct) -- UTType API reference
- [Apple Developer Forums - SwiftData unique attribute disregard](https://developer.apple.com/forums/thread/756673) -- Confirmed silent upsert behavior

### Tertiary (LOW confidence)
- None. All findings verified with official docs or codebase inspection.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All built-in Apple frameworks, no external dependencies, patterns verified in codebase
- Architecture: HIGH -- Transfer struct pattern is well-established, codebase already uses identical SwiftData CRUD patterns
- Pitfalls: HIGH -- Critical upsert pitfall verified via multiple sources and confirmed by STATE.md research flag; all other pitfalls derived from direct codebase analysis
- File format: HIGH -- JSON with Codable is the standard Swift approach, ISO 8601 and base64 are built-in encoder strategies

**Research date:** 2026-02-09
**Valid until:** 2026-06-09 (stable -- all built-in frameworks, no external dependencies)
