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

### Rich Content — Code Detection

- [x] **RICH-01**: App detects code snippets via multi-signal heuristic and classifies them as `.code` ContentType
- [x] **RICH-02**: Code cards show syntax-highlighted previews with auto-detected language (via HighlightSwift)
- [x] **RICH-03**: Code cards display a language badge (e.g., "Swift", "Python")

### Rich Content — Color Detection

- [x] **RICH-04**: App detects standalone color values (hex, rgb, hsl) and classifies them as `.color` ContentType
- [x] **RICH-05**: Color cards show a visual swatch alongside the original color text

### Rich Content — URL Previews

- [ ] **RICH-06**: App auto-fetches URL metadata (title, favicon, og:image) after URL item is captured
- [ ] **RICH-07**: URL cards show source app icon + timestamp header, og:image preview, and favicon + title footer
- [ ] **RICH-08**: URL metadata fetch is non-blocking with graceful fallback to plain URL card on failure
- [ ] **RICH-09**: Settings toggle to disable URL metadata fetching

### Enhanced Paste — Quick Paste Hotkeys

- [x] **PAST-10**: Cmd+1-9 pastes the Nth visible item while the panel is open
- [x] **PAST-10b**: Cmd+Shift+1-9 pastes the Nth visible item as plain text (RTF stripped)
- [x] **PAST-11**: Settings toggle to enable/disable quick paste hotkeys (enabled by default)
- [x] **PAST-12**: First 9 panel cards show keycap-style position badges (⌘ 1-9) when hotkeys are enabled

### Label Enhancements

- [x] **LABL-01**: Label color palette expanded from 8 to 12 colors (add teal, indigo, brown, mint)
- [x] **LABL-02**: Labels support optional emoji that replaces the color dot in chips and card headers
- [x] **LABL-03**: Label settings view provides emoji input (system emoji picker accessible via keyboard)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Enhanced Paste

- **PAST-20**: User can paste as plain text (strip formatting)

### History Management

- **HIST-01**: User can pin/favorite items that persist beyond retention limits
- **HIST-02**: User can drag-and-drop items from panel into other apps

### Privacy

- **PRIV-01**: User can configure allow/ignore app lists for clipboard monitoring

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
| RICH-06 | Phase 8 | Pending |
| RICH-07 | Phase 8 | Pending |
| RICH-08 | Phase 8 | Pending |
| RICH-09 | Phase 8 | Pending |
| PAST-10 | Phase 9 | Complete |
| PAST-10b | Phase 9 | Complete |
| PAST-11 | Phase 9 | Complete |
| PAST-12 | Phase 9 | Complete |

**v1.0 Coverage:**
- v1 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0

**v1.1 Coverage:**
- v1.1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-02-05*
*Last updated: 2026-02-07 after Phase 9 completion*
