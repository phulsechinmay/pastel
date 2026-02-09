# Project Research Summary

**Project:** Pastel v1.3 Power User Features
**Domain:** macOS Clipboard Manager Enhancement (paste-as-plain-text UI, app filtering, import/export, drag-and-drop)
**Researched:** 2026-02-09
**Confidence:** HIGH

## Executive Summary

Pastel v1.3 adds four power user features to the existing v1.0-v1.2 foundation: expanded paste-as-plain-text UI (context menu, Shift+Enter, Shift+double-click), app allow/ignore lists for privacy-conscious filtering, import/export for data portability, and drag-and-drop from the panel to external apps. Research reveals these features are **low-risk additions** that leverage existing infrastructure — PasteService already has complete plain-text paste support, ClipboardMonitor already captures source app metadata, SwiftData models are ready for Codable serialization, and the codebase already uses drag-and-drop patterns for label chips.

The recommended approach is **incremental enhancement** rather than new subsystems. All four features are architecturally independent and can be built in any order, but optimal sequencing is: (1) paste-as-plain-text UI first (lowest effort, immediate value), (2) app filtering second (privacy feature users want before importing large histories), (3) import/export third (most complex, benefits from prior phases as warm-up), (4) drag-and-drop last (highest uncertainty due to NSPanel interaction testing needs). Zero new third-party dependencies are required — all features use Apple first-party frameworks already in the project.

The critical risk is **NSPanel drag-and-drop feasibility** — SwiftUI's `.draggable()` modifier on a non-activating NSPanel has limited documentation. Early testing is mandatory before building the feature. Secondary risks include HTML formatting still appearing during "plain text paste" (existing bug to fix), drag operations triggering self-capture loops (extend `skipNextChange` to time-window), and import silently dropping duplicates (pre-check content hashes and report skipped items). All risks have clear mitigation strategies verified against the existing codebase and Maccy's open-source reference implementation.

## Key Findings

### Recommended Stack

**No new dependencies.** All v1.3 features use Apple first-party frameworks already in the project: UniformTypeIdentifiers (for UTType in drag operations and export file type declaration), Foundation Codable (for import/export JSON serialization), AppKit NSSavePanel/NSOpenPanel (for file dialogs), and NSWorkspace (for app discovery). The only NEW import is UniformTypeIdentifiers — all others are already imported.

**Core technologies for v1.3:**
- **UniformTypeIdentifiers** (macOS 11+): UTType for drag content representations and custom `.pastel` file type declaration — NEW import, well-documented, stable API
- **Foundation Codable**: JSON serialization for export format — already available, manual Codable conformance needed for SwiftData models
- **AppKit NSSavePanel/NSOpenPanel**: File dialogs for import/export — already used in existing codebase, straightforward integration
- **NSWorkspace.shared.runningApplications**: App discovery for filter settings UI — already used for source app capture, extend to picker UI
- **SwiftUI .onDrag + NSItemProvider**: Drag-and-drop implementation — pattern already proven in ChipBarView for label chips, extend to clipboard cards

