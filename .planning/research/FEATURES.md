# Feature Research: v1.2 Storage & Security

**Domain:** macOS Clipboard Manager (storage optimization and sensitive content protection)
**Project:** Pastel
**Researched:** 2026-02-07
**Confidence:** MEDIUM-HIGH (storage patterns are well-understood; macOS Tahoe clipboard privacy implications are evolving)

> **Scope:** This document covers v1.2 features only: image compression, content deduplication improvements, storage dashboard/management, and sensitive item protection. For v1.0/v1.1 feature landscape, see git history.

---

## 1. Image Compression and Storage Optimization

### How Clipboard Managers Handle Image Storage

**Current Pastel approach (v1.0-v1.1):**
- Images stored as PNG files on disk (lossless but large)
- Full images capped at 4K (3840px max dimension) via CGImageSource downscaling
- Thumbnails at 200px for panel display
- Favicons and og:image previews also stored as PNG
- Typical clipboard screenshot PNG: 2-8 MB per image

**The storage problem:** A user who copies 20 screenshots per day accumulates 100-400 MB per week in image storage alone. Over 3 months (the default retention), that is 1.2-4.8 GB. This is unsustainable without compression.

**Industry standard approaches:**

| Format | Compression Ratio vs PNG | Quality | Decode Speed | macOS Support |
|--------|-------------------------|---------|--------------|---------------|
| JPEG (0.8 quality) | ~5-8x smaller | Lossy, good at 0.8 | Fast (1x baseline) | macOS 10.0+ |
| HEIC (0.8 quality) | ~10-15x smaller | Lossy, excellent | Slower (2x JPEG) | macOS 10.13+ |
| WebP | ~6-10x smaller | Lossy or lossless | Medium | macOS 14+ native |
| PNG (current) | 1x (baseline) | Lossless | Fast | Universal |

**Key insight for clipboard managers:** Users copy images to paste them elsewhere. The pasted content comes from the original pasteboard data, NOT from the stored file. The stored file is only for display in the panel (history browsing). Therefore, lossy compression for the stored copy is perfectly acceptable -- it only affects the preview quality, not paste quality.

**However, there is a nuance:** When a user clicks an old item to paste it, Pastel re-writes it to the pasteboard. If we only stored a compressed JPEG, we would paste a degraded image. The solution is a two-tier approach:

1. **Recent items (< 24 hours):** Store original quality (PNG or whatever the pasteboard provided) for faithful paste-back
2. **Older items:** Compress to JPEG at quality 0.8 for storage savings; accept slight quality loss on paste-back of old items

This matches how PastePal handles it (per training data, MEDIUM confidence) -- recent items are full-quality, older items are compressed after a configurable delay.

**Recommendation:** Use JPEG compression at quality 0.8 for stored images. HEIC offers better compression ratios but decodes 2x slower, which matters for scrolling through history. JPEG is the pragmatic choice: universal compatibility, fast decode, and 5-8x size reduction over PNG. Apply compression to images older than 24 hours via a background task.

**NSImage JPEG compression on macOS (HIGH confidence -- Apple API):**
```swift
let bitmap = NSBitmapImageRep(cgImage: cgImage)
let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
```

### What About Thumbnails?

Thumbnails are already small (200px max) and compressed would save minimal space. Keep thumbnails as PNG for sharpness -- they are tiny files (~10-30 KB each). Not worth the complexity.

---

## 2. Content Deduplication

### Current Pastel Deduplication

**What exists (Phase 1, v1.0):**
- SHA256 hash of text content (`contentHash` field, `@Attribute(.unique)`)
- Consecutive duplicate detection (skip if hash matches most recent item)
- Non-consecutive duplicates: insert fails due to unique constraint, caught and rolled back
- Image hashing: first 4096 bytes via SHA256 (fast but potentially collision-prone)

