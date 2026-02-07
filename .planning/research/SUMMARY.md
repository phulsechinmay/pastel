# Project Research Summary

**Project:** Pastel v1.2 Storage & Security
**Domain:** macOS Clipboard Manager (storage optimization and sensitive content protection)
**Researched:** 2026-02-07
**Confidence:** HIGH

## Executive Summary

Pastel v1.2 adds storage optimization and sensitive item protection to an established macOS clipboard manager. The storage problem is acute: users copying 20 screenshots per day accumulate 1.2-4.8 GB over the default 3-month retention without compression. Research confirms JPEG compression at quality 0.85 provides 5-10x storage savings with negligible visual degradation for clipboard previews. All features are implementable using zero new third-party dependencies — exclusively Apple frameworks already imported (ImageIO, SwiftUI, SwiftData, Foundation).

The recommended architecture extends existing patterns cleanly: ImageStorageService gains JPEG compression, RetentionService adds a sensitive-item purge pass, and ClipboardCardView adds blur redaction with click-to-reveal. The critical design decision is maintaining paste-back fidelity: recent images (under 24 hours) should preserve original quality, with compression applied only to older items for display purposes. For sensitive items, blur-based visual redaction without encryption is honest and appropriate — the database is already plaintext on disk, protected by macOS FileVault.

Key risks center on lossy compression degrading paste-back quality (especially transparent PNGs and text-heavy screenshots) and non-atomic purge operations leaving orphan files or records. Both are avoidable: compression must preserve originals for paste-back or use very conservative quality settings (0.85+), and purge operations must delete SwiftData records first, then clean up disk files with reconciliation tasks for partial failures. The storage dashboard is genuinely novel — no surveyed competitor offers visual storage breakdowns or category-based purge tools.

## Key Findings

### Recommended Stack

All v1.2 capabilities use Apple first-party frameworks already available on macOS 14+. Zero new third-party dependencies are required. The existing Pastel stack (Swift 6.0, SwiftUI + AppKit hybrid, SwiftData, ImageIO, CryptoKit) handles all new features.

**Core technologies:**
- **ImageIO (CGImageDestination)**: JPEG compression at configurable quality (0.7-1.0, default 0.85) — 5-10x storage savings vs current PNG storage, universally compatible paste-back, hardware-accelerated encoding
- **SwiftUI (.blur modifier)**: Sensitive content redaction with Gaussian blur (radius 10) plus lock icon overlay — more intuitive than .redacted(reason:) gray boxes, works with images and text, available since SwiftUI 1.0
- **SwiftData (Optional fields)**: isSensitive flag, isCompressed flag, originalByteCount metadata — automatic lightweight migration handles additive fields with nil defaults
- **FileManager (URLResourceValues)**: Storage dashboard disk usage calculation via directory enumeration with totalFileAllocatedSize — accurate filesystem space accounting
- **CryptoKit (SHA256)**: Extend existing contentHash deduplication to bubble re-copied items to top — same infrastructure as v1.0, behavior change not stack change
- **ByteCountFormatter**: Human-readable storage sizes for dashboard ("2.3 MB" not "2415919 bytes") — Foundation utility since macOS 10.8

**What NOT to use:**
- HEIC compression (2x slower decode vs JPEG, paste compatibility issues)
- .redacted(reason: .privacy) (looks like loading skeleton, not hidden content)
- SwiftData #Expression aggregate queries (macOS 15+ only, limited sum/avg support)
- Direct SQLite VACUUM (risky with active SwiftData context, corruption potential)

### Expected Features

Research confirms strong user expectations around storage visibility and sensitive content protection. No surveyed competitor (Maccy, PastePal, Paste 2, CopyClip) offers a storage dashboard or visual breakdown by content type.

