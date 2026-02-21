---
phase: 28-improve-export-import-ui
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Settings/ExportSheetView.swift
  - Pastel/Views/Settings/ImportSheetView.swift
  - Pastel/Views/Settings/GeneralSettingsView.swift
  - Pastel/Services/ImportExportService.swift
autonomous: true
must_haves:
  truths:
    - "Export sheet lets user select content types (text, code, URL, color, rich text, file) via checkboxes"
    - "Export sheet lets user select specific labels to filter by"
    - "Export sheet has optional 'Export data since' checkbox with time range dropdown (1 week, 1 month, 3 months, 1 year)"
    - "When 'Export data since' is unchecked, only items with selected labels are exported"
    - "Import modal lets user pick format (Pastel or PastePal) and select file"
    - "Import modal validates file format and shows error if format doesn't match selection"
  artifacts:
    - path: "Pastel/Views/Settings/ExportSheetView.swift"
      provides: "Export configuration sheet with type/label/date filters"
    - path: "Pastel/Views/Settings/ImportSheetView.swift"
      provides: "Import modal with format picker and file selection"
    - path: "Pastel/Services/ImportExportService.swift"
      provides: "Updated exportHistory with filtering parameters"
  key_links:
    - from: "ExportSheetView.swift"
      to: "ImportExportService.swift"
      via: "calls exportHistory with filter params"
    - from: "ImportSheetView.swift"
      to: "ImportExportService.swift"
      via: "calls importHistory or importPastePalHistory based on format"
    - from: "GeneralSettingsView.swift"
      to: "ExportSheetView.swift"
      via: ".sheet presentation on Export button"
    - from: "GeneralSettingsView.swift"
      to: "ImportSheetView.swift"
      via: ".sheet presentation on Import button"
---

<objective>
Replace the current bare Export/Import buttons in GeneralSettingsView with rich configuration sheets. Export gets a sheet with content type checkboxes, label multi-select, and optional date range filter. Import gets a modal with format picker (Pastel/PastePal), file picker, and format validation with error display.

Purpose: Give users granular control over what they export and a clearer import flow with format validation.
Output: Two new SwiftUI sheet views, updated ImportExportService with filtering, updated GeneralSettingsView wiring.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Settings/GeneralSettingsView.swift
@Pastel/Services/ImportExportService.swift
@Pastel/Models/ContentType.swift
@Pastel/Models/Label.swift
@Pastel/Models/ClipboardItem.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create ExportSheetView and update ImportExportService with filtering</name>
  <files>
    Pastel/Views/Settings/ExportSheetView.swift
    Pastel/Services/ImportExportService.swift
  </files>
  <action>
1. Create `ExportSheetView.swift` as a SwiftUI sheet view with these sections:

   **Content Types section:**
   - Title "Content Types" with `.headline` font
   - Grid/VStack of Toggle checkboxes for each ContentType case: Text, Rich Text, URL, Image, Code, Color, File
   - Use `ContentType.allCases` — display friendly names (e.g. "Rich Text" for `.richText`, "URLs" for `.url`)
   - All selected by default via `@State var selectedTypes: Set<ContentType>` initialized to `Set(ContentType.allCases)`
   - Note: Image export is already excluded in the service, but show the checkbox disabled/unchecked with a caption "(images not supported in export)"

   **Labels section:**
   - Title "Labels" with `.headline` font
   - Use `@Query(sort: \Label.sortOrder) var labels: [Label]`
   - Multi-select list of labels with checkboxes. Each row: label emoji/color dot + name + toggle
   - `@State var selectedLabelNames: Set<String>` — empty by default (meaning "all items" when date filter is on, or "no label filter" effectively)
   - Add "Select All" / "Deselect All" buttons

   **Date Filter section:**
   - Toggle checkbox: "Export data since" with `@State var filterByDate: Bool = false`
   - When enabled, show a Picker dropdown with options: "1 Week" (7), "1 Month" (30), "3 Months" (90), "1 Year" (365) — stored as `@State var exportSinceDays: Int = 30`
   - Caption explaining: "When unchecked, only items with selected labels are exported."

   **Footer:**
   - Cancel button (dismisses sheet)
   - "Export..." button that calls the export flow — opens NSSavePanel, then calls the updated `exportHistory`
   - Show progress bar and message when `importExportService.isProcessing`
   - Show result alert on success

   The view needs `@Environment(\.modelContext)`, `@Environment(\.dismiss)`, and `@State private var importExportService = ImportExportService()`.

2. Update `ImportExportService.exportHistory` to accept filter parameters:

   Change signature to:
   ```swift
   func exportHistory(
       modelContext: ModelContext,
       contentTypes: Set<ContentType>,
       labelNames: Set<String>,
       sinceDate: Date?
   ) throws -> Data
   ```

   Update the fetch predicate logic:
   - Filter by `contentTypes`: only include items whose contentType raw value is in the set. Since SwiftData `#Predicate` can't use `Set.contains`, build the predicate by checking each selected type with OR conditions. Use a helper approach: fetch all non-concealed items, then filter in-memory by contentType membership and label membership. This is simpler and avoids SwiftData predicate limitations.
   - Filter by `labelNames`: if non-empty, only include items that have at least one label whose name is in `labelNames`. Do this in-memory after fetch using `item.safeLabels.contains(where:)`.
   - Filter by `sinceDate`: if non-nil, only include items with `timestamp >= sinceDate`. This CAN be done in the predicate.
   - Always exclude concealed items (existing behavior).
   - Always exclude image items (existing behavior).

   Keep the old `exportHistory(modelContext:)` signature as a convenience that calls the new one with all types selected, empty labels, nil date.
  </action>
  <verify>
    Build with `cd /Users/phulsechinmay/Desktop/Projects/pastel && swift build 2>&1 | tail -5` — should compile without errors.
  </verify>
  <done>ExportSheetView renders with content type toggles, label multi-select, date filter toggle+picker, and Cancel/Export buttons. ImportExportService.exportHistory accepts and applies content type, label, and date filters.</done>
