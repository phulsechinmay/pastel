# Pastel

## What This Is

Pastel is a native macOS clipboard manager that saves everything you copy and makes it instantly accessible through a screen-edge sliding panel. It supports text, images, URLs, files, code snippets, and colors — with label organization, search, and hotkey-driven pasting. Think PastePal or Paste 2, built with Swift and SwiftUI.

## Core Value

Clipboard history is always one hotkey away, with instant paste-back into any app.

## Current Milestone: v1.5 iCloud Sync

**Goal:** Sync clipboard history across multiple Macs via iCloud so users logged into the same Apple ID see the same history on all devices.

**Target features:**
- iCloud sync of clipboard history (text, URLs, code, colors, file references — images deferred)
- Opt-in sync toggle in Settings (off by default)
- Conflict resolution for concurrent edits across devices
- Sync-aware retention limits to manage iCloud storage
- Sync status indicator so users know when data is up to date
- Uses user's own iCloud storage (no server infrastructure needed)

## Requirements

### Validated

- [x] Clipboard monitoring — capture text, images, URLs, files
- [x] Clipboard history sidebar — screen-edge sliding panel triggered by hotkey
- [x] Label system — create labels, assign to items, filter by label chips, drag-and-drop assignment
- [x] Search — full-text search across clipboard history, combinable with label filters
- [x] Paste-back — double-click or Enter to paste items into active app
- [x] Configurable paste behavior — paste directly, copy to clipboard, or copy+paste
- [x] Sidebar positioning — configurable to top, left, right, or bottom screen edge
- [x] History retention settings — 1 week, 1 month, 3 months, 1 year, or forever
- [x] Image storage on disk — store images as files with thumbnails
- [x] Menu bar app — lives in macOS menu bar, no dock icon
- [x] Settings window — configure retention, paste behavior, panel position, hotkeys
- [x] Always-dark theme
- [x] Keyboard navigation — arrow keys + Enter to select and paste
- [x] Accessibility onboarding — guided permission request on first launch
- [x] Code snippet detection — syntax-highlighted previews with language badges
- [x] Color value detection — hex/rgb/hsl with visual swatches
- [x] URL metadata fetching — auto-fetch title, favicon, og:image
- [x] Quick paste hotkeys — Cmd+1-9 and Cmd+Shift+1-9 with position badges
- [x] Label enhancements — 12 colors, optional emoji, emoji picker
- [x] Edit clip content — fix a clip's text in place (Cmd+E), retention-safe
- [x] Pin to top — per-item pinning, sorts above history, exempt from retention
- [x] Manual snippets — author a clip without copying (Cmd+N), born pinned

### Active

See REQUIREMENTS.md for v1.5 milestone requirements.

- [ ] iCloud sync — clipboard history synced across Macs via CloudKit
- [ ] Sync settings — opt-in toggle, retention limits for synced data
- [ ] Conflict resolution — handle concurrent copies across devices
- [ ] Sync status — visual indicator of sync state

### Out of Scope

- iOS companion app — macOS only
- Text expansion (trigger-string substitution while typing) — separate tool category.
  Narrowed 2026-07-27: manual snippet *authoring* (creating a clip without copying)
  is in scope and planned; only TextExpander-style triggers are excluded.
- Light mode / system-adaptive theme — always dark
- Image sync — text-only for v1.5, architecture supports future image sync
- Real-time collaboration / shared clipboard between different Apple IDs

## Context

- Native macOS app using Swift + SwiftUI + AppKit hybrid
- Inspiration: PastePal (screen-edge panel, hotkey paste, label organization) and Paste 2
- Images stored as files on disk with generated thumbnails for sidebar display
- Needs Accessibility permissions for paste simulation into other apps
- Clipboard monitoring via NSPasteboard polling at 0.5s intervals
- Screen-edge panel uses NSPanel with .nonactivatingPanel style mask
- SwiftData for persistence (macOS 14+ target)
- v1.0 complete with 29 requirements delivered across 5 phases
- v1.1 complete with 15 requirements delivered across 5 phases (6-10)
- v1.2 complete with item management features across 2 phases (11-12)
- v1.3 complete with power user features across 4 phases (13-16)
- v1.4 complete with codebase audit (Phase 18; Phase 17 deferred)

## Constraints

- **Platform**: macOS only — no cross-platform considerations
- **Tech Stack**: Swift + SwiftUI — native APIs, no Electron or web views
- **Theme**: Always dark — no light mode variant needed
- **Storage**: Images on disk as files, metadata in SwiftData
- **Distribution**: App Store (App Sandbox enabled, PostEvent TCC for paste-back)
- **Network**: URL metadata fetching must be non-blocking with graceful fallback

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift + SwiftUI | Modern macOS framework, good for sidebar UI and settings | ✓ Good |
| Menu bar only (no dock) | Clipboard managers should be lightweight and unobtrusive | ✓ Good |
| Images on disk | Avoids bloated database, thumbnails keep sidebar fast | ✓ Good |
| Always dark theme | Simpler to build, matches the tool's aesthetic | ✓ Good |
| Configurable paste behavior | Some users prefer clipboard copy, others want direct paste | ✓ Good |
| Screen-edge sliding panel | Matches PastePal UX, globally accessible from any app | ✓ Good |
| NSPanel activate-on-show | Panel activates app for full Liquid Glass, re-activates previous app on dismiss | ✓ Good |
| SwiftData persistence | Modern API with @Query integration, macOS 14+ target | ✓ Good |
| CGEvent Cmd+V paste-back | Reliable paste simulation, requires Accessibility permission | ✓ Good |
| XcodeGen project management | project.yml is source of truth, reproducible builds | ✓ Good |
| Automatic code signing | Stable TCC identity across Xcode rebuilds | ✓ Good |
| Preset label color palette | Simple, clean UX — 12 named colors | ✓ Good |
| Emoji replaces color dot | Either emoji OR color, not both — keeps chips clean | ✓ Good |
| Auto-fetch URL metadata | Fetch on copy with fallback to plain card on failure | ✓ Good |
| Manual sensitive marking | User decides what's sensitive, not heuristics | — Pending |
| Image compression for storage | Reduce disk footprint without losing paste quality | — Pending |

---
*Last updated: 2026-02-14 after milestone v1.5 start*
