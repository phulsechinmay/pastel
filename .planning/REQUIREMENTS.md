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
- [ ] **PNUI-03**: Panel position configurable to top, left, right, or bottom edge
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

- [ ] **ORGN-01**: User can search clipboard history by text content
- [ ] **ORGN-02**: User can create labels
- [ ] **ORGN-03**: User can assign labels to clipboard items
- [ ] **ORGN-04**: Chip bar in panel allows filtering by label
- [ ] **ORGN-05**: User can delete individual clipboard items
- [ ] **ORGN-06**: User can clear all clipboard history

### App Infrastructure

- [x] **INFR-01**: App lives in menu bar with no dock icon
- [ ] **INFR-02**: App can be set to launch at login
- [ ] **INFR-03**: Settings window accessible from menu bar
- [x] **INFR-04**: Images stored on disk with thumbnails, not in database

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Enhanced Paste

- **PAST-10**: User can paste via Cmd+1-9 hotkeys for the latest 9 items without opening panel
- **PAST-11**: Configurable paste behavior (paste directly vs copy-then-paste) in settings
- **PAST-12**: User can paste as plain text (strip formatting)

### Rich Content

- **RICH-01**: App detects code snippets and shows syntax-highlighted previews
- **RICH-02**: App detects color values (hex, rgb, hsl) and shows color swatches
- **RICH-03**: URL cards show page title and favicon from metadata
- **RICH-04**: Cards show source app icon/name for each clipboard item

### History Management

- **HIST-01**: User can configure history retention (1 day, 1 week, 1 month, 1 year, all time)
- **HIST-02**: User can pin/favorite items that persist beyond retention limits
- **HIST-03**: User can drag-and-drop items from panel into other apps

### Privacy

- **PRIV-01**: User can configure allow/ignore app lists for clipboard monitoring
- **PRIV-02**: App detects concealed clipboard types (passwords) and auto-expires them

### Data

- **DATA-01**: User can import/export clipboard history

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| iCloud sync | Massive complexity, server costs, privacy concerns. Universal Clipboard covers basic cross-device needs |
| iOS companion app | macOS only for v1. Entirely different platform |
| Snippet templates / text expansion | Different product category (TextExpander, Typinator). Dilutes focus |
| Browser extension integration | NSPasteboard already captures browser copies. No extension needed |
| AI-powered features | Adds latency, cost, complexity. Tangential to core clipboard value |
| Real-time collaboration / shared clipboard | Networking, auth, conflict resolution. Different product category |
| Plugin/extension system | Massive API surface. Premature for v1 |
| Clipboard rules / automation | Rules engines are complex. Users who want this use Keyboard Maestro |
| Multi-window / detachable panels | Window management complexity multiplies. Single configurable panel |
| Encrypted clipboard history | Degrades search performance, false sense of security. Offer clear history instead |
| Custom theming / light mode | Always-dark is a feature. Ship one polished theme |

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
| PNUI-03 | Phase 5 | Pending |
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
| ORGN-01 | Phase 4 | Pending |
| ORGN-02 | Phase 4 | Pending |
| ORGN-03 | Phase 4 | Pending |
| ORGN-04 | Phase 4 | Pending |
| ORGN-05 | Phase 4 | Pending |
| ORGN-06 | Phase 4 | Pending |
| INFR-01 | Phase 1 | Complete |
| INFR-02 | Phase 5 | Pending |
| INFR-03 | Phase 5 | Pending |
| INFR-04 | Phase 1 | Complete |

**Coverage:**
- v1 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0

---
*Requirements defined: 2026-02-05*
*Last updated: 2026-02-06 after roadmap creation*