</task>

<task type="auto">
  <name>Task 2: Create ImportSheetView with format picker and validation</name>
  <files>
    Pastel/Views/Settings/ImportSheetView.swift
    Pastel/Services/ImportExportService.swift
  </files>
  <action>
1. Create `ImportSheetView.swift` as a SwiftUI sheet view:

   **Format Picker:**
   - Title "Import Clipboard History" as the sheet title
   - `@State var selectedFormat: ImportFormat = .pastel` where `ImportFormat` is a local enum with cases `.pastel` and `.pastePal`, with display names "Pastel (.pastel)" and "PastePal (.json)"
   - Use a `Picker` with `.segmented` style for the two options

   **File Selection:**
   - A row showing "Selected File: (none)" or the filename once picked
   - "Choose File..." button that opens NSOpenPanel
   - The allowed content types change based on format: `.pastelExport` for Pastel, `.json` for PastePal
   - `@State var selectedFileURL: URL?` and `@State var selectedFileName: String = ""`

   **Import Button + Error Display:**
   - "Import" button (disabled until file is selected, disabled while processing)
   - On tap: read file data, attempt decode based on selected format
   - If format is `.pastel`: try `importExportService.importHistory(from:modelContext:)`. If decoding fails, show error: "The selected file does not appear to be a valid Pastel export. Please check the file and try again."
   - If format is `.pastePal`: try `importExportService.importPastePalHistory(from:modelContext:)`. If decoding fails, show error: "The selected file does not appear to be a valid PastePal export. Please check the file and try again."
   - Show progress bar while processing
   - On success: show result (imported count, skipped count, labels created) and dismiss

   **Layout:**
   - Use `.padding(24)` and `.frame(minWidth: 400)`
   - Cancel and Import buttons in an HStack at the bottom, right-aligned
   - Error text shown in red below the buttons area if present (`@State var errorMessage: String?`)

2. Add `ImportExportError.invalidFormat(String)` case to the error enum in ImportExportService.swift for format mismatch errors, with a user-friendly error description.

   The view needs `@Environment(\.modelContext)`, `@Environment(\.dismiss)`.
  </action>
  <verify>
    Build with `cd /Users/phulsechinmay/Desktop/Projects/pastel && swift build 2>&1 | tail -5` — should compile without errors.
  </verify>
  <done>ImportSheetView renders with format segmented picker, file chooser button with filename display, Import/Cancel buttons, and shows validation errors when file format doesn't match selected format.</done>
</task>

<task type="auto">
  <name>Task 3: Wire sheets into GeneralSettingsView, remove old buttons</name>
  <files>
    Pastel/Views/Settings/GeneralSettingsView.swift
  </files>
  <action>
1. Replace the current Data section (section 7) in GeneralSettingsView:

   - Remove the `@State private var importExportService`, `showingExportSuccess`, `showingImportResult`, `showingImportError`, `exportedItemCount`, `lastImportResult`, `importErrorMessage` state variables — they move into the sheet views.

   - Add two new state variables:
     ```swift
     @State private var showingExportSheet = false
     @State private var showingImportSheet = false
     ```

   - Replace the "Export...", "Import...", "Import from PastePal..." buttons with just two buttons:
     - "Export..." sets `showingExportSheet = true`
     - "Import..." sets `showingImportSheet = true`

   - Keep the "Clear All History..." button and its confirmation alert as-is.

   - Remove the progress bar section (moved to sheets).

   - Update the caption text to: "Export saves clipboard history with filters. Import supports Pastel and PastePal formats."

   - Remove the three `.alert` modifiers for export success, import result, import error (moved to sheets).

   - Add `.sheet(isPresented: $showingExportSheet)` presenting `ExportSheetView()`.
   - Add `.sheet(isPresented: $showingImportSheet)` presenting `ImportSheetView()`.

   - Delete the `performExport()`, `performImport()`, `performPastePalImport()` private methods — logic moved to sheet views.

2. Ensure the sheet views receive the model context and AppState via environment (they inherit from the parent).
  </action>
  <verify>
    Build with `cd /Users/phulsechinmay/Desktop/Projects/pastel && swift build 2>&1 | tail -5` — should compile without errors. Open Settings > General and verify the Export/Import buttons are present and no old buttons remain.
  </verify>
  <done>GeneralSettingsView Data section shows two buttons (Export, Import) that open sheet modals. Old inline buttons, progress, and alerts removed. Clear History button unchanged.</done>
</task>

</tasks>

<verification>
- `swift build` compiles without errors
- Export sheet displays all content type checkboxes, label list, date filter
- Import sheet displays format picker, file chooser, import button
- Import shows error when file format mismatches selection
- Export respects type/label/date filters when generating .pastel file
</verification>

<success_criteria>
- Export button opens a sheet with content type, label, and date range filters
- Import button opens a modal with Pastel/PastePal format picker and file chooser
- Invalid import files show descriptive error messages
- All existing export/import functionality preserved (data format unchanged)
- App builds and runs without errors
</success_criteria>

<output>
After completion, create `.planning/quick/28-improve-export-import-ui-with-type-filte/28-SUMMARY.md`
</output>
