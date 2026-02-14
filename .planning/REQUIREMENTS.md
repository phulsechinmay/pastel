# Requirements: Pastel

**Defined:** 2026-02-05
**Core Value:** Clipboard history is always one hotkey away, with instant paste-back into any app.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Clipboard Monitoring

- [x] **CLIP-01**: App captures text copied to system clipboard
- [x] **CLIP-02**: App captures images copied to system clipboard
- [x] **CLIP-03**: App captures URLs copied to system clipboard
- [x] **CLIP-04**: App captures file references copied to system clipboard
- [x] **CLIP-05**: Clipboard history persists across app/system restarts
- [x] **CLIP-06**: Consecutive duplicate copies are not stored twice

### Panel UI

- [x] **PNUI-01**: Screen-edge sliding panel displays clipboard history as cards
- [x] **PNUI-02**: Panel slides in/out with smooth animation
- [x] **PNUI-03**: Panel position configurable to top, left, right, or bottom edge
- [x] **PNUI-04**: Panel activated via global hotkey
- [x] **PNUI-05**: Cards show image thumbnail for image items
- [x] **PNUI-06**: Cards show URL text distinctly for URL items
- [x] **PNUI-07**: Cards show text preview for text items
- [x] **PNUI-08**: Cards show file name/path for file items
- [x] **PNUI-09**: User can navigate cards with arrow keys and paste with Enter
- [x] **PNUI-10**: Panel uses always-dark theme

### Paste

- [x] **PAST-01**: User can double-click a card to paste its content into the active app
- [x] **PAST-02**: App requests Accessibility permission on first launch with clear explanation
- [x] **PAST-03**: Panel does not steal focus from the active app (non-activating panel)

### Organization

- [x] **ORGN-01**: User can search clipboard history by text content
- [x] **ORGN-02**: User can create labels
- [x] **ORGN-03**: User can assign labels to clipboard items
- [x] **ORGN-04**: Chip bar in panel allows filtering by label
- [x] **ORGN-05**: User can delete individual clipboard items
- [x] **ORGN-06**: User can clear all clipboard history

### App Infrastructure

- [x] **INFR-01**: App lives in menu bar with no dock icon
- [x] **INFR-02**: App can be set to launch at login
- [x] **INFR-03**: Settings window accessible from menu bar
- [x] **INFR-04**: Images stored on disk with thumbnails, not in database

## v1.1 Requirements

Requirements for v1.1 milestone: Rich Content & Enhanced Paste.

### Rich Content -- Code Detection

- [x] **RICH-01**: App detects code snippets via multi-signal heuristic and classifies them as `.code` ContentType
- [x] **RICH-02**: Code cards show syntax-highlighted previews with auto-detected language (via HighlightSwift)
- [x] **RICH-03**: Code cards display a language badge (e.g., "Swift", "Python")

### Rich Content -- Color Detection

- [x] **RICH-04**: App detects standalone color values (hex, rgb, hsl) and classifies them as `.color` ContentType
- [x] **RICH-05**: Color cards show a visual swatch alongside the original color text

### Rich Content -- URL Previews

- [x] **RICH-06**: App auto-fetches URL metadata (title, favicon, og:image) after URL item is captured
- [x] **RICH-07**: URL cards show source app icon + timestamp header, og:image preview, and favicon + title footer
- [x] **RICH-08**: URL metadata fetch is non-blocking with graceful fallback to plain URL card on failure
- [x] **RICH-09**: Settings toggle to disable URL metadata fetching

### Enhanced Paste -- Quick Paste Hotkeys

- [x] **PAST-10**: Cmd+1-9 pastes the Nth visible item while the panel is open
- [x] **PAST-10b**: Cmd+Shift+1-9 pastes the Nth visible item as plain text (RTF stripped)
- [x] **PAST-11**: Settings toggle to enable/disable quick paste hotkeys (enabled by default)
- [x] **PAST-12**: First 9 panel cards show keycap-style position badges when hotkeys are enabled

### Label Enhancements

- [x] **LABL-01**: Label color palette expanded from 8 to 12 colors (add teal, indigo, brown, mint)
- [x] **LABL-02**: Labels support optional emoji that replaces the color dot in chips and card headers
- [x] **LABL-03**: Label settings view provides emoji input (system emoji picker accessible via keyboard)

