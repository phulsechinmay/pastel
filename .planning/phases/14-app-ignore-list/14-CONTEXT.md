# Phase 14: App Ignore List - Context

**Gathered:** 2026-02-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Privacy-focused application filtering for clipboard monitoring. Users can exclude specific applications (password managers, banking apps, etc.) so copies from those apps are never captured in Pastel's history. Settings UI for managing the ignore list + ClipboardMonitor filtering logic.

</domain>

<decisions>
## Implementation Decisions

### App Selection Method
- User can browse ALL installed applications (not just running apps)
- App picker shows searchable alphabetical list of installed apps
- Each app row displays: app name + icon (clean and simple)
- Additional "+" button allows file picker to manually select .app files outside the installed app list (for helper apps, non-standard locations, etc.)

### List Management UI
- Ignore list presented as table with sortable columns (like Finder list view)
- Columns: Name + Date Added
- Remove apps via standard macOS pattern: Select row + Delete key
- Search field above table to filter ignore list by app name (helpful when list gets long)

### Default Ignores
- First time user opens Privacy section, show one-time prompt: "Add installed password managers to ignore list?" (Yes/No)
- If Yes: scan system and add only password managers that are actually installed (not a hardcoded list of all possible ones)
- Stay focused on password managers only (don't expand to banking apps, messaging apps, etc. for v1.3)

### Claude's Discretion
- Exact app discovery mechanism (LSApplicationWorkspace, file system scan, etc.)
- Table sorting behavior (which column is default sort, sort direction indicators)
- Empty state messaging when ignore list is empty
- Password manager bundle ID detection logic (which apps qualify as "password managers")

</decisions>

<specifics>
## Specific Ideas

- Simple one-liner for default prompt — don't over-explain, just "Add installed password managers to ignore list?"
- Table should feel consistent with other macOS list-based settings (System Settings style)
- File picker for .app selection allows advanced users to add any app not in the installed list

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 14-app-ignore-list*
*Context gathered: 2026-02-09*
