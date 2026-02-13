# Phase 18: Codebase Audit -- Anti-patterns, Performance, and Security (Encryption) - Research

**Researched:** 2026-02-12
**Domain:** Swift/SwiftUI codebase quality, SwiftData performance, macOS clipboard security
**Confidence:** HIGH (codebase findings), MEDIUM (security recommendations)

## Summary

This research covers three domains: codebase anti-patterns, performance optimization opportunities, and security posture assessment (including encryption). The codebase is generally well-structured with good separation of concerns, consistent `@MainActor` isolation, and proper `[weak self]` usage in closures. However, the audit uncovered several concrete issues: force unwraps that could crash, duplicated CGEvent paste simulation code, silent `try?` error swallowing in 17 locations, a redundant `@Query` for labels in every card view, and an `#Predicate { _ in true }` that fetches all items when no search is active.

On security: the REQUIREMENTS.md decision to keep encryption OUT OF SCOPE is well-justified. FileVault (enabled by default on Apple Silicon Macs) encrypts all data at rest. The App Sandbox prevents other sandboxed apps from accessing Pastel's container. The existing privacy measures (ConcealedType respect, 60-second auto-expiration, app ignore list, concealed/image exclusion from export) are stronger than most competing clipboard managers. Adding application-level encryption would impose search performance penalties and add complexity without meaningfully increasing security beyond what FileVault already provides.

**Primary recommendation:** Fix the concrete anti-patterns (force unwraps, duplicated code, silent error swallowing), optimize the hot-path performance issues (redundant queries, ForEach enumeration), and harden the remaining security surface (export file sensitivity, image directory permissions) -- but do NOT add application-level encryption.

## Architecture Patterns

### Current Project Structure
```
Pastel/
├── App/                 # AppState (central coordinator)
├── Extensions/          # NSPasteboard+Reading, NSImage+Thumbnail, etc.
├── Models/              # SwiftData @Model (ClipboardItem, Label)
├── Services/            # Business logic (ClipboardMonitor, PasteService, etc.)
├── Views/
│   ├── MenuBar/         # StatusPopoverView
│   ├── Onboarding/      # First-launch flow
│   ├── Panel/           # Sliding panel (PanelController, cards, search, chips)
│   └── Settings/        # Settings tabs (General, Labels, Privacy, History)
├── Resources/           # Entitlements, assets
└── PastelApp.swift      # @main entry point
```

### Pattern: Callback Chain (not NotificationCenter)
**What:** State propagation uses explicit callback closures wired in `AppState.setupPanel()`.
**Example:** `panelController.onPasteItem -> AppState.paste -> PasteService.paste`
**Assessment:** This is a good pattern -- explicit, traceable, no stringly-typed notifications.

### Pattern: Init-based @Query for Dynamic Filtering
**What:** `FilteredCardListView` and `HistoryGridView` construct `@Query` predicates at init time. Parent views force recreation via `.id()` modifier when filters change.
**Assessment:** Correct pattern for SwiftData. `@Query` predicates cannot change after view creation. The `.id()` trick is the standard workaround.

### Pattern: In-Memory Label Filtering
**What:** Label filtering done as post-filter on `@Query` results because `#Predicate` cannot use `.contains()` on to-many relationships.
**Assessment:** Correct workaround for a known SwiftData limitation. Performance acceptable for typical clipboard history sizes (<10K items).

## Anti-Patterns Found

### CRITICAL: Force Unwraps (Crash Risk)

| File | Line | Code | Risk |
|------|------|------|------|
| `ImageStorageService.swift` | 46 | `.first!` on `applicationSupportDirectory` | LOW -- system dir always exists, but defensive coding preferred |
| `PanelContentView.swift` | 199 | `labelIDs.first!` | LOW -- guarded by `!labels.isEmpty`, but still a force unwrap |
| `PersistentIdentifier+Transfer.swift` | 7-8 | `try!` JSONEncoder + `.utf8!` | MEDIUM -- encoding a PersistentIdentifier can fail if the type is not Codable in future SwiftData versions |
| `PastelApp.swift` | 15 | `fatalError()` on ModelContainer creation | Acceptable -- app cannot function without a database |