**What this means:** Pastel already has basic deduplication. The unique constraint on `contentHash` means the same text copied twice (even non-consecutively) creates a conflict that is silently rolled back. However, the "update timestamp on re-copy" behavior is missing -- if you copy "hello" today and again tomorrow, the second copy is silently dropped and the old item retains its original timestamp. The item appears to be buried in history rather than bubbling up to the top.

**Expected behavior in clipboard managers:**

| Manager | Dedup Approach | On Re-copy | Source |
|---------|---------------|------------|--------|
| Maccy | Hash-based dedup | Moves existing item to top (updates timestamp) | WebSearch (MEDIUM confidence) |
| PastePal | Hash-based dedup | Moves to top | Training data (MEDIUM confidence) |
| CopyClip | No dedup | Creates duplicate entry | Training data (LOW confidence) |
| CleanClip | Hash-based dedup | Moves to top | WebSearch (LOW confidence) |

**Recommendation:** Change behavior from "silently drop duplicate" to "update timestamp and bubble to top." This is the expected UX -- when a user re-copies something, they expect to see it at the top of history, not buried where it was first captured. Implementation: on unique constraint conflict, fetch the existing item by hash, update its timestamp and source app, then save.

### Image Deduplication Improvement

**Current approach:** Hashing only first 4096 bytes is fast but fragile -- two different images with the same file header would collide. In practice, this is rare for clipboard content (screenshots always have unique pixel data in the header), so this is LOW priority to change.

**Advanced approach (NOT recommended for v1.2):** Perceptual hashing (pHash) could detect near-duplicate images (same screenshot cropped slightly differently). But this adds significant complexity and CPU overhead for marginal benefit. Keep the current SHA256 approach.

---

## 3. Storage Dashboard and Usage Visibility

### How Apps Show Storage Usage

**No clipboard manager surveyed offers a storage dashboard.** This is genuinely novel territory. Disk space analyzers (DiskSavvy, CleanMyMac, macOS System Settings) show storage breakdowns, but clipboard managers do not surface this information.

**Why it matters for Pastel:** Unlike text-only clipboard managers (Maccy, CopyClip), Pastel stores images, thumbnails, favicons, and og:image previews on disk. Without visibility, users have no idea how much space their clipboard history consumes or what contributes most to disk usage.

**What to show:**

| Metric | Source | Complexity | Value |
|--------|--------|------------|-------|
| Total items count | `fetchCount(ClipboardItem.self)` | LOW | Basic orientation |
| Items by content type | Group query on `contentType` | LOW | Identify what fills history |
| Total disk usage (images) | Sum file sizes in images directory | MEDIUM | The headline number |
| Database file size | SwiftData store file size | LOW | Usually small vs images |
| Usage by category (images, thumbnails, favicons, previews) | Categorize by filename suffix | MEDIUM | Identify optimization targets |
| Oldest item age | Query `min(timestamp)` | LOW | Retention context |

**Visualization approach:** SwiftUI Charts (available macOS 13+) provides `SectorMark` for pie/donut charts. A simple donut chart showing storage by content type (images, text, URLs, code, colors) would be immediately useful and visually satisfying.

**Where to put it:** New "Storage" tab in Settings window, alongside General and Labels tabs. This is the natural location -- Settings is where users manage app behavior, and storage management is a settings-adjacent concern.

---

## 4. Storage Management Tools

### Purge by Category

**Expected behavior:** Users should be able to delete all items of a specific content type ("Delete all images", "Delete all URLs") without affecting other types. This is useful when images are consuming disproportionate disk space.

**Current clearing options in Pastel:**
- Delete individual item (context menu, Phase 4)
- Clear all history (confirmation dialog, Phase 4)
- Automatic retention-based purge (RetentionService, Phase 5)

**What is missing:** Selective purge. Users cannot currently say "I want to keep my text clips but purge all images older than 1 week."

**Purge options to support:**

