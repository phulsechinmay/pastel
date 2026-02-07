# Pitfalls Research: v1.2 Storage & Security

**Domain:** macOS clipboard manager -- adding storage optimization (compression, deduplication, dashboard, purge) and sensitive item protection (manual marking, blur redaction, click-to-reveal, auto-expiry) to existing v1.0/v1.1 system
**Researched:** 2026-02-07
**Confidence:** MEDIUM-HIGH (verified against official SQLite docs, Apple developer forums, and existing codebase analysis; some macOS 15+ screenshot protection claims based on developer forum reports)

---

## Critical Pitfalls

Mistakes that cause data loss, broken paste-back, or false sense of security requiring rework.

### Pitfall 1: Lossy Image Compression Degrades Paste-Back Quality

**What goes wrong:**
Compressing stored images with lossy JPEG/HEIC to save disk space silently degrades paste-back fidelity. The user copies a pixel-perfect screenshot from Figma, Pastel compresses it to JPEG at 80% quality, and when the user pastes it back days later, the image has JPEG artifacts -- blurred text, color banding around sharp edges, and different dimensions. For developers and designers, this is a deal-breaker: a clipboard manager that corrupts images is worse than no clipboard manager.

The existing `ImageStorageService` stores images as PNG (lossless) after downscaling to 4K max. Switching to lossy compression changes a fundamental contract: what you copy is NOT what you paste back.

**Why it happens:**
The storage savings from lossy compression are dramatic (PNG screenshot: 2MB, JPEG 80%: 200KB). Developers see a 10x reduction and ship it without checking paste-back quality with critical content types: screenshots with text, UI mockups, diagrams with thin lines, pixel art, and images with transparency.

**Specific risk in Pastel's architecture:**
- `ImageStorageService.saveImage()` currently stores as PNG via `pngData(from:)`. Changing this to JPEG would lose alpha channel (transparency) silently -- JPEG does not support alpha.
- `PasteService.writeToPasteboard()` reads the stored file and writes it as `.png` and `.tiff` to the pasteboard. If the stored file is JPEG, the types would need to change, and some receiving apps may not handle JPEG pasteboard data correctly.
- The `computeImageHash()` function hashes the first 4KB of raw image data. Compressing an image changes its bytes, so re-hashing after compression would produce different hashes than the original -- breaking deduplication across compress/non-compress boundaries.

**How to avoid:**
- **Keep originals as PNG (lossless). Compress only the display thumbnails.** The existing 200px thumbnails are already small. Add a medium-resolution "preview" thumbnail (e.g., 800px) compressed as JPEG for the panel card display, but keep the full-size PNG for paste-back. This gives storage savings on display while preserving paste fidelity.
- **If lossy compression is truly needed for storage:** Make it opt-in per item (not global). Show a clear warning: "Compressed images may lose quality when pasted." Never auto-compress. Let the user choose which old images to compress.
- **Never compress images with alpha channel.** Detect transparency before compression. If the image has alpha, keep it as PNG regardless of compression settings.
- **Store the original format metadata.** Add `imageFormat: String?` to ClipboardItem so paste-back can write the correct pasteboard type.

**Warning signs:**
- Paste a screenshot with text into a design tool. If the text looks fuzzy, compression is too aggressive.
- Paste an image with transparency. If the background turns white/black, alpha channel was lost.
- Users report "Pastel ruined my image" in feedback.

**Phase to address:** Image compression phase. Decide the compression strategy BEFORE writing any compression code. The preview-thumbnail approach avoids this pitfall entirely.

**Confidence:** HIGH -- PNG vs JPEG quality differences and alpha channel loss are well-documented. Verified that current `ImageStorageService` uses PNG exclusively.

---

### Pitfall 2: Purge Operations Delete Disk Files But Crash Before Deleting SwiftData Records (or Vice Versa)

**What goes wrong:**
Purge operations (clear by category, clear by date range, compact storage) must delete both SwiftData records AND their associated disk files (images, thumbnails, favicons, preview images). If the operation deletes disk files first and then crashes before the SwiftData delete, the database has orphan records pointing to missing files. If SwiftData records are deleted first and the crash happens before disk cleanup, orphan files accumulate on disk consuming space invisibly.

