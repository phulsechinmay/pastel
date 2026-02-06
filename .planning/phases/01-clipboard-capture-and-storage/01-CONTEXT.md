# Phase 1: Clipboard Capture and Storage - Context

**Gathered:** 2026-02-05
**Status:** Ready for planning

<domain>
## Phase Boundary

App runs invisibly in the menu bar, captures everything the user copies (text, images, URLs, files), deduplicates, and persists history to disk across app and system restarts. No panel, no paste-back, no organization — just reliable silent capture with a status popover in the menu bar.

</domain>

<decisions>
## Implementation Decisions

### Menu Bar Presence
- Use an SF Symbol clipboard icon (e.g., `doc.on.clipboard` or similar)
- Brief flash/bounce animation on the icon when a copy is captured
- Click opens a status popover showing:
  - Item count ("142 items captured")
  - Monitoring toggle (pause/resume)
  - Quit button
- No recent items list in popover — that's the panel's job (Phase 2)

### Content Capture Scope
- Capture text, images, URLs, and file references
- Smart classification: one item per copy event, classified by best type (URL wins over text, image wins over all)
- Store all metadata per item: timestamp, source app name + icon, content type tag, character/byte count
- Concealed clipboard types (passwords from 1Password etc): capture but auto-expire after 60 seconds
- Consecutive duplicate detection: skip if identical to most recent item

### Rich Text Handling
- Claude's Discretion: decide whether to store both rich (RTF/HTML) and plain text, or plain text only. Pick the standard approach that balances flexibility with storage.

### Image Storage
- Images stored as PNG files on disk (no JPEG — lossless for all)
- Thumbnails: 200px wide, generated on capture
- Full images: cap at 4K resolution, downscale anything larger
- Storage location: `~/Library/Application Support/Pastel/images/` with UUID filenames
- Cleanup on item deletion: lazy — mark for deletion, clean up periodically in background
- Database stores only file path references, never image data

### Xcode Project Bootstrap
- App name: Pastel
- Bundle ID: `app.pastel.Pastel`
- Deployment target: macOS 14.0 (Sonoma)
- Start with App Sandbox enabled — test CGEvent limitation ourselves before removing
- Swift Package dependencies from day one:
  - KeyboardShortcuts (sindresorhus) — for global hotkey support (Phase 3 but add early)
  - LaunchAtLogin (sindresorhus) — for login item support (Phase 5 but add early)
- LSUIElement = true in Info.plist (no dock icon)
- SwiftData for persistence
- @Observable macro for state management

### Claude's Discretion
- Exact SF Symbol choice for menu bar icon
- Rich text storage strategy (RTF+plain vs plain only)
- SwiftData model schema details
- Polling timer implementation (Timer vs DispatchSourceTimer)
- Background queue strategy for image processing
- Exact popover layout and styling

</decisions>

<specifics>
## Specific Ideas

- PastePal-style icon animation: subtle bounce when copy is detected — gives confidence the app is working
- Source app tracking from day one — even though it's metadata, it helps identify items later when panel exists
- Auto-expiring passwords after 60 seconds — respect password manager users while still capturing for brief use

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-clipboard-capture-and-storage*
*Context gathered: 2026-02-05*
