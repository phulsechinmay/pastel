# Pastel

## What This Is

Pastel is a native macOS clipboard manager that saves everything you copy and makes it instantly accessible through a screen-edge sliding panel. It supports text, images, URLs, files, code snippets, and colors — with label organization, search, and hotkey-driven pasting. Think PastePal or Paste 2, built with Swift and SwiftUI.

## Core Value

Clipboard history is always one hotkey away, with instant paste-back into any app.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Clipboard monitoring — capture text, images, URLs, files, code snippets, and colors
- [ ] Clipboard history sidebar — screen-edge sliding panel triggered by hotkey
- [ ] Rich card previews — image thumbnails, URL page previews, syntax-highlighted code, color swatches
- [ ] Label system — create labels, assign to items, filter by label chips in sidebar
- [ ] Search — full-text search across clipboard history, combinable with label filters
- [ ] Paste-back — double-click or Cmd+1-9 hotkeys to paste items into active app
- [ ] Configurable paste behavior — user chooses "paste directly" or "copy to clipboard + paste" in settings
- [ ] Sidebar positioning — configurable to top, left, right, or bottom screen edge
- [ ] History retention settings — 1 day, 1 week, 1 month, 1 year, or all time
- [ ] Image storage on disk — store images as files with thumbnails, load full image on demand
- [ ] Menu bar app — lives in macOS menu bar, no dock icon
- [ ] Settings window — configure history retention, paste behavior, sidebar position, hotkeys
- [ ] Always-dark theme

### Out of Scope

- iCloud sync — adds complexity, not needed for v1
- iOS companion app — macOS only
- Snippet templates / text expansion — separate tool category
- Import/export — defer to v2
- Allow/ignore app lists — defer to v2
- Light mode / system-adaptive theme — always dark for v1

## Context

- Native macOS app using Swift + SwiftUI
- Inspiration: PastePal (screen-edge panel, hotkey paste, label organization) and Paste 2
- Images stored as files on disk with generated thumbnails for sidebar display
- Needs Accessibility permissions for paste simulation into other apps
- Clipboard monitoring via NSPasteboard polling or event-based approach
- Screen-edge panel requires careful window management (NSPanel or similar)

## Constraints

- **Platform**: macOS only — no cross-platform considerations
- **Tech Stack**: Swift + SwiftUI — native APIs, no Electron or web views
- **Theme**: Always dark — no light mode variant needed
- **Storage**: Images on disk as files, metadata in local database (SQLite/SwiftData)
- **Distribution**: Needs Accessibility entitlement for paste-back functionality

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift + SwiftUI | Modern macOS framework, good for sidebar UI and settings | — Pending |
| Menu bar only (no dock) | Clipboard managers should be lightweight and unobtrusive | — Pending |
| Images on disk | Avoids bloated database, thumbnails keep sidebar fast | — Pending |
| Always dark theme | Simpler to build, matches the tool's aesthetic | — Pending |
| Configurable paste behavior | Some users prefer clipboard copy, others want direct paste | — Pending |
| Screen-edge sliding panel | Matches PastePal UX, globally accessible from any app | — Pending |

---
*Last updated: 2026-02-05 after initialization*