**Recommendation:** Replace force unwraps with safe alternatives. The `PersistentIdentifier+Transfer` `try!` is the most concerning because it will crash if encoding fails, and the calling context (drag-and-drop) should gracefully degrade instead.

### HIGH: Duplicated CGEvent Paste Simulation

`PasteService.simulatePaste()` contains the canonical implementation of CGEvent Cmd+V simulation. However, `HistoryBrowserView.bulkPaste()` (lines 144-153) duplicates this exact logic inline instead of calling `PasteService.simulatePaste()`.

**Impact:** If the paste simulation needs to change (e.g., adding key suppression flags, changing delay), the duplicate in HistoryBrowserView would be missed.

**Recommendation:** Extract to a shared utility or expose `PasteService.simulatePaste()` as a static public method and call it from HistoryBrowserView.

### HIGH: Silent Error Swallowing (17 occurrences of `try? modelContext.save()`)

17 call sites use `try? modelContext.save()` which silently discard errors:

| File | Count | Context |
|------|-------|---------|
| `MigrationService.swift` | 1 | Label migration |
| `URLMetadataService.swift` | 4 | Metadata fetch results |
| `ClipboardCardView.swift` | 3 | Label toggle, delete |
| `ChipBarView.swift` | 1 | Label reorder |
| `FilteredCardListView.swift` | 2 | Label drop assignment |
| `HistoryBrowserView.swift` | 1 | Bulk delete |
| `LabelSettingsView.swift` | 5 | Label CRUD |

**Impact:** Save failures (e.g., unique constraint violations, disk full) are silently lost. The user sees no feedback that their action failed.

**Recommendation:**
- For services (ClipboardMonitor, RetentionService, ExpirationService): already use `do/catch` with logging -- this is correct.
- For views: add a shared error handler that at minimum logs the error. Consider a toast/banner for user-visible operations like label assignment.

### MEDIUM: Redundant @Query for Labels in ClipboardCardView

`ClipboardCardView` declares `@Query(sort: \Label.sortOrder) private var labels: [Label]` (line 21) to populate the context menu label submenu. Since `ClipboardCardView` is rendered once per visible card in `FilteredCardListView`, this means **every visible card creates its own independent @Query observer for all labels**.

**Impact:** SwiftData creates N separate query subscriptions (one per visible card) all monitoring the same Label table. On a panel showing 10-15 cards, that is 10-15 redundant queries.

**Recommendation:** Pass labels as a parameter from the parent (`FilteredCardListView` or `PanelContentView`, which already has `@Query` for labels). This eliminates N-1 redundant subscriptions.

### MEDIUM: `#Predicate { _ in true }` Fetches All Items

When search text is empty, both `FilteredCardListView` and `HistoryGridView` create:
```swift
predicate = #Predicate<ClipboardItem> { _ in true }
```

This generates a SQLite query with no WHERE clause, fetching **all** clipboard items into memory. For a user with 10,000+ items, this loads everything on every panel open.

**Impact:** Memory spike on panel open for power users with large histories.

**Recommendation:** Consider using `FetchDescriptor.fetchLimit` to cap initial load (e.g., 200 items) with "load more" pagination. Alternatively, accept this as a known limitation given the in-memory label filtering requirement.

### MEDIUM: FilteredCardListView Body Duplication

The horizontal and vertical layout branches in `FilteredCardListView.body` (lines 110-228) duplicate nearly identical `ForEach` + card rendering logic (~60 lines each). The only differences are:
- `ScrollView(.horizontal)` vs `ScrollView()`
- `LazyHStack` vs `LazyVStack`
- `.frame(width: 260, height: 195)` on horizontal cards

**Recommendation:** Extract the common card rendering into a `@ViewBuilder` helper or a reusable `CardForEach` component.

### LOW: Debug Logging Left in Production Code