## v1.2 Requirements

Requirements for v1.2 milestone: Item Management.

### Item Management

- [x] **ITEM-01**: User can assign custom titles to clipboard items
- [x] **ITEM-02**: User can assign multiple labels to a single clipboard item
- [x] **ITEM-03**: User can edit item title and labels via right-click "Edit" modal
- [x] **ITEM-04**: Search matches against item titles in addition to content
- [x] **ITEM-05**: Items with multiple labels display all label chips on cards
- [x] **ITEM-06**: Chip bar filtering shows items with ANY selected label (OR logic)

### History Browser

- [x] **HIST-01**: Settings has "History" tab with full clipboard history in responsive grid
- [x] **HIST-02**: History browser supports same search and label filtering as panel
- [x] **HIST-03**: User can multi-select items via Cmd-click, Shift-click, and Cmd+A
- [x] **HIST-04**: User can bulk copy selected items (concatenate with newlines)
- [x] **HIST-05**: User can bulk paste selected items into active app
- [x] **HIST-06**: User can bulk delete selected items with confirmation dialog

## v1.3 Requirements

Requirements for v1.3 milestone: Power User Features.

### Enhanced Paste -- Plain Text Support

- [ ] **PAST-20**: Context menu shows "Paste as Plain Text" option on all clipboard cards
- [ ] **PAST-21**: Shift+Enter pastes selected item as plain text (RTF and HTML stripped)
- [ ] **PAST-22**: Shift+double-click pastes item as plain text
- [ ] **PAST-23**: Plain text paste correctly strips ALL formatting (fix existing HTML bug in PasteService)

### Privacy -- App Filtering

- [x] **PRIV-01**: User can configure ignore-list of apps to exclude from clipboard monitoring
- [x] **PRIV-02**: Settings has "Privacy" section with app ignore-list management
- [x] **PRIV-03**: User can add apps to ignore-list via app picker showing running apps
- [x] **PRIV-04**: User can remove apps from ignore-list
- [x] **PRIV-05**: ClipboardMonitor respects ignore-list during capture (skips ignored app bundles)

### Data Portability -- Import/Export

- [x] **DATA-01**: User can export clipboard history to `.pastel` file (JSON format)
- [x] **DATA-02**: Export preserves all metadata (titles, labels, timestamps, source apps, content)
- [x] **DATA-03**: Export format excludes images (text-based export only)
- [x] **DATA-04**: User can import clipboard history from `.pastel` file
- [x] **DATA-05**: Import handles duplicate content gracefully (skip or update timestamp)
- [x] **DATA-06**: Import preserves label relationships and creates missing labels
- [x] **DATA-07**: Settings has "Import/Export" section with export and import buttons
- [x] **DATA-08**: Export/import shows progress feedback for large histories

### Advanced Interaction -- Drag-and-Drop

- [x] **DRAG-01**: User can drag clipboard items from panel to other applications
- [x] **DRAG-02**: Drag-and-drop supports text, images, URLs, and files
- [x] **DRAG-03**: Drag provides correct NSItemProvider UTTypes for receiving apps
- [x] **DRAG-04**: Panel remains visible during drag session (does not dismiss on drag)
- [x] **DRAG-05**: Drag session does not trigger clipboard monitor self-capture

## v1.5 Requirements

Requirements for v1.5 milestone: iCloud Sync (minimal core).

### CloudKit-Compatible Data Model

- [ ] **SYNC-01**: Data model is CloudKit-compatible (no unique constraints, all properties have defaults, relationships optional)
- [ ] **SYNC-02**: Application-level content hash deduplication replaces @Attribute(.unique) constraint
- [ ] **SYNC-03**: ClipboardItem has originDeviceID field stamped at capture time (per-device UUID from UserDefaults)
- [ ] **SYNC-04**: Existing local data migrates cleanly to CloudKit-compatible schema without data loss

### iCloud Sync Infrastructure

- [ ] **SYNC-05**: App has iCloud + CloudKit + Push Notifications entitlements and CloudKit.framework linked
- [ ] **SYNC-06**: ModelContainer configured with cloudKitDatabase: .automatic when sync enabled, .none when disabled
- [ ] **SYNC-07**: Clipboard items (text, URL, code, color) sync across Macs logged into the same Apple ID
- [ ] **SYNC-08**: Labels sync across devices with relationships preserved