The existing `RetentionService.purgeExpiredItems()` and `AppState.clearAllHistory()` both exhibit this pattern: they iterate items, call `ImageStorageService.shared.deleteImage()` (which runs on a background queue), then delete from SwiftData. Since `deleteImage()` is fire-and-forget on `backgroundQueue.async`, the disk deletion and SwiftData deletion are NOT atomic -- they can partially complete.

**Why it happens:**
There is no transaction that spans both file system operations and SwiftData. File deletion is immediate and irreversible (`FileManager.removeItem`). SwiftData deletion requires `modelContext.save()` which can fail. These two systems have independent failure modes.

For a small retention purge (deleting 5 expired items), partial failure is tolerable. For a bulk purge ("delete all images older than 30 days" -- potentially hundreds of items), partial failure means significant data inconsistency.

**Specific risk in Pastel's architecture:**
- `ImageStorageService.deleteImage()` runs on `backgroundQueue` (`.utility` QoS). It's async and has no completion handler. The caller cannot know when or if disk deletion succeeded.
- `RetentionService` deletes images in a loop, then deletes SwiftData records in another loop, then calls `modelContext.save()`. If `save()` throws, it rolls back the SwiftData deletes -- but the disk files are already gone.
- Bulk purge of hundreds of items will be significantly slower than the current small-batch retention purge. SwiftData's `modelContext.delete(model:)` is a batch operation but does not support a `where:` predicate combined with pre-deletion hooks (to collect file paths).

**How to avoid:**
- **Delete SwiftData records FIRST, then disk files.** If SwiftData deletion fails, roll back and abort -- no disk files were touched. If SwiftData succeeds but disk cleanup fails, orphan files are a minor issue (wasted space) that can be cleaned up later by a separate reconciliation task. This order ensures the more critical data (records) stays consistent.
- **Collect all file paths before deleting records.** Fetch items, extract `imagePath`, `thumbnailPath`, `urlFaviconPath`, `urlPreviewImagePath` into an array. Delete records from SwiftData and save. Only then iterate the file paths array for disk cleanup.
- **Add an orphan file cleanup task.** On app launch (or periodically), scan the `~/Library/Application Support/Pastel/images/` directory. For each file, check if any ClipboardItem references it. Delete unreferenced files. This catches any previous partial failures.
- **For bulk purges, batch the SwiftData operations.** Delete in batches of 50-100 items with `modelContext.save()` between batches. This prevents a single massive transaction that could timeout or OOM.

**Warning signs:**
- Image cards show broken thumbnails (file deleted, record exists).
- Storage dashboard shows X items but disk usage keeps growing (records deleted, files remain).
- `modelContext.save()` throws during large purge operations.

**Phase to address:** Storage management / purge phase. The orphan cleanup reconciliation should be implemented alongside purge operations.

**Confidence:** HIGH -- verified by reading existing `RetentionService` and `AppState.clearAllHistory()` code. The non-atomic file+record deletion pattern is already present.

---

### Pitfall 3: "Mark as Sensitive" Creates False Sense of Security While Data Remains Plaintext on Disk

**What goes wrong:**
The user marks a clipboard item as "sensitive." Pastel blurs it in the panel and maybe auto-expires it. The user feels protected. But the actual content (`textContent`, `imagePath`) is stored in plaintext in the SwiftData SQLite database and as unencrypted files on disk. Anyone with access to `~/Library/Application Support/Pastel/` can read every "sensitive" item directly from the database file using `sqlite3` or by opening the image files.

This is worse than no security feature at all, because the user *believes* their sensitive data is protected. They might mark API keys, passwords, private messages, or financial data as "sensitive" and feel safe. But the protection is purely visual -- a blur overlay in the UI. The underlying data is fully exposed.

