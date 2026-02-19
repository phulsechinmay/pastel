---
phase: quick
plan: 024
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Services/ImportExportService.swift
  - Pastel/Views/Settings/GeneralSettingsView.swift
autonomous: true
must_haves:
  truths:
    - "User can import a PastePal JSON export file via Settings > Data"
    - "PastePal collections become Pastel labels with mapped colors and emojis"
    - "PastePal items become Pastel ClipboardItem entries with correct content, timestamps, and label relationships"
    - "Duplicate items (by content hash) are skipped during import"
  artifacts:
    - path: "Pastel/Services/ImportExportService.swift"
      provides: "PastePal JSON decoding structs and importPastePalHistory method"
    - path: "Pastel/Views/Settings/GeneralSettingsView.swift"
      provides: "Import from PastePal button in Data section"
  key_links:
    - from: "Pastel/Views/Settings/GeneralSettingsView.swift"
      to: "ImportExportService.importPastePalHistory"
      via: "performPastePalImport() calling service method"
      pattern: "importPastePalHistory"
---

<objective>
Add PastePal import support to Pastel so users can migrate their clipboard history from PastePal.

Purpose: Enable migration from the PastePal clipboard manager by parsing its JSON export format, mapping collections to labels, and importing text items with deduplication.
Output: Working "Import from PastePal..." button in Settings that imports a PastePal JSON file.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Services/ImportExportService.swift
@Pastel/Views/Settings/GeneralSettingsView.swift
@Pastel/Models/Label.swift
@Pastel/Models/ClipboardItem.swift
@Pastel/Models/LabelColor.swift
@Pastel/Models/ContentType.swift
@PastePal-2026-02-19.json
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add PastePal import logic to ImportExportService</name>
  <files>Pastel/Services/ImportExportService.swift</files>
  <action>
Add PastePal-specific Codable structs and import method to ImportExportService.swift.

1. Add Codable structs for PastePal JSON format (add ABOVE the ImportExportService class):

```swift
// MARK: - PastePal Import Structs

struct PastePalExport: Codable, Sendable {
    let folders: [PastePalFolder]
    let items: [PastePalItem]
    // apps array exists but we don't need it
}

struct PastePalFolder: Codable, Sendable {
    let name: String
    let icon: String      // SF Symbol name like "calendar.badge.plus"
    let id: String        // UUID string
    let color: String     // "Green", "Red", "Teal", etc.
    let createdAt: Double // TimeInterval since reference date (Jan 1, 2001)
}

struct PastePalItem: Codable, Sendable {
    let id: String
    let createdAt: Double   // TimeInterval since reference date
    let string: String      // The actual clipboard content
    let collectionId: String? // Links to PastePalFolder.id (may be nil for uncategorized)
    let itemType: String    // "Rich Text" or "Text"
    let appBundleId: String?
    let appName: String?
    // pbType and appBundleUrl exist but we don't need them
}
```

2. Add a static mapping dictionary from PastePal SF Symbol icon names to emoji characters. Map these icons found in the export file:
   - "calendar.badge.plus" -> "📅"
   - "ice-cream" -> "🍦"
   - "atom" -> "⚛️"
   - "address-book" -> "📒"
   - "inbox" -> "📥"
   - "glass-martini" -> "🍸"
   - "sim-card" -> "💳"
   - "anchor" -> "⚓"
   Use a `[String: String]` dictionary so any unmapped icons gracefully fall back to nil (no emoji, just color dot).

3. Add a static mapping from PastePal color names (capitalized) to Pastel LabelColor raw values (lowercase). PastePal uses: "Green", "Red", "Teal", "Brown", "Blue", "Yellow", "Orange". Map directly to lowercase equivalents. For any unrecognized color, default to "blue".

4. Add `import CryptoKit` at the top of the file (needed for SHA256 content hash computation on imported items).

5. Add method to ImportExportService:

```swift
func importPastePalHistory(from data: Data, modelContext: ModelContext) throws -> ImportResult {
```

This method should:
- Set isProcessing/progress/progressMessage like the existing importHistory method
- Decode `data` as `PastePalExport` using a standard JSONDecoder (NO custom date strategy -- dates are raw Doubles)
- Wrap decode failure in ImportExportError.decodingFailed
- **Phase 1 - Label resolution (from folders):**
  - Fetch existing labels, build name->Label map
  - For each PastePalFolder: if label with that name doesn't exist, create a new Label with:
    - `name`: folder.name
    - `colorName`: mapped lowercase color (or "blue" default)
    - `sortOrder`: maxOrder + 1 + index
    - `emoji`: lookup from icon->emoji map (nil if unmapped)
  - Also build a `folderIdToLabel: [String: Label]` map for item wiring
  - Save after labels