### Sync Controls

- [ ] **SYNC-09**: Settings has sync on/off toggle (off by default) with app restart prompt
- [ ] **SYNC-10**: Concealed items (isConcealed = true) are never synced to iCloud
- [ ] **SYNC-11**: Image and file items are excluded from sync (text-only sync for v1.5)

### Sync Reliability

- [ ] **SYNC-12**: Cross-device duplicate items are detected and merged by contentHash (keep earliest, merge labels)
- [ ] **SYNC-13**: Lightweight sync monitor observes NSPersistentCloudKitContainer events and exposes sync state
- [ ] **SYNC-14**: Sync status indicator in Settings shows current state (synced/syncing/error/offline/disabled)

## Future Requirements

Deferred to future releases. Tracked but not in current roadmap.

### Enhanced Paste

- **PAST-30**: User can paste with formatting options (keep source, match destination, plain text) via submenu

### History Management

- **HIST-10**: User can pin/favorite items that persist beyond retention limits
- **HIST-11**: User can star frequently used items for quick access

### Privacy

- **PRIV-10**: User can configure allow-list mode (only monitor specific apps)
- **PRIV-11**: Settings shows real-time filtering status indicator

### Data Portability

- **DATA-10**: Selective export by date range, labels, or content type
- **DATA-11**: Import from other clipboard manager formats (Maccy, Paste 2, CopyClip)
- **DATA-12**: Export includes images (directory bundle format)

### iCloud Sync Enhancements