`PanelController.show()` contains debug timing logs (lines 221-226):
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
    self?.logger.info("200ms later: isActive=\(NSApp.isActive), panel.isKey=\(panel.isKeyWindow)")
}
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
    self?.logger.info("500ms later: isActive=\(NSApp.isActive), panel.isKey=\(panel.isKeyWindow)")
}
```

Also, the temporary `DistributedNotificationCenter` observer in `AppState.setupPanel()` (lines 92-101) has a comment "TEMPORARY: Remove after liquid glass fix is verified."

**Recommendation:** Remove debug timing logs and the temporary notification observer.

### LOW: `MainActor.assumeIsolated` Usage

`AppState.swift` line 98 uses `MainActor.assumeIsolated` inside a DistributedNotificationCenter callback:
```swift
MainActor.assumeIsolated {
    self?.togglePanel()
}
```

This is safe in this context (queue is `.main`), but `MainActor.assumeIsolated` crashes at runtime if called from a non-main thread. A safer pattern is `Task { @MainActor in ... }` which is already used elsewhere.

### LOW: NSImage.lockFocus Deprecated Pattern

`ClipboardCardView.menuIcon(for:)` uses `NSImage.lockFocus()` / `unlockFocus()` for menu icon rendering. This API is deprecated since macOS 12.

**Recommendation:** Replace with `NSImage(size:flipped:drawingHandler:)` which is the modern equivalent.

## Performance Analysis

### Polling Efficiency (0.5s Timer)

The 0.5-second polling interval with 0.1s tolerance is a good balance:
- **0.5s** is the industry standard for clipboard managers (Maccy uses the same)
- **0.1s tolerance** allows the system to coalesce timer fires for energy efficiency
- `NSPasteboard.changeCount` comparison is O(1) -- the fast path (no change) is effectively free
- Wake notification handler (`NSWorkspace.didWakeNotification`) catches changes during sleep

**Assessment:** No optimization needed.

### Image Storage (Background Queue)

`ImageStorageService` uses a dedicated serial `DispatchQueue(qos: .utility)` for all disk I/O. Pasteboard data is correctly read on the main thread (NSPasteboard is not thread-safe) then handed off to the background queue. The completion handler dispatches back to main thread.

`AsyncThumbnailView` loads thumbnails on `DispatchQueue.global(qos: .userInitiated)` -- appropriate since it is user-visible content.

**Assessment:** Correct architecture. No main-thread blocking for image I/O.

### SwiftData Query Patterns

| Query | Location | Assessment |
|-------|----------|------------|
| `@Query(sort: \Label.sortOrder)` | PanelContentView, ClipboardCardView, HistoryBrowserView, EditItemView, LabelSettingsView | **5 separate subscriptions** for the same Label table; ClipboardCardView is multiplied per-card |
| `@Query(filter: predicate, sort: \ClipboardItem.timestamp, order: .reverse)` | FilteredCardListView, HistoryGridView | Dynamic predicate, correct pattern |
| `FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])` with `fetchLimit: 1` | ClipboardMonitor.isDuplicateOfMostRecent | Efficient -- fetches only 1 row |
| `FetchDescriptor<ClipboardItem>()` (no limit) | ClipboardMonitor.init, MigrationService, AppState.clearAllHistory | Full table scan -- acceptable for init/migration/clear |
| `#Predicate { item.contentHash == hash }` | ImportExportService import dedup | Per-item query during import; could be batch-optimized |

**Key optimization opportunity:** The per-item hash lookup during import (`importHistory`) runs a separate SwiftData query for every imported item. For large imports (1000+ items), this is O(n) database queries. Pre-loading all content hashes into a `Set<String>` would reduce this to a single query + O(n) in-memory lookups.

### View Body Recomputation

The `.id()` modifier on `FilteredCardListView`:
```swift
.id("\(debouncedSearchText)\(selectedLabelIDs...)\(appState.itemCount)")
```

This destroys and recreates the entire `FilteredCardListView` (and all its cards) whenever `itemCount` changes -- which happens **every time a new clipboard item is captured**. If the panel is open while the user is copying, the entire card list is rebuilt from scratch.