| Purge Action | Use Case | Complexity |
|-------------|----------|------------|
| Purge by content type | "Delete all images" | LOW -- predicate on `contentType` |
| Purge by age within type | "Delete images older than 1 week" | MEDIUM -- compound predicate |
| Purge items without labels | "Delete unlabeled items only" | LOW -- predicate on `label == nil` |

### Database Compaction

**Context:** SwiftData uses SQLite with WAL (Write-Ahead Logging) under the hood. After large deletions (like purging all images), the database file does not shrink automatically. SQLite maintains free pages internally for future use.

**VACUUM command:** Rebuilds the database file, reclaiming free pages and shrinking the file on disk. Should be triggered after bulk deletions when freelist exceeds ~20% of total pages.

**How to trigger VACUUM from SwiftData (MEDIUM confidence):**
SwiftData does not expose a direct VACUUM API. The approach is to access the underlying SQLite store URL and run VACUUM directly via sqlite3:

```swift
// Access the SQLite file from the ModelContainer's configuration
let storeURL = modelContainer.configurations.first?.url
// Use sqlite3_exec to run VACUUM
```

Alternatively, use `NSSQLitePragmasOption` with auto_vacuum if setting up the store from scratch. For an existing store, a manual VACUUM pass is needed.

**Recommendation:** Add a "Compact Database" button in the Storage settings tab. When pressed, run VACUUM on the SQLite store. Show before/after file size to give users satisfaction. This is a LOW-frequency action (monthly at most) so performance of VACUUM (which can take seconds) is acceptable.

---

## 5. Sensitive Item Protection

### The Landscape: Existing Concealment in Pastel

**What Pastel already does (Phase 1, v1.0):**
- Detects `org.nspasteboard.ConcealedType` from password managers (1Password, Bitwarden, etc.)
- Sets `isConcealed = true` on those items
- Auto-expires concealed items after 60 seconds via ExpirationService
- ConcealedType items skip code/color detection

**What is NOT built yet:**
- Manual "mark as sensitive" by user
- Visual redaction/blurring of sensitive items in the panel
- Click-to-reveal interaction
- Configurable expiry for sensitive items (currently hardcoded to 60s)

### How Password Managers Handle Sensitive Clipboard Content

**1Password (HIGH confidence -- widely documented):**
- Auto-clears clipboard after 90 seconds (configurable)
- Sets `org.nspasteboard.ConcealedType` on macOS native app
- Browser extension does NOT consistently set ConcealedType (known issue per 1Password community forums)