**Why it happens:**
True encryption is hard. Encrypting individual SwiftData fields breaks `#Predicate` queries (you can't search encrypted text). Encrypting files on disk requires key management. The easy path is "just blur it in the UI" -- which looks like security but isn't.

The project's own REQUIREMENTS.md has "Encrypted clipboard history" explicitly in Out of Scope with the rationale: "Degrades search performance, false sense of security." This is accurate for full-database encryption but does not address the scenario where users explicitly mark specific items as sensitive.

**Specific risk in Pastel's architecture:**
- `textContent` is a plain `String?` in SwiftData. The SQLite file at `~/Library/Application Support/Pastel/default.store` contains this in cleartext.
- No App Sandbox means the database and image files are readable by any process with the user's UID.
- OSLog messages include content type and source app but not content itself -- this is good. However, adding logging for sensitive operations ("Marked item as sensitive") must not include the item's content.
- The existing `isConcealed` field (for password manager items) auto-expires items after 60 seconds. "Mark as sensitive" is different -- the user wants to KEEP the item but redact it visually. If sensitive items use the same `expiresAt` mechanism, users will lose data they wanted to keep.

**How to avoid:**
- **Be honest in the UI.** Do NOT call this feature "secure" or "encrypted." Call it "redacted" or "hidden from view." Use language like "This item is hidden in the panel. It is still stored on your Mac." A tooltip or info icon can explain: "For full disk protection, enable FileVault."
- **Do NOT encrypt individual items.** It adds complexity without real security (the encryption key must live somewhere on the same machine). Instead, rely on macOS FileVault (full-disk encryption) for at-rest protection.
- **Redact sensitive items from specific export/sharing operations.** When implementing export (v2), skip sensitive items entirely or require confirmation.
- **Sanitize logs.** Any new logging related to sensitive items must use `OSLog` privacy markers: `\(item.textContent ?? "", privacy: .private)` so content is redacted in system logs unless Console.app has device unlocked.
- **Separate `isSensitive` from `isConcealed`.** The existing `isConcealed` is automatically detected from password managers and auto-expires in 60 seconds. The new `isSensitive` is manually set by the user and should NOT auto-expire by default. These are different concepts with different lifecycles. Using the same field would conflate them.

**Warning signs:**
- Feature description or UI strings use words like "secure," "protected," or "encrypted."
- User-marked sensitive items use the same `isConcealed` field (conflates auto-detected with manual).
- Sensitive item content appears in OSLog or crash reports.

**Phase to address:** Sensitive item marking phase. The UI language and data model distinction (`isSensitive` vs `isConcealed`) must be decided before any implementation.

**Confidence:** HIGH -- verified that the database is unencrypted plaintext SQLite, no sandbox, and that `isConcealed` already serves a different purpose. Security claims verified against clipboard security analysis.

---

### Pitfall 4: Content Deduplication Silently Drops Different Content That Hashes the Same

**What goes wrong:**
The deduplication system uses SHA256 content hashes with a `@Attribute(.unique)` constraint. If two different clipboard contents produce the same hash, the second one is silently dropped (the SwiftData insert fails with a unique constraint violation, and `modelContext.rollback()` discards it). The user copies something, it never appears in history, and there is no indication of why.

The current system has TWO deduplication mechanisms:
1. **Consecutive dedup** (`isDuplicateOfMostRecent`): Compares hash of new item to the most recent item. Skips if same.
2. **Global dedup** (`@Attribute(.unique)` on `contentHash`): Any item with the same hash as ANY historical item is rejected.

For v1.2 content deduplication, the question is whether to expand beyond consecutive dedup into true content-aware dedup (finding items with identical or near-identical content across the entire history).

**Why it happens:**
SHA256 hash collisions are astronomically unlikely for genuinely different content. The real risk is not cryptographic collision but **implementation bugs in what gets hashed**:
- Image hashing uses only the first 4KB of data (`ImageStorageService.computeImageHash`). Two different images with the same first 4KB (e.g., same EXIF header, different pixel data) would hash identically.
- Text hashing uses `Data(primaryContent.utf8)`. If `primaryContent` is empty or nil, different empty items all hash to the same empty-string SHA256. (The current code guards against empty content, but new code paths might not.)
- If compression changes image bytes, the same logical image has different hashes before and after compression.

**Specific risk in Pastel's architecture:**
- The current `@Attribute(.unique)` on `contentHash` means the global dedup is already live. Adding explicit dedup logic needs to interoperate with this constraint without causing confusing double-rejections.
- The `isDuplicateOfMostRecent` function only checks the single most recent item. True dedup would need to check against all items, which is more expensive but also more correct.
- The `modelContext.rollback()` in the catch block after failed `.save()` handles unique violations gracefully but invisibly. The user never knows an item was dropped.

**How to avoid:**
- **For text dedup: Hash the full content, not a prefix.** The current text hashing is already correct (full UTF-8 content). Keep this.
- **For image dedup: Hash more than 4KB.** The first 4KB is often metadata/headers. Hash at least the first 64KB, or better, hash the entire file. For very large images, use a two-stage approach: fast prefix hash for initial comparison, full hash for confirmation.
- **For near-duplicate detection (e.g., same text with trailing whitespace differences):** Normalize before hashing. Trim whitespace, normalize Unicode (NFC), then hash. But store the ORIGINAL content for paste-back -- only use normalized form for dedup comparison.
- **When adding compression: compute and store the hash BEFORE compression.** The hash should represent the logical content, not the storage representation. This way, the same image hashed before and after compression produces the same dedup key.
- **Consider whether global dedup (`@Attribute(.unique)`) is actually desired.** Currently, if you copy the same text, go do other things, and copy it again a week later, the second copy is silently dropped. For a clipboard manager, the user might WANT the second copy to appear (with a new timestamp). Consider relaxing the unique constraint and using only consecutive dedup plus explicit user-initiated dedup.

**Warning signs:**
- User reports "I copied X but it doesn't appear in history" -- likely a hash collision with an older item.
- After adding compression, previously-deduplicated images are no longer detected as duplicates (hash changed).
- Two visually different images show the same hash in logs (4KB prefix collision).

**Phase to address:** Deduplication phase. The hashing strategy and unique constraint policy must be decided before implementing any new dedup logic.

**Confidence:** HIGH -- verified the 4KB image prefix hashing in `ImageStorageService.computeImageHash()` and the `@Attribute(.unique)` constraint on `contentHash`.

---

### Pitfall 5: Database Compaction (VACUUM) Corrupts Data or Fails Under Active Use

**What goes wrong:**
SQLite `VACUUM` creates a copy of the entire database, restructures it for optimal space, then replaces the original. During this process:
1. It requires **twice the disk space** of the current database (original + copy).
2. It **fails if there is an open transaction** on the same connection.
3. It is a **write operation** that blocks all other writes during execution.
4. If the app crashes or the user force-quits during VACUUM, the database can be left in an inconsistent state.
5. It can **change ROWIDs** for tables without explicit INTEGER PRIMARY KEY (SwiftData uses its own ID scheme, which could be affected).

For a clipboard manager that polls the pasteboard every 0.5 seconds and writes new items continuously, running VACUUM while the app is actively capturing clipboard changes creates a high-risk window where the capture write collides with the VACUUM write.

**Why it happens:**
Developers add a "Compact Database" button to the storage dashboard. The user clicks it. The VACUUM runs on the same `ModelContext` that `ClipboardMonitor` uses for clipboard capture. The timer fires, a new clipboard item arrives, `modelContext.save()` is called -- and it fails or corrupts because VACUUM is in progress.

**Specific risk in Pastel's architecture:**
- There is ONE `ModelContext` shared by `ClipboardMonitor`, `RetentionService`, `ExpirationService`, and the SwiftUI views. All are `@MainActor`. A VACUUM on this context blocks the main thread and conflicts with the 0.5s polling timer.
- SwiftData wraps Core Data which wraps SQLite. Accessing SQLite's VACUUM through SwiftData is not directly supported -- you would need to drop down to Core Data's `NSPersistentStoreCoordinator` or use raw SQLite access, both of which bypass SwiftData's change tracking and can leave the `ModelContext` in an inconsistent state.
- The database uses WAL mode (SwiftData's default). VACUUM in WAL mode has specific constraints -- it can only change the `auto_vacuum` property, not other pragmas.

**How to avoid:**
- **Do NOT implement VACUUM as a user-facing feature.** The risk-reward ratio is poor. SQLite databases for a clipboard manager are typically small (under 50MB even with thousands of items). The space savings from VACUUM are minimal and the corruption risk is real.
- **If compaction is truly needed:** Use `VACUUM INTO` to create a compacted copy. This does not modify the original database. Then, shut down all database access (stop ClipboardMonitor, invalidate timers), swap the files, and restart. This is safer but complex.
- **Prefer periodic cleanup over compaction.** Deleting old items via `RetentionService` and the orphan file cleanup (Pitfall 2) is sufficient for managing storage. The database file will have some wasted space from deletions, but SQLite reuses deleted pages for new insertions automatically.
- **If implementing a storage dashboard:** Show the database file size and image directory size. Offer "Delete items older than X" and "Delete items by type" -- not "Compact Database." These achieve the user's goal (free up space) without VACUUM's risks.

**Warning signs:**
- The app freezes for several seconds when the user clicks "Compact" (VACUUM blocking main thread).
- Clipboard monitoring stops capturing during compaction (timer fires can't write).
- Crash reports with SQLite errors after compaction attempt.

**Phase to address:** Storage dashboard / management phase. The decision to NOT implement VACUUM should be made during phase planning.

**Confidence:** HIGH -- verified against official SQLite VACUUM documentation. VACUUM failure conditions during active transactions are well-documented. SwiftData's lack of direct VACUUM API confirmed via developer community sources.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Reuse `isConcealed` for user-marked sensitive items | No new field, less migration | Conflates auto-detected (60s expiry) with user-chosen (persist). Users lose items they wanted to keep. | Never -- these are fundamentally different concepts |
| JPEG compression for all stored images | Massive storage savings (5-10x) | Lossy paste-back, alpha channel loss, user trust erosion | Never for paste-back source; acceptable for display-only thumbnails |
| Sync file deletion with SwiftData deletion in same operation | Simpler code, no orphan handling | Partial failures leave inconsistent state; no recovery path | Acceptable for single-item delete (low risk); never for bulk purge |
| Calculate storage stats synchronously on every panel open | Simple implementation, always current | Panel open latency grows with history size; blocks main thread | Only if history is under 100 items. Cache stats and recalculate periodically for larger histories |
| Store compression metadata only in filename (e.g., `.jpg` vs `.png`) | No schema change needed | Filename parsing is fragile; renaming files breaks detection; no room for quality parameters | Never -- use explicit model fields |
| Use `blur(radius:)` alone for sensitive item redaction | Quick to implement, looks good in demo | VoiceOver reads the content behind the blur; blur can be circumvented by reading SwiftUI view hierarchy | Acceptable as visual layer but must be combined with content replacement in the view |

---

## Integration Gotchas

Mistakes specific to adding v1.2 features alongside the existing v1.0/v1.1 system.

| Integration Point | Common Mistake | Correct Approach |
|-------------------|----------------|------------------|
| `isConcealed` vs `isSensitive` | Using the same Bool field for both auto-detected concealed items (password managers) and user-marked sensitive items | Add new `isSensitive: Bool? = nil` field. ExpirationService handles `isConcealed`; new SensitiveService handles `isSensitive`. Different expiry defaults, different UI treatment |
| RetentionService purge + new purge-by-category | Adding category purge to RetentionService, making it do too much | Create a separate PurgeService for user-initiated purges. RetentionService remains automated-only. Both share the same file cleanup helper |
| Image hash stability across compression | Compressing an image changes its bytes, changing its hash. If hash is recomputed after compression, dedup breaks for items that were identical pre-compression | Compute and store hash from ORIGINAL image data at capture time. Never recompute hash after compression. If compression is retroactive, preserve the original hash |
| FilteredCardListView + sensitive blur | Adding blur to card views while maintaining keyboard navigation and paste-back | The blur is a visual overlay only. The item is still fully selectable, navigable, and pasteable. Click-to-reveal toggles the blur state on the view, NOT on the data model. The underlying `ClipboardItem.textContent` is never modified |
| ExpirationService + sensitive auto-expiry | Reusing ExpirationService (designed for 60s concealed items) for configurable sensitive expiry (hours/days) | ExpirationService uses `DispatchWorkItem` timers, which are not suitable for long-duration expiries (survive app restarts poorly). For sensitive auto-expiry, use the same approach as RetentionService: periodic polling with date comparison. Add `sensitiveExpiresAt: Date?` field |
| Storage dashboard + ImageStorageService | Calculating image directory size by iterating all files on every dashboard open | Cache the total image directory size. Update it incrementally when images are added/deleted. Recalculate fully only on first launch or user request |

---

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Scanning entire images directory for storage stats | Dashboard takes 2+ seconds to open, main thread blocked | Cache directory size at launch. Update incrementally on add/delete. Use `FileManager.enumerator(at:includingPropertiesForKeys:[.fileSizeKey])` with prefetched keys | ~500+ images on disk (common after months of use) |
| Fetching ALL ClipboardItems to calculate per-type counts | Memory spike loading thousands of items into memory | Use separate `FetchDescriptor` with `fetchCount` for each content type, using `#Predicate` to filter. No items loaded into memory | ~5,000+ items (months of heavy use) |
| Dedup scan comparing new item against entire history | O(n) hash comparison on every clipboard capture, slowing the 0.5s poll loop | Use `@Attribute(.unique)` (already in place) instead of manual iteration. For near-duplicate detection, use SwiftData `#Predicate` with `contentHash` field, not in-memory comparison | ~10,000+ items |
| Rendering blur effect on every card in a lazy list | GPU overhead from multiple simultaneous `blur(radius:)` modifiers during scroll | Only apply blur to VISIBLE sensitive cards. Use a boolean `isRevealed` state per card, not a global toggle. LazyVStack already handles view lifecycle, but blur calculation adds per-frame cost | ~20+ sensitive items visible in a scroll session |
| Full-database size calculation via `FileManager.attributesOfItem` on the SQLite file | Inaccurate (doesn't include WAL and SHM files), potentially misleading | Sum sizes of `.store`, `.store-wal`, and `.store-shm` files for accurate database size. Or use `NSSQLiteStoreFileProtectionKey` metadata | Immediately inaccurate if only checking main file |

---

## Security Mistakes

Domain-specific security issues for a clipboard manager with sensitive item features.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Logging sensitive item content in OSLog | Sensitive text appears in Console.app / system log, readable by any process | Use OSLog privacy markers: `\(text, privacy: .private)`. Log only item ID, type, and timestamp -- never content. Review ALL new log statements for content leakage |
| Blur without replacing accessible text | VoiceOver reads the full text content behind the blur. Screen readers bypass visual redaction entirely | Set `.accessibilityLabel("Sensitive item")` on blurred cards. Use `.accessibilityHidden(true)` on the actual text content when blurred. Replace readable content, not just overlay it |
| Sensitive content in pasteboard after paste-back | User marks item as sensitive, then pastes it. The content is now on `NSPasteboard.general`, visible to all apps monitoring the clipboard | After paste-back of a sensitive item, optionally clear the pasteboard after a configurable delay (e.g., 30 seconds). Warn the user that pasting places content on the system clipboard |
| Screenshot captures sensitive content through blur | macOS screenshots (`Cmd+Shift+4`) and screen recording capture the composited window, including any blur overlays. However, `NSWindow.sharingType = .none` no longer prevents capture on macOS 15+ (ScreenCaptureKit ignores it) | Accept that screenshot protection is not possible on macOS 15+. Document this honestly. The blur is a casual-viewing deterrent, NOT a screenshot-proof mechanism. Do not claim screenshot protection |
| Sensitive items survive in SwiftData journal/WAL | Even after deleting a sensitive item from SwiftData, the SQLite WAL file may contain the deleted content until the next checkpoint | Accept this as a limitation of SQLite. For users requiring true data destruction, recommend FileVault and point them to the "Clear All History" feature. Do not promise "secure deletion" |
| Auto-expiry deletes items the user wanted to keep | User marks item sensitive with auto-expiry enabled. Days later, wonders where their important API key went. No undo, no recovery | Auto-expiry for sensitive items should be OFF by default (opt-in). When enabled, show a clear countdown or expiry date on the card. Provide a Settings option, not a per-item toggle, to avoid complexity |

---

## UX Pitfalls

Common user experience mistakes when adding storage and security features.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Storage dashboard shows bytes only (e.g., "142,387,456 bytes") | Numbers are meaningless to users. Cannot compare or act on them | Show human-readable sizes ("135.7 MB") with breakdown by type: "Images: 120 MB (312 items), Text: 8 MB (4,201 items), URLs: 7 MB (890 items)" |
| "Compact Database" button with no progress indicator | User clicks, app freezes, user force-quits (the worst outcome during compaction) | If offering any long operation, show a progress indicator. Better: don't offer VACUUM (see Pitfall 5) |
| Mark-as-sensitive requires two-step confirmation | Every mark action: right-click, "Mark Sensitive," confirm dialog. Friction discourages use | Single action with undo support. Right-click, "Mark Sensitive," done. Show a brief toast "Marked as sensitive. Undo?" for 3 seconds |
| Blur radius is too low (partially readable) or too high (obliterates card shape) | Too low: text is guessable. Too high: user cannot distinguish between sensitive items | Use `blur(radius: 10)` (tested: sufficient to make text unreadable at callout font size). Overlay a lock icon or "Sensitive" label so the card is identifiable without revealing content |
| Click-to-reveal has no auto-re-hide | User reveals sensitive content, walks away from desk. Content remains visible indefinitely | Auto-re-hide after 10 seconds of no interaction. Or re-hide when the panel closes. Configurable in Settings |
| Purge operations have no undo | User accidentally purges "all images." Hundreds of screenshots gone. No recovery | Show a confirmation dialog listing what will be deleted ("This will permanently delete 312 images (120 MB). This cannot be undone."). For single-item delete, the existing immediate delete is fine (low impact) |
| Deduplication runs silently with no user feedback | User copies something, it doesn't appear. They don't know why. They copy it again. Still doesn't appear | When a non-consecutive duplicate is detected, update the existing item's timestamp to bring it to the top of the list. This way, the item "reappears" at the top without creating a true duplicate |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Image compression:** Looks done when screenshots compress smaller -- but verify paste-back quality with text-heavy screenshots, transparent PNGs, and pixel art. Test in Figma, Photoshop, and Preview.
- [ ] **Deduplication:** Looks done when identical text is deduplicated -- but verify with near-duplicates (trailing newline, different whitespace), and verify images with different content but same 4KB prefix are NOT falsely deduplicated.
- [ ] **Storage dashboard:** Looks done when showing total size -- but verify it includes WAL/SHM files, image directory size (not just database), and that it updates after purge operations.
- [ ] **Blur redaction:** Looks done when text is visually blurred -- but test with VoiceOver (does it read the content?), test with screenshot (is content captured?), test with large text (is it still readable at any angle?).
- [ ] **Click-to-reveal:** Looks done when click toggles blur -- but verify state resets when panel closes, verify reveal does not persist across app restarts (it's a transient view state, not a model property), verify keyboard navigation still works on revealed items.
- [ ] **Sensitive auto-expiry:** Looks done when items expire -- but verify expiry survives app restart (uses date comparison, not in-memory timer), verify the user understands the item will be deleted (not just hidden), verify expiry does not affect non-sensitive items using the same `expiresAt` field.
- [ ] **Purge by category:** Looks done when items are removed from the list -- but verify disk files are cleaned up (check images directory manually), verify the database size decreases (may need WAL checkpoint), verify item count updates correctly.
- [ ] **New SwiftData fields:** Looks done when the app runs on a fresh database -- but verify migration from v1.1 database with existing items. All new fields must be `Optional` with `nil` default.

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Lossy compression damaged stored images | HIGH | No recovery for already-compressed images. Revert to PNG storage for new captures. Communicate to users that previously compressed images cannot be restored |
| Purge left orphan files on disk | LOW | Run orphan file cleanup: scan images directory, cross-reference with SwiftData records, delete unreferenced files. Automate as periodic task |
| Purge left orphan SwiftData records | MEDIUM | Scan all ClipboardItems with non-nil `imagePath`. Check if file exists. Delete records where file is missing. Show "Image unavailable" placeholder while cleanup runs |
| Sensitive item content leaked in logs | LOW | Remove logging of content. Cannot recall already-written logs. File rotation will eventually clear old entries. No user-facing impact unless logs were exfiltrated |
| VoiceOver reads blurred content | LOW | Add accessibility label override. Fix in next update. No data loss |
| VACUUM corrupted database | HIGH | If app crashes during VACUUM: check if the database is recoverable. If not, restore from Time Machine or start fresh. This is why VACUUM should not be offered (Pitfall 5) |
| `isConcealed` and `isSensitive` conflated | MEDIUM | Add new `isSensitive` field via migration. Write a one-time migration script to move user-marked items from `isConcealed` to `isSensitive`. Reset `expiresAt` for items that should not auto-expire |
| Hash instability after compression | MEDIUM | Recompute hashes for all items from their stored content. Update `contentHash` field. Run dedup pass to find any duplicates that slipped through |
| Auto-expiry deleted items user wanted | HIGH | No recovery -- items are permanently deleted. This is why auto-expiry should be opt-in with clear UI warning. Consider a "recently deleted" holding area (like Photos) for future versions |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Lossy image compression (1) | Image compression phase | Paste-back test: copy screenshot with text + transparency, compress, paste into Figma/Preview, verify pixel-perfect match |
| Non-atomic purge operations (2) | Storage management / purge phase | Kill app during bulk purge (force quit). Restart. Verify no orphan files AND no orphan records. Run orphan cleanup |
| False security from "Mark Sensitive" (3) | Sensitive item marking phase | Review all UI strings for security claims. Open SQLite database directly and verify sensitive content is readable (confirming honest UI language) |
| Dedup hash collision / instability (4) | Deduplication phase | Create two images with same EXIF but different pixels. Verify both are stored. Change compression settings. Verify existing hashes unchanged |
| VACUUM corruption risk (5) | Storage dashboard phase | Decision: do NOT implement VACUUM. Verify storage management achieves user goals without compaction |
| Blur bypassed by VoiceOver (Security) | Blur redaction phase | Enable VoiceOver. Navigate to a blurred sensitive card. Verify VoiceOver reads "Sensitive item" not the actual content |
| Click-to-reveal state persistence (UX) | Click-to-reveal phase | Reveal a sensitive item. Close panel. Reopen panel. Verify item is re-blurred. Quit app. Relaunch. Verify still blurred |
| Auto-expiry data loss (UX) | Auto-expiry phase | Mark item sensitive with auto-expiry. Quit app. Wait past expiry time. Relaunch. Verify item is deleted. Verify the UI warned about expiry before it happened |

---

## Sources

- [SQLite VACUUM documentation](https://sqlite.org/lang_vacuum.html) -- VACUUM failure conditions, disk space requirements, WAL interaction (HIGH confidence)
- [SwiftData pitfalls -- Wade Tregaskis](https://wadetregaskis.com/swiftdata-pitfalls/) -- auto-save failure, relationship corruption (MEDIUM confidence -- opinionated blog, but findings verified against Apple Forums)
- [Key Considerations Before Using SwiftData -- Fat Bob Man](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/) -- batch operation limitations, performance hierarchy (MEDIUM confidence)
- [Apple Developer Forums: macOS 15 NSWindow.sharingType](https://developer.apple.com/forums/thread/792152) -- ScreenCaptureKit ignores sharingType on macOS 15+ (HIGH confidence -- Apple Forums, multiple confirmations)
- [Clipboard security -- Ctrl Blog](https://www.ctrl.blog/entry/clipboard-security.html) -- clipboard manager security fundamentals, plaintext storage risks (HIGH confidence)
- [OSLog privacy documentation](https://developer.apple.com/documentation/os/oslogprivacy) -- log privacy markers for sensitive data (HIGH confidence -- official Apple docs)
- [Hash collision risks in deduplication](https://backupcentral.com/de-dupe-hash-collisions/) -- silent data loss from false positive matches (HIGH confidence)
- [SQLite forum: Does VACUUM ever result in data loss](https://sqlite.org/forum/info/3bd787a793af66aaaa41898374160bceee7fca52c995c2351279b642162f662d) -- VACUUM safety during concurrent access (HIGH confidence -- official SQLite forum)
- [Prevent screenshot capture of sensitive SwiftUI views](https://www.createwithswift.com/prevent-screenshot-capture-of-sensitive-swiftui-views/) -- iOS-only UITextField technique, not applicable to macOS (MEDIUM confidence)
- [SwiftData batch delete -- Fat Bob Man](https://fatbobman.com/en/snippet/how-to-batch-delete-data-in-swiftdata/) -- batch delete API, save requirement (MEDIUM confidence)
- Direct analysis of Pastel codebase: `ImageStorageService.swift`, `RetentionService.swift`, `ClipboardMonitor.swift`, `ExpirationService.swift`, `ClipboardItem.swift`, `PasteService.swift`, `ClipboardCardView.swift` (HIGH confidence -- source code inspection)

---
*Pitfalls research for: Pastel v1.2 Storage & Security*
*Researched: 2026-02-07*