**Impact:** Visible jank if the user is scrolling the panel while new items arrive.

**Recommendation:** Remove `appState.itemCount` from the `.id()` string. SwiftData's `@Query` already automatically updates when items are added/deleted. The `itemCount` in the `.id()` forces a unnecessary full rebuild.

### `ForEach(Array(filteredItems.enumerated()), id: \.element.id)`

Both `FilteredCardListView` and `HistoryGridView` use `Array(filteredItems.enumerated())` which:
1. Creates a full copy of the array
2. Wraps each element in an `EnumeratedSequence.Element`
3. Uses `.element.id` as the identity

This is done to access the index for selection tracking and badge numbering.

**Impact:** For typical list sizes (<500 items), the overhead is negligible. For 10,000+ items, the array copy adds memory pressure.

**Recommendation:** Low priority. Consider using the item's `persistentModelID` for selection instead of integer indices, which would eliminate the need for enumeration.

## Security Assessment

### Current Security Measures (Already Implemented)

| Measure | Implementation | Effectiveness |
|---------|---------------|---------------|
| App Sandbox | Entitlements: `app-sandbox`, `network.client`, `files.user-selected.read-write` | HIGH -- prevents unauthorized file system access |
| ConcealedType respect | `NSPasteboard.PasteboardType.concealed` detection in `classifyContent()` | HIGH -- password manager content flagged |
| Auto-expiration | `ExpirationService`: 60-second timer for concealed items | HIGH -- passwords auto-deleted |
| Overdue cleanup | `expireOverdueItems()` on launch | HIGH -- catches items expired during app quit |
| App ignore list | `UserDefaults.ignoredAppBundleIDs` checked in `checkForChanges()` | HIGH -- privacy for banking apps etc. |
| TransientType skip | `org.nspasteboard.TransientType` skipped entirely | HIGH -- auto-fill content not captured |
| Export exclusions | Concealed and image items excluded from `.pastel` export (Phase 15 decision) | HIGH -- no passwords or screenshots in export files |
| Private IP filtering | `URLMetadataService.isPrivateHost()` blocks localhost, 10.x, 192.168.x, etc. | MEDIUM -- prevents metadata fetch to local services |
| LSUIElement | No Dock icon or Cmd+Tab entry | LOW security, but reduces visibility |

### Threat Model

| Threat | Protection | Gap? |
|--------|-----------|------|
| Unauthorized app reading clipboard | macOS clipboard is globally accessible -- no protection possible | Known OS limitation |
| Malware reading SwiftData store | FileVault encrypts at rest; App Sandbox (macOS 14+) protects container from sandboxed apps | Non-sandboxed malware with FDA can still read |
| Physical device theft (powered off) | FileVault XTS-AES-128 encryption | No gap if FileVault enabled |
| Physical device theft (unlocked) | No protection | Encryption would not help either -- device is unlocked |
| Time Machine backup exposure | Not encrypted by Pastel; relies on TM encryption | Gap: user may not encrypt backups |
| Export file left on disk | `.pastel` JSON file contains clipboard text in plaintext | MEDIUM gap: export files should be treated as sensitive |
| Image files on disk | Stored in `~/Library/Application Support/Pastel/images/` | LOW gap: protected by sandbox + FileVault |

### Encryption Assessment: Should We Add It?

**REQUIREMENTS.md states:** "Encrypted clipboard history" is OUT OF SCOPE with rationale: "Degrades search performance, false sense of security. Offer clear history instead."

**After thorough research, the REQUIREMENTS.md position is correct.** Here is the detailed analysis:

#### What encryption would protect against:
1. Someone reading the SQLite database file directly (requires bypassing App Sandbox + FileVault)
2. Time Machine backups containing unencrypted clipboard text
3. Non-sandboxed apps with Full Disk Access reading the store

#### What encryption would NOT protect against:
1. The clipboard itself (globally readable by all apps -- this is the real exposure surface)
2. An unlocked device (encryption keys are in memory)
3. The user's own password manager workflow (already handled by ConcealedType)
4. An attacker with root/admin access (can read Keychain, defeat any app-level encryption)