**Must have (table stakes):**
- Image compression for storage savings (images are the #1 disk consumer)
- Duplicate bubble-up on re-copy (every major clipboard manager does this)
- Total storage usage display (users need to know app footprint)
- Mark item as sensitive (manual, not auto-detect)
- Blur/redact sensitive items in panel
- Click-to-reveal for sensitive content
- Purge all items (already exists in v1.0)

**Should have (competitive advantage):**
- Storage dashboard with visual breakdown by content type (donut chart or progress bars)
- Purge by content type (targeted cleanup without losing everything)
- Configurable sensitive item expiry (1h, 4h, 24h, same as global)
- Auto-re-blur after timed reveal (security-conscious re-hiding after 10s)
- Item count by type in dashboard
- Database compaction button (optional, see pitfall concerns)

**Defer (v2+):**
- HEIC compression (wait for decode performance improvements)
- Perceptual image deduplication (pHash is overkill for clipboard use case)
- Auto-detect sensitive content (regex for CC#/SSN has false positive risk)
- Encrypted database (complexity without real security gain given FileVault)
- Purge by age within type (compound filter, stretch goal)

### Architecture Approach

The existing architecture provides clean integration points for all v1.2 features. No major structural changes needed — services remain singleton or @MainActor-bound, SwiftData continues with automatic lightweight migration, and view-layer changes are contained to existing card components.

**Major components:**

1. **ImageStorageService (modified)**: Add JPEG compression in saveImage() method — change from PNG output to JPEG at configurable quality (0.85 default), preserve thumbnails as PNG (already small), add directory size calculation for storage dashboard, add bulk PNG-to-JPEG migration on first v1.2 launch

2. **StorageStatsService (new)**: Compute storage statistics on demand for dashboard — calculate total disk usage via FileManager enumeration, fetch item counts by type using SwiftData fetchCount with predicates, cache results briefly (30s) to avoid re-scanning on every dashboard view

3. **SensitiveContentDetector (new)**: Heuristic detection at capture time — check source app bundle ID against known password managers (1Password, Bitwarden, Keychain Access), pattern match API keys (sk-, Bearer, ghp-), conservative approach to avoid false positives, struct with static methods (no state)

4. **RetentionService (modified)**: Add sensitive-item purge pass — extend existing hourly purge with second pass for isSensitive items using configurable sensitiveRetention hours, reuse existing disk cleanup pattern, runs sequentially after normal retention purge

5. **ClipboardCardView (modified)**: Add blur redaction and click-to-reveal — @State private var isRevealed for ephemeral reveal state (resets on panel close), conditional rendering of sensitiveContentPlaceholder vs actual content, auto-hide timer after 10s reveal, context menu "Mark as Sensitive" toggle

6. **StorageSettingsView (new)**: New Settings tab for storage dashboard — donut chart or progress bars showing breakdown by type, purge-by-category buttons with confirmation, image compression quality slider, sensitive retention picker, displays human-readable sizes via ByteCountFormatter

**Data flow changes:**
- Capture pipeline: Add SensitiveContentDetector.detect() call after content classification, set isSensitive flag before modelContext.insert()
- Rendering pipeline: ClipboardCardView checks isSensitive && !isRevealed to render placeholder instead of actual content
- Retention pipeline: RetentionService runs two passes (normal retention, then sensitive retention with shorter window)
- Deduplication: Replace isDuplicateOfMostRecent check with findExistingItem(contentHash:) for full-history dedup with timestamp bump

### Critical Pitfalls

Research identified five critical pitfalls that would cause data loss, broken paste-back, or false security claims requiring major rework. Each has clear prevention strategies.

1. **Lossy image compression degrades paste-back quality** — Users copy pixel-perfect screenshots, Pastel compresses to JPEG, paste-back has artifacts. JPEG does not support alpha channel (transparency loss). Prevention: Keep originals as PNG for paste-back, compress only display thumbnails. OR use very conservative quality (0.85+) and never compress images with alpha. Never auto-compress all images globally without user awareness.

2. **Purge operations delete disk files but crash before deleting SwiftData records (or vice versa)** — Non-atomic deletion leaves orphan records (broken thumbnails) or orphan files (invisible disk usage). Prevention: Delete SwiftData records FIRST, then clean up disk files. If SwiftData fails, rollback and abort. Collect file paths before deletion. Add orphan file cleanup reconciliation task to catch partial failures.

3. **"Mark as Sensitive" creates false sense of security while data remains plaintext on disk** — Users mark API keys as "sensitive," feel protected, but content is plaintext in SQLite database readable with sqlite3 command. Prevention: Be honest in UI — use "redacted" or "hidden from view" language, NOT "secure" or "encrypted." Add tooltip: "This item is hidden in the panel. It is still stored on your Mac." Rely on macOS FileVault for at-rest encryption. Separate isSensitive (user-marked, persists) from isConcealed (auto-detected, 60s expiry).

4. **Content deduplication silently drops different content that hashes the same** — Image hashing uses only first 4KB (header collision risk for different images with same EXIF). If compression changes image bytes, same logical image has different hash before/after. Prevention: Hash more than 4KB for images (at least 64KB or full file), compute hash from ORIGINAL data before compression and never recompute after compression, consider whether @Attribute(.unique) global dedup is desired vs consecutive-only dedup.

5. **Database compaction (VACUUM) corrupts data or fails under active use** — VACUUM requires 2x disk space, fails if transaction is open, blocks writes, can corrupt if app crashes during operation. ClipboardMonitor polls every 0.5s creating high collision risk. Prevention: Do NOT implement VACUUM as user-facing feature. SQLite auto-reuses deleted pages. Offer "Delete by type" and "Delete by age" instead of compaction. If compaction is truly needed, use VACUUM INTO (creates copy without modifying original).

## Implications for Roadmap

Based on dependency analysis and risk mitigation priorities, the recommended phase structure separates storage optimization from sensitive content protection, with foundational work first and UI/management last.

### Phase 1: Image Compression Foundation
**Rationale:** Immediately reduces storage growth rate with minimal risk. No model changes. Isolated to ImageStorageService. Zero impact on existing features. Delivers tangible storage savings before any other v1.2 work.

**Delivers:** JPEG compression at quality 0.85 for stored images, 5-10x storage reduction vs current PNG storage, compression quality slider in Settings

**Addresses features:**
- Image compression for storage savings (table stakes)
- Settings integration (quality slider)

**Avoids pitfalls:**
- Pitfall 1 (lossy compression): Use conservative 0.85 quality, add alpha channel detection to skip compression for transparent images
- Verify paste-back quality with text-heavy screenshots and transparent PNGs before declaring phase complete

**Research flags:** None. JPEG compression via CGImageDestination is well-documented Apple API. Skip phase-specific research.

### Phase 2: Sensitive Item Model + Detection
**Rationale:** Adds isSensitive field that rendering and retention depend on. Small model migration. Detection is additive to capture pipeline. Must come before UI redaction but can be built in parallel with Phase 1.

**Delivers:** isSensitive Bool field on ClipboardItem, SensitiveContentDetector service, "Mark as Sensitive" context menu, auto-detection from password manager apps

**Uses stack:**
- SwiftData Optional field migration (automatic lightweight)
- Bundle ID pattern matching (Foundation)

**Addresses features:**
- Mark item as sensitive (table stakes)
- Foundation for blur redaction and expiry

**Avoids pitfalls:**
- Pitfall 3 (false security): Use "hidden" language not "secure," separate isSensitive from isConcealed, add tooltip explaining plaintext storage
- Verify migration from v1.1 database — all new fields must be Optional with nil default

**Research flags:** None. Pattern matching and model migration follow established v1.1 patterns.

### Phase 3: Blur Redaction + Click-to-Reveal
**Rationale:** Depends on isSensitive field from Phase 2. Pure view-layer change. No data model or service dependencies. Delivers the most visible user-facing feature of v1.2.

**Delivers:** Blur overlay for sensitive items (radius 10), lock icon placeholder, click-to-reveal interaction, auto-re-hide after 10s, state management via @State (ephemeral)

**Uses stack:**
- SwiftUI .blur() modifier (macOS 10.15+)
- DispatchQueue.main.asyncAfter for auto-hide timer

**Addresses features:**
- Blur/redact sensitive items (table stakes)
- Click-to-reveal (table stakes)
- Auto-re-blur after reveal (competitive)

**Avoids pitfalls:**
- Pitfall 3 (false security): Visual redaction only, no encryption claims
- Verify VoiceOver reads "Sensitive item" not actual content (accessibility label override)
- Verify reveal state resets when panel closes (ephemeral @State, not persisted)

**Research flags:** None. SwiftUI blur and state management are standard patterns.

### Phase 4: Sensitive Item Retention
**Rationale:** Depends on isSensitive field. Extends existing RetentionService. Needs Settings UI from Phase 5 but can ship standalone with hardcoded retention values initially.

**Delivers:** Sensitive-item purge pass in RetentionService (hourly), sensitiveRetention preference (1h/4h/24h/same as global), Settings picker for retention duration

**Uses stack:**
- SwiftData #Predicate filtering on isSensitive
- @AppStorage for preference
- Foundation Timer (existing hourly retention timer)

**Addresses features:**
- Configurable sensitive item expiry (competitive)

**Avoids pitfalls:**
- Pitfall 2 (non-atomic purge): Delete SwiftData first, then disk cleanup
- Auto-expiry should be opt-in (default: same as global) to avoid data loss
- Clear UI warning that sensitive items will be deleted

**Research flags:** None. Extends existing RetentionService pattern.

### Phase 5: Deduplication Enhancement
**Rationale:** Improves existing behavior without adding new features. Low risk. Can be done independently but placed here to avoid disrupting capture pipeline while Phases 2-4 are active.

**Delivers:** Bubble-to-top dedup (replace isDuplicateOfMostRecent with findExistingItem), timestamp update on re-copy, existing @Attribute(.unique) remains as safety net

**Uses stack:**
- SwiftData fetch with contentHash predicate
- Existing CryptoKit SHA256 hashing

**Addresses features:**
- Duplicate bubble-up on re-copy (table stakes)

**Avoids pitfalls:**
- Pitfall 4 (hash instability): Compute hash from original data before compression, never recompute hash after compression
- Verify image hash covers more than 4KB to avoid false collisions

**Research flags:** None. Extends existing deduplication infrastructure.

### Phase 6: Storage Dashboard + Purge-by-Category
**Rationale:** Reporting and management feature that benefits from all other features being in place. Dashboard shows data from Phases 1-5. No dependencies block this, but it delivers more value after storage optimizations are live.

**Delivers:** StorageStatsService, new Settings "Storage" tab, donut chart or progress bars by content type, item counts, disk usage (images + database), purge-by-category buttons with confirmation, ByteCountFormatter for human-readable sizes

**Uses stack:**
- FileManager directory enumeration (totalFileAllocatedSize)
- SwiftData fetchCount with predicates
- SwiftUI progress bars (simpler than Swift Charts)
- ByteCountFormatter (Foundation)

**Addresses features:**
- Storage dashboard with breakdown (competitive)
- Purge by content type (competitive)
- Item count by type (table stakes)

**Avoids pitfalls:**
- Pitfall 2 (non-atomic purge): Delete SwiftData first, disk cleanup second, add orphan file reconciliation
- Pitfall 5 (VACUUM risk): Do NOT implement database compaction button — offer targeted purge instead
- Cache storage stats (30s), calculate on dashboard open not continuously

**Research flags:** None. FileManager enumeration and SwiftData batch delete are established patterns.

### Phase Ordering Rationale

- **Phase 1 first**: Compression delivers immediate storage relief with zero risk to existing features. Can ship independently.
- **Phases 2-4 sequential**: Sensitive item support requires model (P2), then UI (P3), then lifecycle (P4). Clear dependency chain.
- **Phase 5 standalone**: Deduplication improvement is independent but placed after sensitive features to avoid churn in capture pipeline.
- **Phase 6 last**: Dashboard benefits from all features being live. Shows compression savings, sensitive item counts, etc.

**Parallel work opportunities:**
- Phase 1 (compression) and Phase 2 (sensitive model) can be built in parallel — no shared code paths
- Phase 3 (blur UI) and Phase 4 (retention) can be built in parallel after Phase 2 completes

### Research Flags

**Phases needing deeper research during planning:**
- None. All phases use well-documented Apple APIs and extend existing Pastel patterns.

**Phases with standard patterns (skip research-phase):**
- All phases. SwiftData migration, ImageIO compression, SwiftUI blur, FileManager enumeration, and batch delete are solved problems with official documentation.

**Validation checkpoints:**
- Phase 1: Paste-back quality testing with text screenshots and transparent PNGs
- Phase 2: Migration from v1.1 database with existing items
- Phase 3: VoiceOver accessibility testing
- Phase 4: Auto-expiry behavior across app restarts
- Phase 6: Orphan file reconciliation after bulk purge

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies are Apple first-party frameworks already imported and in use. JPEG compression via CGImageDestination verified in official docs. SwiftUI blur is basic API since 1.0. |
| Features | MEDIUM-HIGH | Storage dashboard is novel (no competitor offers it, so feature expectations are inferred). Sensitive item protection expectations are validated against password manager behaviors and clipboard security research. |
| Architecture | HIGH | Based on direct source code analysis of all 44 Swift files in Pastel codebase. Integration points verified against existing service patterns, SwiftData usage, and view-layer structure. |
| Pitfalls | MEDIUM-HIGH | Lossy compression risks and non-atomic purge issues verified through codebase analysis and official SQLite docs. Security pitfall concerns validated against clipboard security fundamentals. macOS 15+ screenshot protection limitations based on developer forum reports. |

**Overall confidence:** HIGH

### Gaps to Address

The following areas require validation during implementation, not additional research:

- **JPEG quality threshold for paste-back fidelity**: Research recommends 0.85 quality, but optimal value must be verified with real clipboard content (screenshots with text, UI mockups, diagrams). Test in Figma, Photoshop, and Preview to confirm no visible artifacts.

- **Image hash stability across compression**: The existing 4KB prefix hash is flagged as potentially collision-prone. During Phase 5, measure actual collision rate in production usage and decide whether to expand hash coverage to 64KB or full file.

- **Storage dashboard UI pattern**: Research suggests SwiftUI progress bars over Swift Charts for simplicity. During Phase 6, prototype both approaches and verify dark-mode compatibility and visual fit with Pastel's aesthetic.

- **Sensitive auto-expiry default**: Research recommends opt-in (default: same as global retention) to avoid accidental data loss. During Phase 4, validate with beta users whether default should be "same as global" or "24 hours" based on actual usage patterns.

- **Orphan file cleanup frequency**: Research recommends reconciliation after bulk purges. During Phase 6, decide whether to also run periodic cleanup (e.g., on app launch) or only on-demand to avoid unnecessary disk I/O.

## Sources

### Primary (HIGH confidence)
- Direct source code analysis of Pastel codebase (44 Swift files across Models, Services, Views) — integration points, existing patterns, data flow
- Apple Documentation: kCGImageDestinationLossyCompressionQuality — JPEG compression API
- Apple Documentation: URLResourceValues.totalFileAllocatedSize — disk size calculation
- Apple Documentation: SwiftUI blur(radius:opaque:) — blur modifier
- Apple Documentation: ByteCountFormatter — human-readable sizes
- SQLite VACUUM documentation — database compaction mechanics and risks
- OSLog privacy documentation — log privacy markers for sensitive data

### Secondary (MEDIUM confidence)
- HEIC vs JPEG comparison (Adobe, Cloudinary) — compression ratios and decode performance
- SwiftData batch delete API (Fat Bob Man, Apple docs) — batch operations with predicates
- SwiftUI redacted modifier (Swift with Majid) — redaction approaches
- FileManager directory size patterns (Nikolai Ruhe gist, MacPaw) — disk size calculation best practices
- SwiftData Expressions (Use Your Loaf) — aggregate query limitations in macOS 14/15
- Core Data VACUUM approach (Marco Eidinger) — SQLite compaction from Swift
- macOS Tahoe clipboard privacy (9to5Mac, MacWorld) — 8-hour retention, privacy prompts
- Clipboard security fundamentals (Ctrl Blog) — plaintext storage risks
- Hash collision risks in deduplication (BackupCentral) — false positive implications

### Tertiary (LOW confidence)
- Competitor feature analysis (PastePal, Maccy, Paste 2) — inferred from app descriptions and GitHub, not direct testing
- macOS 15+ screenshot protection (Apple Developer Forums) — ScreenCaptureKit ignoring sharingType based on forum reports, not official documentation
- Password manager clipboard behavior (1Password community, Bitwarden GitHub) — ConcealedType reliability issues based on user reports

---
*Research completed: 2026-02-07*
*Ready for roadmap: yes*