- **Phase 2 - Item import:**
  - Pre-load existing content hashes into a Set for O(1) dedup
  - For each PastePalItem:
    - Compute SHA256 content hash from `item.string` (encode as UTF-8, hash, format as hex -- same pattern as ClipboardMonitor)
    - Skip if hash already exists
    - Create ClipboardItem with:
      - `textContent`: item.string
      - `contentType`: map itemType "Rich Text" -> .richText, "Text" -> .text, default .text
      - `timestamp`: `Date(timeIntervalSinceReferenceDate: item.createdAt)`
      - `sourceAppBundleID`: item.appBundleId
      - `sourceAppName`: item.appName
      - `characterCount`: item.string.count
      - `byteCount`: item.string.utf8.count
      - `changeCount`: 0
      - `isConcealed`: false
      - `contentHash`: computed hash
    - Wire label relationship: if item.collectionId is non-nil, look up in folderIdToLabel map, append to item.safeLabels
    - Insert into modelContext, add hash to existingHashes set
  - Batch save every 50 items with progress updates (same pattern as existing importHistory)
  - Final save, return ImportResult
  </action>
  <verify>Project builds: `cd /Users/phulsechinmay/Desktop/Projects/pastel && swift build 2>&1 | tail -5` shows success</verify>
  <done>ImportExportService has PastePal Codable structs, icon-to-emoji map, color map, and importPastePalHistory method that decodes PastePal JSON, creates labels from folders, imports items with dedup and label wiring</done>
</task>

<task type="auto">
  <name>Task 2: Add PastePal import button to Settings UI</name>
  <files>Pastel/Views/Settings/GeneralSettingsView.swift</files>
  <action>
Add a "Import from PastePal..." button to the Data section of GeneralSettingsView, next to the existing "Import..." button.

1. In the Data section HStack (line ~129-154), add a new button AFTER the existing "Import..." button and BEFORE "Clear All History...":

```swift
Button("Import from PastePal...") {
    performPastePalImport()
}
.disabled(importExportService.isProcessing)
```

2. Add the `performPastePalImport()` method (alongside existing performImport):

```swift
// MARK: - PastePal Import

private func performPastePalImport() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.title = "Import from PastePal"
    panel.message = "Select a PastePal JSON export file."

    let response = panel.runModal()
    guard response == .OK, let url = panel.url else { return }

    Task {
        do {
            let data = try Data(contentsOf: url)
            let result = try importExportService.importPastePalHistory(from: data, modelContext: modelContext)
            lastImportResult = result
            showingImportResult = true
        } catch {
            importErrorMessage = "PastePal import failed: \(error.localizedDescription)"
            showingImportError = true
        }
    }
}
```

Note: The `allowedContentTypes` uses `.json` (from UniformTypeIdentifiers, already imported) since PastePal exports as plain .json files. The existing alert dialogs for import result and import error are reused -- no new UI state needed.

3. Update the caption text (line ~165) to mention PastePal support:
   Change: `"Export saves text-based clipboard history to a .pastel file. Images are not included."`
   To: `"Export saves text-based clipboard history to a .pastel file. Images are not included. You can also import from PastePal JSON exports."`
  </action>
  <verify>Project builds: `cd /Users/phulsechinmay/Desktop/Projects/pastel && swift build 2>&1 | tail -5` shows success</verify>
  <done>"Import from PastePal..." button appears in Settings > Data section, opens a file picker for .json files, calls importPastePalHistory, and shows result/error via existing alerts</done>
</task>

</tasks>

<verification>
1. `swift build` succeeds with no errors
2. Launch app, open Settings > General, confirm "Import from PastePal..." button visible in Data section
3. Click "Import from PastePal...", select PastePal-2026-02-19.json from project root
4. Alert shows imported count (should be ~40 items) with labels created (should be 9 labels)
5. Check panel -- imported items appear with correct text content and label assignments
6. Re-import same file -- all items skipped as duplicates (0 imported, ~40 skipped)
</verification>

<success_criteria>
- PastePal JSON files can be imported via Settings
- Collections become Labels with correct names, colors, and emoji mappings
- Items have correct text content, timestamps, app source info, and label relationships
- Deduplication prevents double-importing the same data
- Existing Pastel import/export functionality is unaffected
</success_criteria>

<output>
After completion, create `.planning/quick/24-add-pastepal-import-option-to-pastel/024-SUMMARY.md`
</output>
