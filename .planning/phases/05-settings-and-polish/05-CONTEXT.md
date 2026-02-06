# Phase 5: Settings and Polish — Context & Decisions

**Created:** 2026-02-06
**Requirements:** INFR-02, INFR-03, PNUI-03

## Goal

Users can configure Pastel to fit their workflow -- panel position, launch at login, hotkey customization, history retention, and label management -- all from a settings window accessible via the panel and menu bar.

## Decisions

### 1. Settings Window Structure

| Decision | Choice |
|----------|--------|
| Window structure | Tabbed, with custom horizontal tab bar at top (keyogre-style) |
| Tabs | Two: **General** and **Labels** |
| Theme | Always dark (matches panel and app identity) |
| Access points | Both: gear icon in panel header AND right-click menu bar item |
| Tab bar style | Horizontal centered, icon + text, dark glassmorphism background (`.ultraThinMaterial`), accent color selection, from keyogre `SettingsView` pattern |

**Reference implementation:** `keyogre/KeyOgre/Views/SettingsView.swift` tab bar pattern -- 80x60pt buttons, icon + text label, accent color background on selection, frosted glass background.

### 2. General Tab Layout

| Decision | Choice |
|----------|--------|
| Launch at login | Toggle at top of General tab (most visible setting) |
| Hotkey customization | Customizable panel toggle hotkey using KeyboardShortcuts library (already a dependency) |
| History retention | Dropdown with time-based options: 1 week, 1 month, 3 months, 1 year, Forever |
| Panel position | Visual screen diagram selector (small rectangle with clickable edges) |

**General tab layout order (top to bottom):**
1. Launch at login toggle
2. Panel toggle hotkey recorder
3. Panel position selector (visual diagram)
4. History retention dropdown

### 3. Panel Position

| Decision | Choice |
|----------|--------|
| Supported edges | All four: left, right, top, bottom |
| Right/left orientation | Vertical sidebar (full height, fixed width 320pt) -- current behavior |
| Top/bottom orientation | Horizontal bar (full screen width, fixed height ~300pt) |
| Slide animation | Always from the edge (left panel slides from left, top from top, etc.) |
| Position selector UI | Visual screen diagram with clickable edges |
| Default position | Right edge (current behavior) |

**Card layout adaptation for horizontal position (top/bottom):**
- Cards should flow horizontally when panel is at top/bottom edge
- Claude's discretion on exact horizontal layout

### 4. Label Management (Labels Tab)

| Decision | Choice |
|----------|--------|
| Display format | Vertical list with inline editing |
| Actions available | Create, rename, recolor, delete |
| Create label | "+" button at bottom of list, inline creation |
| Rename | Click label name to edit inline |
| Recolor | Click color dot to show color picker (preset palette from LabelColor enum) |
| Delete | Delete button per row, no confirmation dialog |
| Deletion behavior | Items with deleted label become unlabeled (relationship nullified) |

### 5. Claude's Discretion

- Exact spacing and typography in settings window
- Visual screen diagram design details (how the clickable edges look)
- How cards adapt to horizontal panel orientation (top/bottom)
- Settings persistence mechanism (@AppStorage vs UserDefaults)
- History retention auto-purge timing (on app launch, periodic, etc.)

## Specific Ideas

- Tab bar should match keyogre's `SettingsView` pattern: horizontal, centered, icon + text labels, glassmorphism background, accent color selection state
- Settings window reference images provided by user (pasteboard.co screenshots)
- "Forever" option for history retention means no auto-purging

## Deferred Ideas

None -- discussion stayed within phase scope.

---

*Phase: 05-settings-and-polish*
*Context gathered: 2026-02-06*
