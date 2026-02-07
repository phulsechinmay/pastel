# Phase 9 Context: Quick Paste Hotkeys

Captured: 2026-02-07
Source: `/gsd:discuss-phase 9`

## Decisions

### 1. Hotkey Scope: Panel-Scoped (Not Global)

**Decision:** Quick paste hotkeys are only active when the panel is open.

**Rationale:** Avoids all global hotkey conflicts (Cmd+1-9 conflicts with browser tab switching in Safari/Chrome/Firefox). Hotkeys are handled as local key events in the panel's SwiftUI view hierarchy using `.onKeyPress`, consistent with existing arrow key + Enter navigation in FilteredCardListView.

**Workflow:** Cmd+Shift+V (open panel) → Cmd+3 (paste 3rd item) → panel closes.

**Impact on PAST-10:** Requirement wording changes from "without opening the panel" to "while the panel is open, paste the Nth item via Cmd+N without manual navigation."

### 2. Two Hotkey Sets: Normal Paste + Plain Text Paste

**Decision:**
- **Cmd+1-9**: Quick paste preserving all formatting (RTF, HTML)
- **Cmd+Shift+1-9**: Quick paste as plain text (strips RTF, keeps HTML)

**Plain text behavior:** Removes RTF data from pasteboard. Retains HTML and plain string types. Equivalent to "Paste and Match Style" for RTF content.

**Non-text items:** For images, files, URLs — both hotkey sets behave identically (no formatting to strip).

### 3. Implementation: .onKeyPress Handlers (No KeyboardShortcuts Registration)

**Decision:** Use SwiftUI `.onKeyPress` handlers in FilteredCardListView/PanelContentView instead of registering KeyboardShortcuts.Name entries.

**Rationale:** Since hotkeys are panel-scoped, they don't need global registration. The panel's SwiftUI views already handle arrow keys and Enter via `.onKeyPress`. Adding Cmd+1-9 and Cmd+Shift+1-9 follows the same pattern. No new dependencies or registration infrastructure needed.

### 4. Item Resolution: Filtered View (WYSIWYG)

**Decision:** Cmd+N pastes the Nth visible card in the current filtered view.

**Rationale:** Badges correspond to what you see. If the user filters by a label, Cmd+1 pastes the most recent item matching that filter. Intuitive, no disconnect between badge numbers and card positions.

### 5. Badge Visual Design

**Position:** Bottom-right corner of each card.
**Style:** Keyboard key (rounded rect mimicking a keycap with subtle border/shadow).
**Text:** Modifier + number (e.g., "⌘ 1", "⌘ 2").
**Color:** Muted/subtle — white text on dark semi-transparent background (white/0.15 bg, white/0.7 text). Blends with always-dark theme.
**Visibility:** Only shown on first 9 cards. Hidden when quick paste is disabled in settings.

### 6. Settings Toggle

**Location:** Under existing "Hotkey" section in GeneralSettingsView (grouped with panel toggle hotkey).
**Default:** Enabled.
**Behavior when disabled:** Cmd+1-9 and Cmd+Shift+1-9 are no longer handled. Position badges disappear from all cards.
**Key:** `@AppStorage("quickPasteEnabled")` defaulting to `true`.

## Updated Requirements

Original PAST-10 through PAST-12 are refined:

- **PAST-10** (revised): Cmd+1-9 pastes the Nth visible item while the panel is open
- **PAST-10b** (new): Cmd+Shift+1-9 pastes the Nth visible item as plain text (RTF stripped)
- **PAST-11**: Settings toggle to enable/disable quick paste hotkeys (enabled by default) — under Hotkey section
- **PAST-12**: First 9 panel cards show keyboard-key-style position badges (⌘ 1-9) in bottom-right corner when hotkeys are enabled

## Key Files to Modify

- `Pastel/Views/Panel/FilteredCardListView.swift` — add `.onKeyPress` handlers for Cmd+1-9 and Cmd+Shift+1-9
- `Pastel/Views/Panel/ClipboardCardView.swift` — add position badge overlay in bottom-right corner
- `Pastel/Services/PasteService.swift` — add `pastePlainText` method that strips RTF
- `Pastel/Views/Settings/GeneralSettingsView.swift` — add toggle under Hotkey section
- `Pastel/App/AppState.swift` — possible quick paste coordination method

## Open Questions

None — all gray areas resolved.