#### Performance cost:
- **SQLCipher** (full database encryption): ~5-15% overhead on all queries. Incompatible with SwiftData's `ModelContainer` without dropping to Core Data + custom store.
- **Property-level encryption** (encrypt `textContent` before storing): Breaks `#Predicate` text search entirely. Would need to decrypt all items into memory for search, defeating the purpose of lazy loading.
- **File-level protection** (`NSFileProtectionComplete`): Locks the database when the device is locked. On macOS, FileVault already provides equivalent protection. Adding this breaks background clipboard capture while the screen is locked.

#### What other clipboard managers do:

| App | Encrypts data? | Approach |
|-----|----------------|----------|
| **Maccy** (open source) | No | Relies on macOS security. Encryption requested in [GitHub issue #151](https://github.com/p0deje/Maccy/issues/151), closed without implementation. Developer asked "What are the benefits over standard macOS disk encryption?" |
| **Paste** (commercial) | No (local) / Yes (iCloud sync) | Stores locally in SQLite, relies on device encryption for at-rest protection |
| **SaneClip** (commercial) | Yes | AES-256 with Keychain-stored keys, Touch ID lock. Niche differentiator, not industry standard |
| **CopyClip / Clipy** | No | Standard local storage |
| **Planck** (commercial) | Yes (sync only) | AES-GCM-256 for cloud sync, not for local storage |

**Conclusion:** The vast majority of clipboard managers (including the most popular open-source one, Maccy) do NOT encrypt local data. The ones that do encrypt are either encrypting cloud-synced data (different threat model) or using it as a marketing differentiator (SaneClip). FileVault + App Sandbox is the industry-standard protection for local data.

### Recommended Security Hardening (Without Encryption)

These are concrete improvements that increase security without the performance/complexity cost of encryption:

1. **Add a "Clear on Quit" option** -- UserDefaults toggle that calls `clearAllHistory()` on `applicationWillTerminate`. Zero-cost, addresses Time Machine backup concern.

2. **Sensitive data detection heuristics** -- Auto-detect patterns that look like credit card numbers, SSNs, API keys (regex patterns). Flag these items with a "sensitive" marker and auto-expire them like concealed items (configurable timeout).

3. **Export file warning** -- When exporting, show a clear warning that the `.pastel` file contains unencrypted clipboard text and should be stored securely or deleted after import.

4. **Verify image directory permissions** -- On launch, verify that `~/Library/Application Support/Pastel/images/` has restrictive POSIX permissions (0700). Currently uses default permissions from `createDirectory()`.

5. **Memory cleanup on hide** -- When the panel hides, nil out any large data structures (e.g., the highlight cache could be capped more aggressively, image caches could be trimmed).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Application-level encryption | Custom AES/SQLCipher integration | FileVault + App Sandbox | OS-level encryption is transparent, zero performance cost, and cannot be bypassed by app-level bugs |
| Clipboard change detection | KVO/notification-based monitoring | NSPasteboard.changeCount polling | Apple explicitly does not provide change notifications; polling is the only reliable approach |
| Syntax highlighting | Custom regex-based highlighter | HighlightSwift (already used) | highlight.js has 190+ languages; custom highlighting is a maintenance nightmare |
| CGEvent Cmd+V simulation | Accessibility API scripting | Direct CGEvent posting (already used) | CGEvent is lower-level and more reliable than NSAppleScript or AX-based approaches |

## Common Pitfalls

### Pitfall 1: SwiftData @Query in Frequently-Instantiated Views
**What goes wrong:** Every instance of a view with `@Query` creates an independent SQLite subscription. In a `ForEach`, this means N subscriptions for N visible cards.
**Why it happens:** `@Query` is convenient and looks like a simple property declaration, hiding the subscription cost.
**How to avoid:** Pass queried data as parameters to child views. Reserve `@Query` for the top-level container view only.
**Warning signs:** High CPU in `SwiftData` framework during profiling, especially when scrolling.

### Pitfall 2: `.id()` Modifier Causing Full View Reconstruction
**What goes wrong:** Changing the `.id()` value destroys and recreates the entire view tree, including all child views, their state, and their queries.
**Why it happens:** `.id()` is used to force `@Query` recreation when filters change. But including frequently-changing values (like `itemCount`) causes unnecessary rebuilds.
**How to avoid:** Only include values that should trigger a complete query reset in the `.id()` string. Do not include values that `@Query` already observes automatically.
**Warning signs:** Scroll position resets, visual flicker, or performance drops when new items are captured while the panel is open.

### Pitfall 3: Silent `try?` Hiding Data Loss
**What goes wrong:** A `try? modelContext.save()` silently discards errors, potentially losing user data (label assignments, edits, deletions) without feedback.
**Why it happens:** `try?` is the quickest way to handle errors in SwiftUI view bodies where throwing is not allowed.
**How to avoid:** Create a shared error-handling utility that at minimum logs the error. For user-initiated actions, propagate errors to the UI.
**Warning signs:** User reports of "lost" label assignments or edits that don't persist after app restart.

### Pitfall 4: App-Level Encryption Breaking Search
**What goes wrong:** Encrypting individual properties (textContent, etc.) means `#Predicate` can no longer search them. Full-text search requires decrypting every item in memory.
**Why it happens:** SQLite LIKE queries operate on stored values; if stored values are ciphertext, the query matches ciphertext, not plaintext.
**How to avoid:** Don't encrypt searchable properties. If encryption is mandated, use SQLCipher for whole-database encryption (transparent to queries) instead of property-level encryption.
**Warning signs:** Search returning zero results, or extreme latency on search due to in-memory decryption of entire database.

## Code Examples

### Fix: Replace Force Unwraps with Safe Alternatives

```swift
// BEFORE (ImageStorageService.swift:46)
let appSupport = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
).first!

// AFTER
guard let appSupport = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
).first else {
    // Log error; this should never happen on macOS but defensive coding is better
    Self.logger.error("Could not find Application Support directory")
    fatalError("Application Support directory unavailable")
}
```

```swift
// BEFORE (PersistentIdentifier+Transfer.swift:7-8)
var asTransferString: String {
    let data = try! JSONEncoder().encode(self)
    return String(data: data, encoding: .utf8)!
}

// AFTER
var asTransferString: String? {
    guard let data = try? JSONEncoder().encode(self),
          let string = String(data: data, encoding: .utf8) else {
        return nil
    }
    return string
}
```

### Fix: Extract Shared CGEvent Paste Simulation

```swift
// In PasteService.swift -- make static method accessible
static func simulatePaste() { /* existing implementation */ }

// In HistoryBrowserView.swift -- replace inline duplication
DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
    PasteService.simulatePaste()
}
```

### Fix: Remove itemCount from .id() Modifier

```swift
// BEFORE (PanelContentView.swift:138)
.id("\(debouncedSearchText)\(selectedLabelIDs...)\(appState.itemCount)")

// AFTER -- @Query already observes item changes automatically
.id("\(debouncedSearchText)\(selectedLabelIDs...)")
```

### Fix: Pass Labels as Parameter Instead of @Query in ClipboardCardView

```swift
// BEFORE (ClipboardCardView.swift:21)
@Query(sort: \Label.sortOrder) private var labels: [Label]

// AFTER -- receive from parent
let allLabels: [Label]  // passed from FilteredCardListView/HistoryGridView
```

### Pattern: Shared Error Handler for SwiftData Saves

```swift
// New utility function
@MainActor
func saveWithLogging(_ modelContext: ModelContext, operation: String) {
    do {
        try modelContext.save()
    } catch {
        Logger(subsystem: "app.pastel.Pastel", category: "SwiftData")
            .error("Save failed during \(operation): \(error.localizedDescription)")
        // Future: trigger user-visible error toast
    }
}

// Usage in views
saveWithLogging(modelContext, operation: "label assignment")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSImage.lockFocus()` | `NSImage(size:flipped:drawingHandler:)` | Deprecated macOS 12 | Should migrate menu icon rendering |
| `DispatchQueue.main.async` in @MainActor context | Direct call (already on main actor) | Swift concurrency | Some dispatch calls are redundant when already @MainActor isolated |
| `NSApp.activate(ignoringOtherApps:)` | `NSApp.activate()` (no parameter) | macOS 14 | Current code uses deprecated parameter form in some places |

## Open Questions

1. **Import performance at scale**
   - What we know: Per-item hash lookup during import is O(n) queries
   - What's unclear: Actual performance impact for imports of 5000+ items
   - Recommendation: Pre-load all hashes into a Set<String> before import loop; measure before/after

2. **@Query subscription cost**
   - What we know: Multiple `@Query` instances on the same table create independent observers
   - What's unclear: Exact overhead per subscription (CPU/memory) -- needs Instruments profiling
   - Recommendation: Fix the obvious case (ClipboardCardView) and profile to measure improvement

3. **FileVault adoption rate**
   - What we know: Apple Silicon Macs have FileVault enabled by default; Intel Macs may not
   - What's unclear: What percentage of Pastel users have FileVault enabled
   - Recommendation: Consider a first-launch check that warns if FileVault is disabled (non-blocking informational only)

4. **Memory usage with large histories**
   - What we know: `#Predicate { _ in true }` loads all items; in-memory label filtering processes them all
   - What's unclear: Actual memory footprint for 10K, 50K, 100K items
   - Recommendation: Profile with Instruments using a synthetic large dataset; consider fetchLimit + pagination if needed

## Sources

### Primary (HIGH confidence)
- Codebase analysis: all 57 Swift files in `Pastel/` directory read and analyzed
- Apple App Sandbox documentation: [developer.apple.com/documentation/security/app-sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- Apple FileVault documentation: [support.apple.com/guide/security/volume-encryption-with-filevault](https://support.apple.com/guide/security/volume-encryption-with-filevault-sec4c6dc1b6e/web)

### Secondary (MEDIUM confidence)
- [Hacking with Swift: How to encrypt SwiftData](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-encrypt-swiftdata) -- confirmed SwiftData has no built-in encryption; options are `.allowsCloudEncryption` (iCloud only) or file-level protection
- [Maccy encryption discussion (GitHub #151)](https://github.com/p0deje/Maccy/issues/151) -- developer explicitly questioned the value of app-level encryption over FileVault; issue closed without implementation
- [Ctrl.blog: Clipboard security](https://www.ctrl.blog/entry/clipboard-security.html) -- confirmed that macOS clipboard is globally accessible; voluntary ConcealedType convention is the only protection
- [SaneClip](https://saneclip.com/) -- confirmed as the only clipboard manager with AES-256 local encryption + Touch ID; uses it as marketing differentiator
- [Privacy Guides Community discussion](https://discuss.privacyguides.net/t/macos-clipboard-manager/22131) -- community consensus that clipboard managers should respect ConcealedType and rely on device encryption
- [Apple Developer Forums: Is SwiftData Secure?](https://developer.apple.com/forums/thread/731987) -- Apple response confirms SwiftData relies on platform data protection mechanisms

### Tertiary (LOW confidence)
- General web search results about macOS security trends 2025-2026 (SecureMac, setapp.com) -- used for context only, not for specific technical claims

## Metadata

**Confidence breakdown:**
- Anti-patterns: HIGH -- directly observed in codebase with line numbers
- Performance: MEDIUM-HIGH -- patterns identified from code review; actual impact needs Instruments profiling
- Security assessment: MEDIUM -- based on web research cross-referenced with Apple documentation and competitor analysis
- Encryption recommendation: HIGH -- strong consensus across multiple sources (Maccy developer, Apple documentation, community discussion, competitor analysis)

**Research date:** 2026-02-12
**Valid until:** 2026-04-12 (stable -- macOS security model changes slowly)
