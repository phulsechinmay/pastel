# Feature Research: v1.5 iCloud Sync

**Domain:** macOS Clipboard Manager -- iCloud Sync of Clipboard History
**Project:** Pastel
**Researched:** 2026-02-14
**Confidence:** MEDIUM-HIGH (sync patterns well-established across competitors; CloudKit specifics need phase-level research; conflict resolution UX has limited precedent in this category)

> **Scope:** This document covers v1.5 sync features only: iCloud sync toggle, sync-aware retention, conflict resolution, sync status indicators, privacy controls for sync, and selective sync. For v1.3 feature research, see git history.

---

## Competitive Landscape: How Competitors Handle Sync

### Competitor Sync Feature Matrix

| Feature | Paste | PastePal | Awesome Copy | Copier | PasteNow | CleanClip | Maccy |
|---------|-------|----------|--------------|--------|----------|-----------|-------|
| iCloud sync | Yes | Yes | Yes | Yes | Yes | Yes (beta) | No |
| Sync on by default | Yes (with iCloud) | No (opt-in) | Yes | No (opt-in) | Yes | Yes | N/A |
| Image sync | Yes | Yes (via iCloud Drive) | Yes | Yes | Yes | Unknown | N/A |
| Sync status indicator | No visible | No visible | No visible | No visible | No visible | No visible | N/A |
| Selective sync | No (all or nothing) | No | No | No | No | No | N/A |
| Conflict resolution UX | None visible | None visible | None visible | None visible | None visible | None visible | N/A |
| E2E encryption claim | iCloud standard | iCloud standard | Yes (claimed) | Yes (AES-256) | iCloud standard | Yes (claimed) | N/A |
| Shared/collab features | Shared Pinboards | No | No | No | No | No | N/A |
| Subscription required | Yes | No (one-time) | No (one-time) | No (one-time) | No (one-time) | Yes | N/A |
| Privacy app exclusion | Yes | Yes (allow/ignore lists) | Yes | Unknown | Unknown | Unknown | Yes (local only) |
| Sync retention separate | No (unified) | No (unified) | No (unified) | No (unified) | No (unified) | No (unified) | N/A |

**Key finding:** No competitor exposes sync conflict resolution, sync status, or selective sync to users. Sync is treated as invisible infrastructure -- it either works or it does not. This is both the industry norm and an opportunity for differentiation through transparency.

### How Competitors Structure Sync