- **SYNC-20**: Sync status badge in panel header (not just Settings)
- **SYNC-21**: Separate local/cloud retention limits
- **SYNC-22**: Device attribution ("Copied on MacBook Pro") shown on synced items
- **SYNC-23**: Content type filtering for sync (choose what types sync)
- **SYNC-24**: Per-item sync exclusion via context menu
- **SYNC-25**: First-sync progress indicator
- **SYNC-26**: Image sync support

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Image sync (v1.5) | Images are 10-1000x larger than text. Deferred to future version to avoid iCloud quota issues |
| iOS companion app | macOS only. Entirely different platform |
| Snippet templates / text expansion | Different product category (TextExpander, Typinator). Dilutes focus |
| Browser extension integration | NSPasteboard already captures browser copies. No extension needed |
| AI-powered features | Adds latency, cost, complexity. Tangential to core clipboard value |
| Real-time collaboration / shared clipboard | Requires CloudKit Sharing, access control, invitation flows. Different product category |
| Plugin/extension system | Massive API surface. Premature |
| Clipboard rules / automation | Rules engines are complex. Users who want this use Keyboard Maestro |
| Multi-window / detachable panels | Window management complexity multiplies. Single configurable panel |
| E2E encryption beyond iCloud | Prevents server-side querying/sorting. iCloud encrypts at rest and in transit |
| Custom theming / light mode | Always-dark is a feature. Ship one polished theme |
| Cross-Apple-ID sync | Requires custom server infrastructure. Same Apple ID only |
| Custom conflict resolution UI | Clipboard items are immutable. Last-writer-wins is sufficient for metadata |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CLIP-01 | Phase 1 | Complete |
| CLIP-02 | Phase 1 | Complete |
| CLIP-03 | Phase 1 | Complete |
| CLIP-04 | Phase 1 | Complete |
| CLIP-05 | Phase 1 | Complete |
| CLIP-06 | Phase 1 | Complete |
| PNUI-01 | Phase 2 | Complete |
| PNUI-02 | Phase 2 | Complete |
| PNUI-03 | Phase 5 | Complete |
| PNUI-04 | Phase 3 | Complete |
| PNUI-05 | Phase 2 | Complete |
| PNUI-06 | Phase 2 | Complete |
| PNUI-07 | Phase 2 | Complete |
| PNUI-08 | Phase 2 | Complete |
| PNUI-09 | Phase 3 | Complete |
| PNUI-10 | Phase 2 | Complete |
| PAST-01 | Phase 3 | Complete |
| PAST-02 | Phase 3 | Complete |
| PAST-03 | Phase 3 | Complete |
| ORGN-01 | Phase 4 | Complete |
| ORGN-02 | Phase 4 | Complete |
| ORGN-03 | Phase 4 | Complete |
| ORGN-04 | Phase 4 | Complete |
| ORGN-05 | Phase 4 | Complete |
| ORGN-06 | Phase 4 | Complete |
| INFR-01 | Phase 1 | Complete |
| INFR-02 | Phase 5 | Complete |
| INFR-03 | Phase 5 | Complete |
| INFR-04 | Phase 1 | Complete |
| LABL-01 | Phase 6 | Complete |
| LABL-02 | Phase 6 | Complete |
| LABL-03 | Phase 6 | Complete |
| RICH-01 | Phase 7 | Complete |
| RICH-02 | Phase 7 | Complete |
| RICH-03 | Phase 7 | Complete |
| RICH-04 | Phase 7 | Complete |
| RICH-05 | Phase 7 | Complete |
| RICH-06 | Phase 8 | Complete |
| RICH-07 | Phase 8 | Complete |
| RICH-08 | Phase 8 | Complete |
| RICH-09 | Phase 8 | Complete |
| PAST-10 | Phase 9 | Complete |
| PAST-10b | Phase 9 | Complete |
| PAST-11 | Phase 9 | Complete |
| PAST-12 | Phase 9 | Complete |
| ITEM-01 | Phase 11 | Complete |
| ITEM-02 | Phase 11 | Complete |
| ITEM-03 | Phase 11 | Complete |
| ITEM-04 | Phase 11 | Complete |
| ITEM-05 | Phase 11 | Complete |
| ITEM-06 | Phase 11 | Complete |
| HIST-01 | Phase 12 | Complete |
| HIST-02 | Phase 12 | Complete |
| HIST-03 | Phase 12 | Complete |
| HIST-04 | Phase 12 | Complete |
| HIST-05 | Phase 12 | Complete |
| HIST-06 | Phase 12 | Complete |
| PAST-20 | Phase 13 | Complete |
| PAST-21 | Phase 13 | Complete |
| PAST-22 | Phase 13 | Complete |
| PAST-23 | Phase 13 | Complete |
| PRIV-01 | Phase 14 | Complete |
| PRIV-02 | Phase 14 | Complete |
| PRIV-03 | Phase 14 | Complete |
| PRIV-04 | Phase 14 | Complete |
| PRIV-05 | Phase 14 | Complete |
| DATA-01 | Phase 15 | Complete |
| DATA-02 | Phase 15 | Complete |
| DATA-03 | Phase 15 | Complete |
| DATA-04 | Phase 15 | Complete |
| DATA-05 | Phase 15 | Complete |
| DATA-06 | Phase 15 | Complete |
| DATA-07 | Phase 15 | Complete |
| DATA-08 | Phase 15 | Complete |
| DRAG-01 | Phase 16 | Complete |
| DRAG-02 | Phase 16 | Complete |
| DRAG-03 | Phase 16 | Complete |
| DRAG-04 | Phase 16 | Complete |
| DRAG-05 | Phase 16 | Complete |
| SYNC-01 | Phase 19 | Pending |
| SYNC-02 | Phase 19 | Pending |
| SYNC-03 | Phase 19 | Pending |
| SYNC-04 | Phase 19 | Pending |
| SYNC-05 | Phase 20 | Pending |
| SYNC-06 | Phase 20 | Pending |
| SYNC-07 | Phase 20 | Pending |
| SYNC-08 | Phase 20 | Pending |
| SYNC-09 | Phase 21 | Pending |
| SYNC-10 | Phase 20 | Pending |
| SYNC-11 | Phase 20 | Pending |
| SYNC-12 | Phase 21 | Pending |
| SYNC-13 | Phase 21 | Pending |
| SYNC-14 | Phase 21 | Pending |

**v1.0 Coverage:**
- v1 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0

**v1.1 Coverage:**
- v1.1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

**v1.2 Coverage:**
- v1.2 requirements: 12 total
- Mapped to phases: 12
- Unmapped: 0

**v1.3 Coverage:**
- v1.3 requirements: 22 total
- Mapped to phases: 22
- Unmapped: 0

**v1.5 Coverage:**
- v1.5 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-02-05*
*Last updated: 2026-02-14 after v1.5 roadmap creation*