**Bitwarden:**
- Similar auto-clear behavior
- Desktop app has had issues with ConcealedType on macOS (GitHub issue #350)

**Key takeaway:** The `ConcealedType` convention is not universally reliable. Browser extensions often bypass it. Users need a manual fallback to mark items as sensitive.

### Manual "Mark as Sensitive" Design

**How it should work (user's requirement specifies manual, NOT auto-detect):**

1. User right-clicks a clipboard item in the panel
2. Context menu shows "Mark as Sensitive" / "Unmark as Sensitive"
3. Marked items display with visual redaction (blurred/redacted text, blurred image)
4. Clicking a marked item reveals content temporarily
5. Sensitive items can optionally auto-expire faster than normal items

**Why manual, not auto-detect:** Automatic detection of sensitive content (credit card numbers, SSNs, API keys) is fraught with false positives and false negatives. Users know what is sensitive in their workflow. A regex that matches "4111 1111 1111 1111" as a credit card might also match a product SKU. The PROJECT.md decision is explicit: "User decides what's sensitive, not heuristics."

### Visual Redaction Approaches

**SwiftUI provides two built-in mechanisms:**

1. **`.redacted(reason: .privacy)`** -- Replaces content with gray rectangles. Available iOS 15+ / macOS 12+. Good for text but looks like a loading skeleton, which is confusing in this context.

2. **`.blur(radius:)`** -- Gaussian blur overlay. More intuitive for "hidden content" because users understand blurred = concealed. Blur radius of 8-12 makes text unreadable while preserving the sense that content exists.

**Recommendation: Use `.blur(radius: 10)` with an overlay icon (lock or eye-slash).** This is more visually intuitive than `.redacted()` for sensitive content. The blur communicates "this is hidden intentionally" rather than "this is loading." Add a small lock icon overlay so users know why it is blurred and that they can click to reveal.

**Click-to-reveal pattern:**

```swift
@State private var isRevealed = false

VStack {
    contentView
        .blur(radius: item.isSensitive && !isRevealed ? 10 : 0)
        .overlay {
            if item.isSensitive && !isRevealed {
                Image(systemName: "eye.slash.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .onTapGesture {
            if item.isSensitive {
                isRevealed.toggle()
            }
        }
}
```

**Auto-hide after reveal:** After revealing, automatically re-blur after 5-10 seconds. This prevents accidentally leaving sensitive content visible on screen.

### Sensitive Item Auto-Expiry

**Current behavior:** All items use the global retention setting (7d, 30d, 90d, 1y, forever). Concealed items (from password managers) expire in 60 seconds.

**User's requirement:** "Optional shorter auto-expiry for sensitive items."

**Recommended options:**

| Option | Use Case |
|--------|----------|
| 1 hour | Copied a password, will not need it again today |
| 24 hours | Temporary sensitive info, keep through the workday |
| 1 week | Somewhat sensitive, but may need to re-paste |
| Same as normal | User wants sensitivity marking for display only, not expiry |

**Implementation:** Add a `sensitiveExpiryHours` setting in Settings (default: 24 hours). When an item is marked sensitive, set `expiresAt` to `now + sensitiveExpiryHours`. The existing ExpirationService and RetentionService can handle cleanup -- they already check `expiresAt`. The user can also set this to "Same as retention" to disable separate expiry.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist when they see "storage optimization" and "sensitive items" in a changelog.

| Feature | Why Expected | Complexity | Depends On |
|---------|--------------|------------|------------|
| Image compression for storage savings | Images are the #1 storage consumer; users expect optimization | MEDIUM | ImageStorageService (exists) |
| Duplicate handling: bubble re-copied items to top | Every major clipboard manager does this; silent drop is confusing | LOW | ClipboardMonitor dedup logic (exists) |
| Total storage usage display | Users need to know how much space the app uses | LOW | New Settings tab |
| Item count by type | Basic orientation: "how many images vs text clips do I have?" | LOW | SwiftData aggregate queries |
| Mark item as sensitive (manual) | Users who handle passwords/keys expect a way to protect them | MEDIUM | Context menu (exists), new model field |
| Blur/redact sensitive items in panel | If "sensitive" exists as a concept, display must reflect it | LOW | SwiftUI `.blur()` modifier |
| Click-to-reveal for sensitive items | Blurred content is useless if you can never see it | LOW | State toggle per card |
| Purge all items (already exists) | Basic cleanup; already implemented in v1.0 | N/A | Already built |

### Differentiators (Competitive Advantage)

Features no surveyed clipboard manager offers. These set Pastel apart.

| Feature | Value Proposition | Complexity | Depends On |
|---------|-------------------|------------|------------|
| Storage dashboard with donut chart | No competitor shows storage breakdown visually; genuine novelty | MEDIUM | SwiftUI Charts (macOS 13+) |
| Purge by content type | Targeted cleanup without losing everything | LOW | SwiftData predicates |
| Purge by age within type | Fine-grained control: "delete images older than 1 week" | MEDIUM | Compound predicates |
| Database compaction button | Reclaim disk space after bulk deletions; visible before/after | MEDIUM | SQLite VACUUM |
| Configurable sensitive item expiry | No clipboard manager offers graduated expiry for user-marked items | LOW | ExpirationService (exists) |
| Auto-re-blur after timed reveal | Security-conscious: reveals auto-hide after 5-10 seconds | LOW | Timer-based state reset |
| Sensitive items in context menu (toggle) | Quick one-action marking, no dialogs | LOW | Context menu (exists) |
| Deferred image compression (24h grace period) | Recent images stay full quality; older ones compress automatically | MEDIUM | Background task + ImageStorageService |

### Anti-Features (Things to Deliberately NOT Build)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Auto-detect sensitive content (regex for CC#, SSN, API keys) | "Wouldn't it be smart to automatically detect passwords?" | False positives destroy trust; false negatives create false security; regex cannot reliably identify "sensitive" vs "looks like a number" | Manual marking -- user decides what is sensitive |
| Encrypt clipboard history database | "For security!" | Degrades search performance (can't query encrypted fields); false sense of security (key stored on same machine); adds massive complexity | Clear history button, auto-expiry, manual sensitive marking |
| HEIC image compression | "Better compression ratio than JPEG" | 2x slower decode = janky scrolling in panel; limited tooling outside Apple ecosystem; marginal benefit for clipboard previews | JPEG at quality 0.8 -- fast decode, universal, 5-8x savings |
| Perceptual image deduplication (pHash) | "Detect similar screenshots" | CPU-intensive on every capture; complex dependency; marginal benefit for clipboard use case | SHA256 hash dedup (already implemented) |
| Real-time storage monitoring (live counters) | "Show disk usage updating live" | Continuous filesystem polling wastes CPU; storage changes infrequently | Calculate on Settings tab open; refresh button |
| Encrypted/password-protected reveal | "Require password to see sensitive items" | macOS clipboard managers run in user context; if attacker has user access, password adds no real security | Blur + click-to-reveal is sufficient for shoulder-surfing protection |
| Import/export of sensitive items separately | "Export my sensitive clips encrypted" | Scope creep; import/export is deferred to v2 entirely | Defer to v2 |

---

## Feature Dependencies

```
[Mark as Sensitive]
    |-- requires --> [Context menu infrastructure] (DONE in Phase 4)
    |-- requires --> [Model field: isSensitive] (NEW - extends ClipboardItem)
    |
    |-- enables --> [Blur/Redact display]
    |                   |-- enables --> [Click-to-reveal]
    |                   |-- enables --> [Auto-re-blur timer]
    |
    |-- enables --> [Sensitive item expiry setting]
                        |-- reuses --> [ExpirationService] (DONE in Phase 1)

[Image Compression]
    |-- requires --> [ImageStorageService] (DONE in Phase 1)
    |-- requires --> [Background compression task] (NEW)
    |-- enables --> [Storage savings visible in dashboard]

[Storage Dashboard]
    |-- requires --> [Settings window infrastructure] (DONE in Phase 5)
    |-- requires --> [SwiftUI Charts] (framework, no dependency to add)
    |-- enhances --> [Purge by category]
    |-- enhances --> [Database compaction]

[Duplicate bubble-up]
    |-- modifies --> [ClipboardMonitor dedup logic] (DONE in Phase 1)
    |-- independent of other v1.2 features

[Purge by Category]
    |-- requires --> [Storage tab UI] (part of Dashboard)
    |-- enables --> [Database compaction] (run after large purge)

[Database Compaction]
    |-- requires --> [Access to SQLite store URL]
    |-- follows --> [Purge by category] (most valuable after bulk delete)
```

### Dependency Notes

- **Mark as Sensitive requires context menu:** Already built in Phase 4. Just needs a new menu item.
- **Storage Dashboard requires Settings window:** Already built in Phase 5. Just needs a new tab.
- **Image Compression and Sensitive Marking are independent:** Can be built in parallel or any order.
- **Database Compaction follows Purge:** Most valuable after bulk deletions, but can be offered standalone too.
- **Duplicate bubble-up is standalone:** No dependencies on other v1.2 features; can ship in any phase.

---

## Milestone Scope Definition

### Must Build (v1.2 Core)

- [ ] **Image compression** -- JPEG at 0.8 for images older than 24h; background task
- [ ] **Duplicate bubble-up** -- Re-copied items update timestamp and appear at top
- [ ] **Storage dashboard** -- New Settings tab showing item counts, disk usage, donut chart
- [ ] **Purge by content type** -- Delete all items of a selected type
- [ ] **Mark as sensitive** -- Context menu toggle on clipboard items
- [ ] **Blur/redact display** -- Sensitive items show blurred in panel
- [ ] **Click-to-reveal** -- Tap to temporarily show sensitive content
- [ ] **Sensitive item expiry** -- Configurable shorter auto-expiry for marked items

### Add If Time Allows (v1.2 Stretch)

- [ ] **Database compaction** -- VACUUM button with before/after size display
- [ ] **Purge unlabeled items** -- Delete items without any label assigned
- [ ] **Auto-re-blur timer** -- Re-hide sensitive content after 5-10 seconds
- [ ] **Purge by age within type** -- Compound filter: "images older than 1 week"

### Defer to v1.3+ (Out of Scope)

- [ ] **HEIC compression** -- Wait for decode performance to improve
- [ ] **Perceptual image dedup** -- Overkill for clipboard use case
- [ ] **Auto-detect sensitive content** -- False positive risk too high
- [ ] **Encrypted database** -- Complexity without real security gain

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Mark as sensitive (context menu) | HIGH | LOW | P1 |
| Blur/redact sensitive items | HIGH | LOW | P1 |
| Click-to-reveal | HIGH | LOW | P1 |
| Duplicate bubble-up on re-copy | HIGH | LOW | P1 |
| Image compression (JPEG, 24h grace) | HIGH | MEDIUM | P1 |
| Sensitive item expiry setting | MEDIUM | LOW | P1 |
| Storage dashboard (item counts + disk usage) | MEDIUM | MEDIUM | P1 |
| Purge by content type | MEDIUM | LOW | P1 |
| Database compaction | LOW | MEDIUM | P2 |
| Auto-re-blur timer | LOW | LOW | P2 |
| Purge unlabeled items | LOW | LOW | P2 |
| Purge by age within type | LOW | MEDIUM | P3 |

---

## Competitor Feature Analysis

| Feature | PastePal | Paste 2 | Maccy | Pastel (v1.2) |
|---------|----------|---------|-------|---------------|
| Image compression | Unknown (likely yes, recent images full-quality) | Unknown | No image storage (text only by default) | JPEG 0.8 with 24h grace period |
| Storage dashboard | None visible | None visible | None (lightweight, no images) | Donut chart + item counts + disk size |
| Purge by type | None visible | None visible | None | Category-based purge |
| Sensitive marking | Exclude apps list | Exclude apps list | Ignores ConcealedType | Manual mark + blur + reveal + expiry |
| Deduplication | Bubble-up on re-copy | Bubble-up on re-copy | Bubble-up on re-copy | Bubble-up on re-copy (to be added) |
| Auto-expiry for sensitive | Not user-configurable | Not user-configurable | N/A (deletes concealed items) | Configurable: 1h, 24h, 1w, or match retention |
| Database compaction | Not exposed | Not exposed | Not exposed | Manual VACUUM button |

**Pastel's competitive edge in v1.2:** Storage visibility and management. No surveyed competitor gives users visibility into how much disk space their clipboard history consumes or tools to manage it selectively. Combined with genuinely useful sensitive item protection (not just app exclusion lists), this positions Pastel as the most storage-conscious and privacy-respectful clipboard manager.

---

## Critical Context: macOS Tahoe (macOS 26) Implications

### Built-in Clipboard History

macOS 26 Tahoe includes native clipboard history accessible via Spotlight (Cmd+4). Items retained for 8 hours, disabled by default. This is basic but represents Apple entering the space. It validates the clipboard manager category while raising the bar for third-party apps.

**Impact on Pastel:** Reinforces the importance of features Apple's built-in solution lacks -- labels, search, image support, sensitive marking, storage management. Apple's version is intentionally minimal (8-hour retention, no organization, no images). Pastel's differentiators remain strong.

### Clipboard Privacy Prompts

macOS 16+ (and Tahoe) introduces clipboard privacy prompts when apps read the pasteboard programmatically. NSPasteboard polling (which Pastel uses) will trigger a one-time permission request.

**Impact on v1.2 specifically:** The `isConcealed` check already works without reading pasteboard contents (it checks pasteboard types, not content). However, the new `detect` methods should be evaluated in a future phase to minimize permission friction. For v1.2, this is informational -- the permission prompt is a one-time user action, and clipboard managers are expected to request this access.

---

## Sources

- [PastePal - App Store](https://apps.apple.com/us/app/clipboard-manager-pastepal/id1503446680) (feature list, MEDIUM confidence)
- [Maccy - GitHub](https://github.com/p0deje/Maccy) (open source, storage approach, HIGH confidence)
- [NSPasteboard.org](http://nspasteboard.org/) (ConcealedType specification, HIGH confidence)
- [1Password - Clipboard Clearing](https://1password.community/discussions/1password/clipboard-clearing----too-aggressive/123881) (90s timeout, HIGH confidence)
- [Bitwarden - ConcealedType Issue](https://github.com/bitwarden/desktop/issues/350) (ConcealedType gaps, HIGH confidence)
- [SwiftUI redacted modifier](https://developer.apple.com/documentation/swiftui/view/redacted(reason:)) (Apple docs, HIGH confidence)
- [macOS Tahoe Clipboard History](https://jimmytechsf.com/blog/macos-26-tahoe-gets-clipboard-history) (8-hour retention, MEDIUM confidence)
- [macOS 16 Clipboard Privacy](https://9to5mac.com/2025/05/12/macos-16-clipboard-privacy-protection/) (privacy prompts, MEDIUM confidence)
- [Pasteboard Privacy Developer Preview](https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/) (detect APIs, MEDIUM confidence)
- [macOS Tahoe 26.1 Clipboard Settings](https://www.macworld.com/article/2962021/this-macos-tahoe-26-1-setting-will-eliminate-embarrassing-clipboard-mishaps.html) (expiry options, MEDIUM confidence)
- [SQLite VACUUM](https://sqlite.org/lang_vacuum.html) (database compaction, HIGH confidence)
- [SwiftUI Charts SectorMark](https://swiftwithmajid.com/2023/09/26/mastering-charts-in-swiftui-pie-and-donut-charts/) (donut charts, HIGH confidence)
- [NSImage JPEG compression](https://developer.apple.com/documentation/appkit/nsbitmapimagerep/representation(using:properties:)) (Apple API, HIGH confidence)
- [HEIC vs JPEG performance](https://pspdfkit.com/blog/2018/ios-heic-performance/) (decode speed comparison, MEDIUM confidence)
- [CoreData VACUUM approach](https://blog.eidinger.info/keep-your-coredata-store-small-by-vacuuming) (SQLite compaction from Swift, MEDIUM confidence)

**Gaps requiring phase-specific research:**
- SwiftData VACUUM access: Verify how to access the underlying SQLite store URL from a ModelContainer in the current SwiftData API. May require using the store's `url` property from `ModelConfiguration`.
- macOS Tahoe detect APIs: Evaluate `NSPasteboard.detect()` methods for future compatibility. Not blocking for v1.2 but important for v1.3+.
- Background image compression: Test JPEG compression quality 0.8 with real clipboard screenshots to verify acceptable visual quality for panel display.

---
*Feature research for: Pastel v1.2 -- Storage & Security*
*Researched: 2026-02-07*