**What NOT to add:**
- Transferable protocol (over-engineered for cross-app drag; NSItemProvider provides multiple representations more cleanly)
- FileDocument/ReferenceFileDocument (one-shot export doesn't need document lifecycle; NSSavePanel is simpler)
- Third-party JSON libraries (Swift Codable handles everything needed)
- Compression framework (not needed for v1.3; directory bundles are fine; defer to v2 if exports grow large)

### Expected Features

**Must have (table stakes):**
- Context menu "Paste as Plain Text" — every competitor with a context menu has this; users expect it
- Shift+Enter for plain text paste — natural modifier convention matching ecosystem patterns
- App ignore list in Settings — Paste, Maccy, CopyClip 2 all offer this; primary use case is blocking password managers
- Export clipboard history — data portability is a user right; users expect backup capability
- Import clipboard history — restore from backup completes the export story

**Should have (differentiators):**
- Shift+double-click for plain text paste — no competitor offers modifier-click for plain text; clean power user UX
- "Ignore [App Name]" from card context menu — no competitor offers in-context ignore; genuine UX innovation
- Allow list mode (monitor only specific apps) — no macOS clipboard manager offers dual-mode filtering; fails closed for security
- Drag-and-drop items to other apps — only premium managers support this; Maccy does not
- Extensible export format (versioned JSON) — future-proofs for cross-manager import and format evolution
- Import with duplicate detection via hash — smart merge, not blind append; prevents history pollution

**Defer (v2+):**
- iCloud sync (massive complexity: conflict resolution, storage costs, privacy concerns; Apple's Universal Clipboard handles basic cross-device)
- Import from other clipboard managers (each has different storage; define Pastel's format first, add importers later)
- Multi-item drag (confusing UX: order? concatenation?; SwiftUI multi-drag support limited)
- Encrypted export (key management complexity; users have FileVault; rely on macOS file security)

### Architecture Approach

**Feature-by-feature integration with existing services.** All changes are modifications to existing components or small new services that plug into AppState. No subsystem rewrites needed.

**Major components:**
1. **AppFilterService (NEW)** — @MainActor @Observable service that encapsulates allow/ignore list logic and UserDefaults persistence; checked by ClipboardMonitor.checkForChanges() before content processing
2. **ImportExportService (NEW)** — @MainActor service with Codable mapping structs (ExportDocument, ExportLabel, ExportItem); handles JSON serialization and batch SwiftData insert
3. **Modified ClipboardCardView** — add context menu "Paste as Plain Text" entry and .onDrag modifier with NSItemProvider construction per content type
4. **Modified FilteredCardListView** — Shift+Enter and Shift+double-click detection using keyPress.modifiers and NSEvent.modifierFlags
5. **Modified PasteService.writeToPasteboardPlainText** — fix existing bug: remove .html write, write ONLY .string type for true plain text
6. **AppFilterSettingsView (NEW)** — SwiftUI view for managing app lists with mode toggle, app picker via NSOpenPanel or NSWorkspace.shared.runningApplications

**Data flow:**
- App filtering check happens EARLY in ClipboardMonitor.checkForChanges() (before content processing) to avoid unnecessary work
- Plain text paste routes through existing PanelActions.pastePlainTextItem callback (same path as Cmd+Shift+1-9)
- Drag-and-drop uses SwiftUI .onDrag with NSItemProvider, writes to drag pasteboard (NOT NSPasteboard.general), avoids self-capture
- Import/export operates directly on SwiftData modelContext with batch inserts and individual saves for duplicate handling

### Critical Pitfalls

1. **writeToPasteboardPlainText still writes HTML, defeating plain text intent** — The existing method strips .rtf but keeps .html. Receiving apps (Pages, Notes, Google Docs) prefer HTML and render formatting. Users explicitly requested plain text but get rich text. **Fix:** Write ONLY .string type in writeToPasteboardPlainText. No .html, no .rtf. Test with Google Docs, Notes, Pages to verify zero formatting appears.

2. **Drag-and-drop from panel writes to NSPasteboard.general, triggering self-capture loop** — If drag implementation accidentally writes to .general, ClipboardMonitor detects changeCount and creates duplicate. Some receiving apps also copy dropped content to system clipboard. **Fix:** Use SwiftUI .draggable() which writes to drag pasteboard (NSDragPboard), NOT .general. Extend skipNextChange to time-window (skipChangesUntil: Date?) for 2 seconds after drag to handle receiving app's async clipboard write.

3. **App filtering checks frontmostApplication at capture time, not copy time** — NSPasteboard has no metadata about which app wrote to it. frontmostApplication returns the app with focus at poll time (up to 500ms after actual copy). User copies from ignored app, switches to another app — monitor sees wrong source app. **Accept as limitation:** Document it ("based on active app when detected; fast app-switching may cause misattribution"). Use allow-list mode for security-sensitive users (fails closed).

4. **Import overwrites existing items due to contentHash unique constraint collision** — SwiftData's @Attribute(.unique) on contentHash causes save() to throw for duplicates. modelContext.rollback() discards the failed insert. User imports 500 items, only 200 appear. **Fix:** Insert one item at a time with individual save() calls. Pre-check existing hashes into a Set. Count skipped duplicates and show import result: "Imported 200, skipped 300 duplicates."

5. **Drag-and-drop from non-activating NSPanel fails because panel cannot initiate drag session** — NSPanel with .nonactivatingPanel and canBecomeMain: false has restricted window server interaction. SwiftUI .draggable() may fail to initiate drag, or drag terminates when cursor leaves panel. **Test EARLY:** Create minimal test (single card with .draggable("test") in non-activating panel). Verify drag crosses panel boundary and drops into TextEdit. If fails, switch to AppKit NSDraggingSource protocol directly. Disable globalClickMonitor during drag to prevent panel dismiss mid-drag.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Paste-as-Plain-Text UI Expansion
**Rationale:** Lowest effort (all infrastructure exists), highest daily impact, zero dependencies on other v1.3 features. Pure UI wiring task with proven patterns. Immediate user value.

**Delivers:** Context menu "Paste as Plain Text", Shift+Enter keyboard shortcut, Shift+double-click mouse interaction — all routing through existing PasteService.pastePlainText.

**Addresses:**
- PAST-20 from features research (expand plain text paste entry points)
- Fixes Pitfall 1 (HTML formatting in plain text paste) as prerequisite

**Avoids:**
- Pitfall 6 (modifier key conflict) via keyPress.modifiers and NSEvent.modifierFlags patterns already proven in codebase

**Files modified:** ClipboardCardView.swift (~8 lines), FilteredCardListView.swift (~10 lines), PasteService.swift (bug fix: remove HTML write)

**Complexity:** LOW — ~25 lines across 3 files, no new components

### Phase 2: App Allow/Ignore Lists
**Rationale:** Independent of other features, moderate complexity (new service + settings view). Privacy feature users want before importing large histories. Early filter prevents capturing unwanted content before user builds large history.

**Delivers:** Allow-list or ignore-list of apps by bundle identifier, Settings UI with app picker, context menu "Ignore [App Name]" shortcut from cards, ClipboardMonitor filter check before content processing.

**Uses:**
- NSWorkspace.shared.runningApplications for app discovery
- NSWorkspace.shared.frontmostApplication for source app (already captured)
- UserDefaults for persistence (array of bundle IDs + mode string)

**Implements:**
- AppFilterService (NEW service, ~100 lines)
- AppFilterSettingsView (NEW view, ~150 lines)
- ClipboardMonitor filter check (~8 lines added)

**Avoids:**
- Pitfall 3 (frontmostApplication race condition) via documented limitation and allow-list mode option
- Pitfall 7 (bundle ID display) via app name + icon UI

**Complexity:** MEDIUM — ~200 lines across 4-5 files (2 new, 2-3 modified)

### Phase 3: Import/Export
**Rationale:** Independent of other features but most complex (Codable mapping, batch insert, image encoding). Benefits from app filtering being done first (export respects user preferences). Warm-up from two simpler phases helps with complexity.

**Delivers:** Export clipboard history to custom .pastel format (JSON manifest + directory bundle), import with duplicate detection and conflict resolution, Settings UI with NSSavePanel/NSOpenPanel integration.

**Uses:**
- Foundation Codable for JSON serialization
- UniformTypeIdentifiers for custom .pastel file type
- NSSavePanel/NSOpenPanel for file dialogs
- ImageStorageService for image Base64 encoding/decoding

**Implements:**
- ImportExportService (NEW service, ~400 lines)
- Export/Import UI in GeneralSettingsView (~30 lines)
- Codable conformance extensions for ClipboardItem and Label (~100 lines)

**Avoids:**
- Pitfall 4 (import hash collision) via one-at-a-time insert with individual saves
- Pitfall 8 (export versioning) via format version field in manifest
- Pitfall 10 (file paths in export) via Base64-embedded images or directory bundle with relative paths

**Complexity:** MEDIUM-HIGH — ~400 lines across 2-3 files (1 new service, 1-2 modified views)

### Phase 4: Drag-and-Drop from Panel
**Rationale:** Highest uncertainty (NSPanel + drag session interaction), potential gesture conflicts, requires manual testing. Least critical feature (users have copy+paste alternative). Benefits from paste-as-plain-text being done first (shares ClipboardCardView modifications).

**Delivers:** Drag clipboard cards from panel to external apps (text to TextEdit, images to Finder, URLs to Safari), drag preview with content snippet, NSItemProvider with multiple representations per content type.

**Uses:**
- SwiftUI .onDrag + NSItemProvider (pattern already proven in ChipBarView)
- UniformTypeIdentifiers for UTType references (public.plainText, public.png, public.url, public.fileURL)
- ImageStorageService for image file URLs

**Implements:**
- .onDrag modifier on ClipboardCardView (~40 lines)
- createItemProvider helper method with type-specific NSItemProvider construction (~50 lines)
- Potential PanelController globalClickMonitor suppression during drag (~5 lines if needed)

**Avoids:**
- Pitfall 2 (drag self-capture) via SwiftUI .draggable writing to drag pasteboard, not .general
- Pitfall 5 (NSPanel drag failure) via EARLY feasibility test before building feature
- Pitfall 9 (image drag disk loading) via NSItemProvider lazy file loading with thumbnail preview

**Critical first task:** Test .draggable() on non-activating NSPanel. If fails, pivot to AppKit NSDraggingSource.

**Complexity:** MEDIUM — ~80 lines across 1-2 files, high testing overhead

### Phase Ordering Rationale

- **Sequential build: 1 -> 2 -> 3 -> 4** is safest. Phases 1 and 2 touch different files and could parallel, but sequential keeps cognitive load low.
- **Paste-as-plain-text first** because it's the quickest win (infrastructure exists, pure wiring, immediate user value).
- **App filtering second** because users want privacy controls before importing large histories. Establishes the AppFilterService pattern before the more complex ImportExportService.
- **Import/export third** because it's the most implementation work but least time-sensitive (export/import happens once, not daily). Benefits from two simpler phases as warm-up.
- **Drag-and-drop last** because it has the highest uncertainty (NSPanel interaction) and requires the most manual testing. If it fails feasibility test, it can be deferred to v1.4 without blocking other features.
- **Dependency consideration:** Phase 4 modifies ClipboardCardView which Phase 1 also modifies, so Phase 4 must come after Phase 1. Phases 2 and 3 both modify AppState and GeneralSettingsView, so sequential is safer than parallel.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 4 (Drag-and-drop):** NSPanel drag session behavior is under-documented. Feasibility test MUST be first task in phase plan. If .draggable() fails on NSPanel, research AppKit NSDraggingSource protocol as fallback. Research flag: TEST_EARLY.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Paste-as-plain-text):** Proven patterns (modifier key detection already in codebase), straightforward SwiftUI, no unknowns.
- **Phase 2 (App filtering):** Maccy open-source provides reference implementation, NSWorkspace API well-documented, standard Settings UI.
- **Phase 3 (Import/export):** Standard Codable + NSSavePanel patterns, well-documented, no novel integration points.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs verified in Apple docs or already used in codebase. Zero new third-party dependencies. UniformTypeIdentifiers only NEW import. |
| Features | HIGH | Paste-as-plain-text and app filtering are table stakes (verified across Paste, Maccy, PastePal). Drag-and-drop is differentiator (verified in Pasta, PasteNow). Export/import has no ecosystem standard but user expectation is clear. |
| Architecture | HIGH | All integration points verified via direct source code analysis of 50+ Swift files. Patterns already established (PanelActions callbacks, @AppStorage, @Observable services, dynamic @Query). No subsystem rewrites. |
| Pitfalls | MEDIUM-HIGH | Critical pitfalls verified against existing code (Pitfall 1: PasteService.swift line 218-240, Pitfall 3: ClipboardMonitor.swift line 223). NSPanel drag interaction (Pitfall 5) based on developer reports, not firsthand testing — needs validation. |

**Overall confidence:** HIGH

### Gaps to Address

**NSPanel drag-and-drop feasibility (Pitfall 5):**
- Gap: SwiftUI .draggable() on non-activating NSPanel is under-documented. Unknown if drag session initiates correctly, if drag preview appears, if drop completes successfully.
- How to handle: MANDATORY feasibility test at start of Phase 4 plan. Create minimal reproduction (single card with .draggable("test") in SlidingPanel). Test drag to TextEdit. If fails, pivot to AppKit NSDraggingSource protocol. DO NOT build full feature before validating approach.

**App filtering race condition (Pitfall 3):**
- Gap: NSPasteboard has no API to identify source app. frontmostApplication check is best-effort but has timing window. Maccy has same limitation.
- How to handle: Accept as documented limitation. Use allow-list mode for security-sensitive users (fails closed). In UI, show disclaimer: "App filtering is based on the active app when the copy is detected."

**Image drag performance (Pitfall 9):**
- Gap: Large images (4K screenshots, 2-5MB) loaded from disk synchronously could freeze UI during drag initiation.
- How to handle: Use thumbnail for drag preview (small, fast). Full image data loaded via NSItemProvider lazy callback (async, system-managed). Test with 5MB image to verify no freeze.

**Export format evolution (Pitfall 8):**
- Gap: First version of export format sets precedent for all future imports. Schema changes must be backward-compatible.
- How to handle: Include "version": 1 in manifest. Use Codable with explicit CodingKeys and default values for all fields. Never remove/rename fields, only add optional fields. Test import of v1 export after every model change.

## Sources

### Primary (HIGH confidence)
- Direct source code analysis: all 50+ Swift files in Pastel codebase (AppState, ClipboardMonitor, PasteService, PanelController, FilteredCardListView, ClipboardCardView, ClipboardItem, SlidingPanel, ImageStorageService, etc.)
- [Maccy clipboard manager — app filtering implementation](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift) — open-source reference for allow/ignore list pattern
- [NSItemProvider — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nsitemprovider)
- [NSWorkspace — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsworkspace)
- [UTType — Apple Developer Documentation](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct)
- [Defining file and data types — Apple Developer Documentation](https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app)

### Secondary (MEDIUM confidence)
- [SwiftUI drag and drop on macOS — Eclectic Light](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/) — NSItemProvider patterns, background thread gotchas
- [onDrag conflicts with clicks on macOS — Hacking with Swift Forums](https://www.hackingwithswift.com/forums/swiftui/ondrag-conflicts-with-clicks-on-macos/8020) — gesture conflict documentation
- [Making SwiftData models Codable — Donny Wals](https://www.donnywals.com/making-your-swiftdata-models-codable/)
- [NSPanel nonactivating style mask blog](https://philz.blog/nspanel-nonactivating-style-mask-flag/) — window server behavior analysis
- [Paste Help Center](https://pasteapp.io/help/paste-on-mac) — paste-as-plain-text UX patterns
- [Maccy issue #79](https://github.com/p0deje/Maccy/issues/79) — community discussion on app-specific filtering
- [Maccy issue #1072](https://github.com/p0deje/Maccy/issues/1072) — frontmostApplication vs actual clipboard source limitation

### Tertiary (LOW confidence)
- [NSTextView plain text pasteboard handling — Christian Tietze](https://christiantietze.de/posts/2022/09/nstextview-plain-text-pasteboard-string-not-included/) — pasteboard type priority behavior

---
*Research completed: 2026-02-09*
*Ready for roadmap: yes*