**Paste (market leader for sync):**
- Syncs via iCloud automatically once signed in
- Uses iCloud Drive under the hood (Settings > Apple ID > iCloud Drive > Options > Paste)
- First sync may take minutes for large histories; subsequent syncs are item-by-item
- Shared Pinboards for team collaboration (unique feature, requires subscription)
- Troubleshooting: users must verify iCloud Drive is enabled, Paste checkbox is on
- Reset option: delete Paste's iCloud data and re-sync from scratch
- Source: [Paste Help Center](https://pasteapp.io/help/icloud-sync-doesn-t-work) (MEDIUM)

**PastePal:**
- iCloud sync disabled by default, enabled in Settings
- Separate iCloud Drive toggle for image sync (text syncs via CloudKit, images via iCloud Drive)
- "Nothing will be overwritten with something newer" -- conflict prevention over resolution
- Allow/ignore lists for app filtering (affects what gets synced by proxy)
- Source: [PastePal Docs](https://docs.indiegoodies.com/pastepal/Mac/features/icloud-drive), [PastePal App Store](https://apps.apple.com/us/app/clipboard-manager-pastepal/id1503446680) (MEDIUM)

**Awesome Copy:**
- E2E encrypted iCloud sync
- Excludes apps from tracking (password managers auto-detected)
- Auto-clear clipboard on sleep/lock (prevents sensitive data from syncing)
- One-time purchase model
- Source: [Awesome Copy](https://awesomecopy.app/) (MEDIUM)

**Copier:**
- Optional iCloud sync, works fully offline when disabled
- AES-256 encryption, TLS 1.3 in transit
- Preserves original format for all content types
- Source: [Copier](https://www.trycopier.app/) (MEDIUM)

**Cloud Snippets (notable for sync UX):**
- Only app found with "Sync status indicated in Menu Bar icon"
- This is the only competitor with visible sync state feedback
- Source: [Cloud Snippets](https://cloudsnippets.twoint.com/) (MEDIUM)

### What Users Actually Complain About

Based on App Store reviews, help center articles, and forum posts:

1. **"Sync is slow on first setup"** -- Large initial syncs take minutes, users think it is broken
2. **"Items not appearing on other device"** -- Usually an iCloud Drive configuration issue
3. **"Duplicates after sync"** -- Poor deduplication creates repeated items
4. **"Using too much iCloud storage"** -- Image-heavy histories consume quota quickly
5. **"No way to know if sync is working"** -- Zero feedback about sync state

Source: [Paste Help Center](https://pasteapp.io/help), App Store reviews for PastePal and Paste (MEDIUM)

---

## Table Stakes

Features users expect from any clipboard manager that claims iCloud sync. Missing any of these makes the feature feel broken or incomplete.

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| **Sync on/off toggle** | Every competitor with sync makes it opt-in or at minimum toggleable. Users demand control over what goes to cloud. PastePal, Copier both default to off. | LOW | Settings infrastructure (Phase 5, done) | Default OFF. Single toggle in Settings. Must fully disconnect from CloudKit when off. |
| **Text content sync** | Core value proposition. Text, URLs, code, color values are the primary clipboard content types. | HIGH | ClipboardItem model, CloudKit schema | Sync textContent, htmlContent, contentType, timestamp, sourceAppName, title, detectedLanguage, detectedColorHex. Exclude rtfData (binary, large) from initial sync. |
| **Label sync** | Labels are organizational metadata that users create intentionally. Losing labels on another device defeats their purpose. | MEDIUM | Label model, many-to-many relationship | Must handle label merge conflicts (same name, different color on two devices). |
| **Concealed item exclusion** | Items marked with ConcealedType (password manager content) must NEVER sync to iCloud. This is a hard privacy requirement. | LOW | isConcealed field on ClipboardItem | Filter predicate: only sync items where isConcealed == false. Non-negotiable. |
| **Ignore-list respect for sync** | Items captured from ignored apps should not sync (they should not exist in the first place, but defense-in-depth). | LOW | Privacy ignore list (Phase 14, done) | Items from ignored apps are already not captured, but verify no edge cases leak through. |
| **Deduplication across devices** | When the same text is copied on two devices, it should not appear twice. contentHash already exists for this. | MEDIUM | contentHash field (unique constraint) | Use contentHash as the CloudKit record ID or a secondary index. Same content = same record. |
| **Retention applies to synced items** | Users set retention to "3 months" -- synced items older than 3 months should still be purged locally and remotely. | MEDIUM | RetentionService (done), CloudKit delete propagation | RetentionService must delete from CloudKit when purging locally. |
| **Works with App Sandbox** | Pastel ships via App Store with sandbox enabled. CloudKit works within sandbox. | LOW | Entitlements, iCloud container | Add com.apple.developer.icloud-container-identifiers entitlement. CloudKit is sandbox-compatible. |

---

## Differentiators

Features that would set Pastel apart. No competitor currently offers these, but they address real user pain points identified in research.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| **Sync status indicator** | Only Cloud Snippets shows sync state. Every other competitor leaves users guessing. A small cloud icon with status (synced/syncing/error/offline) in the panel header or menu bar gives confidence. | MEDIUM | Panel UI, sync engine state machine | States: synced (checkmark), syncing (animated), error (exclamation), offline (slash), disabled (hidden). Subtle -- not prominent. |
| **Sync-aware retention (separate limits)** | No competitor separates local vs cloud retention. Users with "Forever" local retention may not want unlimited iCloud usage. Offering "Keep in iCloud for: 1 month / 3 months / 1 year" independent of local retention gives storage control. | MEDIUM | RetentionService extension, new UserDefaults key | Cloud retention <= local retention (enforced). Default cloud retention = match local. |
| **Content type filtering for sync** | Let users choose WHICH types sync: text yes, URLs yes, code yes, colors no, files no. No competitor offers this granularity. | LOW | Sync predicate filter, Settings UI | Simple checklist in sync settings. Default: all syncable types on. |
| **Per-item sync exclusion** | Right-click an item > "Don't sync this item." Marks it as local-only. Power user feature for one-off sensitive copies that passed the ignore list. | LOW | New boolean field on ClipboardItem: isSyncExcluded | Context menu addition, simple predicate filter in sync. |
| **First-sync progress indicator** | Users report first sync feels broken due to silence. Show "Syncing 142 of 500 items..." during initial sync. | MEDIUM | Sync engine progress reporting, Settings or panel UI | Only appears during initial sync or large backfill. Dismisses automatically. |
| **Device attribution** | Show which device an item was copied on: "Copied on MacBook Pro" vs "Copied on iMac". No competitor shows this. | LOW | Add deviceName field to CloudKit record (Host.current().localizedName) | Subtle metadata shown in card detail or tooltip. Helps users track provenance. |

---

## Anti-Features

Features to explicitly NOT build for v1.5. Each was considered and rejected with specific rationale.

| Anti-Feature | Why It Seems Appealing | Why Avoid | What to Do Instead |
|--------------|----------------------|-----------|-------------------|
| **Image sync** | "Sync everything!" Images are clipboard content. | Images are 10-1000x larger than text. A single screenshot is 2-5MB. 100 screenshots = 500MB of iCloud quota. PastePal separates this into a distinct iCloud Drive feature for good reason. Text-first sync validates the architecture without storage quota risk. | Defer to v1.6. Architecture should SUPPORT image sync (record structure allows it) but not enable it. |
| **Real-time push sync** | "I want items to appear instantly on all devices!" | CloudKit push notifications exist but are best-effort with no guaranteed latency. Building UX expectations around instant sync leads to bug reports. | Use CloudKit subscriptions for background notification + periodic polling (every 30-60 seconds when app is active). Items appear within a minute, not instantly. |
| **End-to-end encryption beyond iCloud** | "Encrypt everything client-side before CloudKit!" | CloudKit Encrypted Data fields exist but prevent server-side querying/sorting. Would need to sync ALL records and decrypt locally for search. Massive performance hit. iCloud already encrypts at rest and in transit. | Use standard CloudKit fields. Rely on iCloud's built-in encryption. Document this in privacy policy. Users who need more can disable sync. |
| **Cross-Apple-ID sync** | "Sync between my work and personal Apple ID!" | Requires a custom server, authentication system, and networking infrastructure. Fundamentally different product. | Out of scope. iCloud sync = same Apple ID only. |
| **iOS companion app sync** | "Sync to my iPhone!" | Requires building an entire iOS app. Different platform, different clipboard APIs, different UI paradigms. | macOS-to-macOS only for v1.5. Architecture should not prevent future iOS support, but do not build for it. |
| **Shared clipboards between users** | Paste 5.0 has "Shared Pinboards" -- should Pastel? | Requires CloudKit Sharing, access control, invitation flows, and a fundamentally different data model. This is a collaboration feature, not a sync feature. | Out of scope. Paste charges a subscription for this feature because it is expensive to build and maintain. |
| **Selective sync by label** | "Only sync items with the 'Work' label!" | Label assignment happens AFTER capture. By the time a user labels an item, it may have already synced. Creates confusing "undo sync" scenarios. | Content type filtering (text/URL/code) is a better granularity -- it is known at capture time and does not change. |
| **Sync history/audit log** | "Show me what synced when!" | Adds storage overhead, UI complexity, and minimal user value. | Sync status indicator (synced/syncing/error) provides sufficient feedback without the log. |
| **Automatic conflict resolution with merge** | "Merge edits from both devices intelligently!" | Clipboard items are immutable after capture. The only mutable fields are title and labels. Merging title edits is ambiguous (which title wins?). | Last-write-wins for metadata changes (title, labels). Items themselves are immutable -- no merge needed. |

---

## Feature Dependencies

```
[Sync Toggle (Settings)]
    |-- requires --> Settings infrastructure (Phase 5, DONE)
    |-- requires --> CloudKit container setup (entitlements)
    |-- BLOCKS --> all other sync features (must be first)

[CloudKit Schema + Sync Engine]
    |-- requires --> Sync Toggle
    |-- requires --> ClipboardItem model knowledge
    |-- requires --> Label model knowledge
    |-- requires --> contentHash for deduplication
    |-- BLOCKS --> all data sync features

[Text Content Sync]
    |-- requires --> CloudKit Schema + Sync Engine
    |-- requires --> ClipboardItem fields mapping to CKRecord
    |-- BLOCKS --> Sync Status Indicator (needs working sync to show status)
    |-- BLOCKS --> Sync-Aware Retention (needs synced data to retain/purge)

[Label Sync]
    |-- requires --> CloudKit Schema + Sync Engine
    |-- requires --> Label model mapping to CKRecord
    |-- requires --> Text Content Sync (labels reference items)
    |-- conflict resolution: same-name labels across devices

[Concealed Item Exclusion]
    |-- requires --> Sync Engine (filter predicate)
    |-- INDEPENDENT: can be wired as a sync predicate from day one
    |-- must be part of initial sync engine implementation (not a later addition)

[Sync Status Indicator]
    |-- requires --> Sync Engine with state reporting
    |-- requires --> Panel UI or menu bar integration
    |-- INDEPENDENT of retention and conflict resolution

[Sync-Aware Retention]
    |-- requires --> RetentionService (DONE)
    |-- requires --> Sync Engine (CloudKit delete propagation)
    |-- requires --> New "cloud retention" UserDefaults key
    |-- INDEPENDENT of sync status

[Conflict Resolution]
    |-- requires --> Sync Engine operational
    |-- requires --> Label Sync (label conflicts are the primary concern)
    |-- title conflict: last-write-wins with timestamp comparison
    |-- label conflict: merge (union of labels from both devices)

[Device Attribution]
    |-- requires --> Sync Engine (deviceName field in CKRecord)
    |-- requires --> Panel card UI update (show device name)
    |-- INDEPENDENT, can be added at any point

[Content Type Filtering]
    |-- requires --> Sync Toggle (settings UI)
    |-- requires --> Sync Engine (predicate filter)
    |-- INDEPENDENT, can be added at any point

[Per-Item Sync Exclusion]
    |-- requires --> Sync Engine
    |-- requires --> New field on ClipboardItem (isSyncExcluded)
    |-- requires --> Context menu update
    |-- INDEPENDENT, can be added at any point
```

### Critical Path

```
Entitlements + CloudKit Container
    -> Sync Toggle in Settings
        -> CloudKit Schema Design
            -> Sync Engine (push/pull/dedup)
                -> Text + Label Sync (core feature)
                    -> Conflict Resolution
                    -> Sync Status Indicator
                    -> Sync-Aware Retention
```

---

## Sync UX Patterns (from Competitor Research)

### Sync Toggle Pattern

Every competitor that offers sync uses the same pattern:

1. Toggle in Settings (not a first-run wizard)
2. Off by default (PastePal, Copier) OR on automatically if iCloud is available (Paste, Awesome Copy)
3. Disabling sync does NOT delete cloud data (allows re-enabling later)
4. No confirmation dialog for enabling (low friction)
5. Warning or confirmation for disabling ("Your cloud data will remain but stop updating")

**Recommendation for Pastel:** Off by default. Enable with single toggle. First enable triggers initial upload of existing local history. Show progress during first sync. Disable toggle shows confirmation: "Sync will stop. Your data in iCloud will not be deleted. You can re-enable sync anytime."

### Conflict Resolution Pattern

No competitor exposes conflict resolution UX to users. The universal approach:

1. **Items are immutable after creation** -- no content conflicts possible
2. **Metadata conflicts (title, labels) use last-write-wins** -- timestamp comparison
3. **Deduplication by content hash** -- same content = same record
4. **Label name collisions** -- if both devices create a label called "Work" with different colors, the most-recently-modified version wins

**Recommendation for Pastel:** Follow the industry pattern. No user-facing conflict resolution UI. Use last-write-wins for mutable metadata. Use contentHash for item deduplication. For label conflicts, merge by name with last-write-wins for properties (color, emoji, sortOrder).

### Sync Status Pattern

Almost no competitor shows sync status. The one exception (Cloud Snippets) uses a menu bar icon state.

**Recommendation for Pastel:** Subtle sync badge in the panel header (next to search bar or settings gear). States:

| State | Visual | Tooltip | When |
|-------|--------|---------|------|
| Synced | Small cloud with checkmark (SF Symbol: cloud.fill) | "All items synced" | Steady state, all records uploaded/downloaded |
| Syncing | Small cloud with arrows (animated) | "Syncing 12 items..." | During active push/pull operations |
| Error | Small cloud with exclamation | "Sync error. Check iCloud settings." | CloudKit error, auth failure, quota exceeded |
| Offline | Small cloud with slash | "Offline. Will sync when connected." | No network connectivity |
| Disabled | Hidden (no indicator) | N/A | Sync toggle is off |

This is more transparent than any competitor while remaining unobtrusive.

### Privacy Controls for Sync

Competitor patterns for sync privacy:

1. **App ignore list** (already built in Pastel): Items from ignored apps never enter the database, so they never sync
2. **Concealed content handling**: Password manager content (ConcealedType) auto-expires in 60 seconds locally -- must ALSO be excluded from sync
3. **Manual exclusion**: No competitor offers per-item "don't sync" -- but it is a natural extension of the existing context menu
4. **Content type filtering**: No competitor offers this -- but it is simple and powerful

**Recommendation for Pastel:** Layer privacy controls:
1. **Layer 1 (automatic):** Concealed items never sync (hard rule, not user-configurable)
2. **Layer 2 (existing):** Ignored-app items never captured, thus never sync
3. **Layer 3 (new, optional):** Content type filter in sync settings (default: all types on)
4. **Layer 4 (new, optional):** Per-item "Don't sync" via context menu

### Retention for Sync

No competitor separates local and cloud retention. All use unified retention where local retention = cloud retention.

**Recommendation for Pastel:** Offer TWO retention settings:

| Setting | Controls | Default | Options |
|---------|----------|---------|---------|
| Local retention | How long items stay on THIS Mac | Existing setting (user's choice, e.g. 3 months) | 1 week, 1 month, 3 months, 1 year, forever |
| Cloud retention | How long items stay in iCloud | Match local retention | 1 week, 1 month, 3 months, 1 year, match local |

**Why separate?** A user may want "Forever" locally (disk is cheap) but "3 months" in iCloud (iCloud storage costs money). The constraint is: cloud retention <= local retention (cannot keep items in cloud longer than they exist locally, since we need the local copy as source of truth).

**Implementation:** RetentionService runs two purge passes:
1. Local purge (existing): delete items older than local retention
2. Cloud purge (new): delete CloudKit records for items older than cloud retention (items stay local)

---

## MVP Recommendation

### Phase 1 (Core): Must ship together
1. **Sync on/off toggle** -- Gate for everything else
2. **CloudKit schema + sync engine** -- The infrastructure
3. **Text content sync** -- The core value
4. **Concealed item exclusion** -- Non-negotiable privacy
5. **Deduplication via contentHash** -- Prevents duplicate chaos

### Phase 2 (Completeness): Ship shortly after
6. **Label sync with conflict resolution** -- Labels are part of the core experience
7. **Sync status indicator** -- Users need to know sync is working
8. **Sync-aware retention** -- Prevents iCloud storage runaway

### Phase 3 (Polish): Differentiators
9. **Device attribution** -- "Copied on MacBook Pro"
10. **Content type filtering** -- Choose what syncs
11. **Per-item sync exclusion** -- Power user privacy control
12. **First-sync progress indicator** -- Onboarding polish

### Defer to v1.6
- Image sync (architecture supports it, toggle enables it)
- RTF data sync (binary, large, low priority)

---

## Competitor Feature Gap Analysis

Where Pastel v1.5 would stand relative to competitors:

| Capability | Industry Norm | Pastel v1.5 Plan | Advantage |
|-----------|---------------|------------------|-----------|
| Sync toggle | All have it | Yes, off by default | Matches norm |
| Text/URL/code sync | All have it | Yes | Matches norm |
| Image sync | Most have it | Deferred (v1.6) | Gap -- acceptable for v1.5 |
| Sync status | None show it (except Cloud Snippets menu bar) | Panel badge with 4 states | **Differentiator** |
| Separate cloud retention | None offer it | Separate local/cloud retention | **Differentiator** |
| Content type filter | None offer it | Checklist for syncable types | **Differentiator** |
| Per-item exclusion | None offer it | Context menu "Don't sync" | **Differentiator** |
| Device attribution | None show it | "Copied on [device]" | **Differentiator** |
| Conflict resolution UX | None expose it | Last-write-wins (invisible) | Matches norm |
| E2E encryption | Some claim it | iCloud standard encryption | Matches norm |
| First-sync progress | None show it | Progress indicator | **Differentiator** |
| Subscription required | Paste yes, others no | No (free feature) | Advantage over Paste |

**Summary:** Pastel would match competitors on table stakes while offering 5-6 features no competitor has. The main gap is image sync, which is intentionally deferred.

---

## Sources

### Competitor Analysis
- [Paste - Official Site](https://pasteapp.io/) -- Sync features, pinboards, pricing (MEDIUM)
- [Paste Help Center - iCloud Sync Troubleshooting](https://pasteapp.io/help/icloud-sync-doesn-t-work) -- Sync architecture, common issues (MEDIUM)
- [Paste 5.0 - Shared Pinboards](https://pasteapp.io/paste-5) -- Collaboration features (MEDIUM)
- [PastePal - Official Site](https://indiegoodies.com/pastepal) -- Feature list, sync toggle (MEDIUM)
- [PastePal - iCloud Drive Docs](https://docs.indiegoodies.com/pastepal/Mac/features/icloud-drive) -- Image sync via iCloud Drive (MEDIUM)
- [PastePal - App Store](https://apps.apple.com/us/app/clipboard-manager-pastepal/id1503446680) -- Feature list, sync disabled by default (MEDIUM)
- [Awesome Copy](https://awesomecopy.app/) -- E2E encryption, app exclusion, auto-clear (MEDIUM)
- [Copier](https://www.trycopier.app/) -- AES-256, optional sync, offline support (MEDIUM)
- [Cloud Snippets](https://cloudsnippets.twoint.com/) -- Sync status in menu bar icon (MEDIUM)
- [PasteNow](https://pastenow.app/) -- iCloud sync, cross-platform (MEDIUM)
- [Maccy](https://maccy.app/) -- No sync, local only (HIGH)
- [CleanClip](https://cleanclip.cc/) -- Sync features, context-aware intelligence (LOW)

### User Pain Points
- [Paste Review 2026](https://josephnilo.com/blog/paste-setapp-review/) -- User experience with sync (MEDIUM)
- [6 Best Clipboard Manager Mac Apps 2026](https://www.drbuho.com/review/clipboard-manager-mac) -- Comparative overview (LOW)
- [PastePal Review - MacSources](https://macsources.com/pastepal-clipboard-manager-for-macos-review/) -- Sync reliability notes (MEDIUM)

### Privacy and Security
- [Ctrl Blog - Clipboard Security](https://www.ctrl.blog/entry/clipboard-security.html) -- Clipboard privacy risks (MEDIUM)
- [SaneClip](https://saneclip.com/) -- Touch ID clipboard protection pattern (LOW)

**Gaps requiring phase-specific research:**
- CloudKit schema design: exact CKRecord field types and relationships
- CloudKit subscription types: which notification mechanism for sync triggers
- SwiftData + CloudKit interaction: whether to use NSPersistentCloudKitContainer or manual CloudKit sync alongside SwiftData
- CloudKit quota limits and rate limiting behavior
- Sandbox entitlements required for CloudKit in App Store distribution

---
*Feature research for: Pastel v1.5 -- iCloud Sync*
*Researched: 2026-02-14*
