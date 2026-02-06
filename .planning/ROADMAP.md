# Roadmap: Pastel

## Overview

Pastel is a native macOS clipboard manager built with Swift and SwiftUI. The roadmap delivers the core value -- clipboard history one hotkey away with instant paste-back -- through five phases. Each phase delivers a coherent, verifiable capability: silent clipboard capture, visual browsing, paste-back into active apps, organization at scale, and user configuration. The ordering is strictly dependency-driven: you cannot browse what has not been captured, cannot paste what has not been displayed, and cannot configure what has not been built.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Clipboard Capture and Storage** - Silently capture all clipboard content and persist across restarts
- [x] **Phase 2: Sliding Panel** - Browse clipboard history in a visually rich screen-edge panel
- [x] **Phase 3: Paste-Back and Hotkeys** - Instantly paste any item into the active app via hotkey and keyboard
- [x] **Phase 4: Organization** - Search, label, filter, and manage clipboard history
- [x] **Phase 5: Settings and Polish** - Configure panel position, launch behavior, and preferences

## Phase Details

### Phase 1: Clipboard Capture and Storage
**Goal**: App runs invisibly in the menu bar, captures everything the user copies (text, images, URLs, files), deduplicates, and persists history to disk across app and system restarts
**Depends on**: Nothing (first phase)
**Requirements**: CLIP-01, CLIP-02, CLIP-03, CLIP-04, CLIP-05, CLIP-06, INFR-01, INFR-04
**Success Criteria** (what must be TRUE):
  1. User copies text in any app and it appears in stored clipboard history
  2. User copies an image and a thumbnail is saved to disk (not in the database)
  3. User copies a URL or file reference and it is captured as the correct content type
  4. User quits and relaunches the app and all previous clipboard history is still present
  5. User copies the same text twice consecutively and only one entry appears in history
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md -- Xcode project bootstrap, SwiftData model, menu bar app shell
- [x] 01-02-PLAN.md -- Clipboard monitoring, content classification, deduplication
- [x] 01-03-PLAN.md -- Image storage, concealed item handling, end-to-end verification

### Phase 2: Sliding Panel
**Goal**: Users can visually browse their clipboard history in a screen-edge sliding panel with rich card previews for each content type, using an always-dark theme
**Depends on**: Phase 1
**Requirements**: PNUI-01, PNUI-02, PNUI-05, PNUI-06, PNUI-07, PNUI-08, PNUI-10
**Success Criteria** (what must be TRUE):
  1. Panel slides in from the screen edge with smooth animation and slides out when dismissed
  2. Text items show a readable text preview in their card
  3. Image items show a thumbnail preview in their card
  4. URL items are visually distinct from plain text items
  5. File items show the file name or path in their card
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md -- NSPanel infrastructure, PanelController, dark vibrancy, menu bar toggle, Cmd+Shift+V shortcut
- [x] 02-02-PLAN.md -- Card views for all content types (text, image, URL, file), async thumbnails, source app icons

### Phase 3: Paste-Back and Hotkeys
**Goal**: Users can summon the panel with a global hotkey and paste any clipboard item into the currently active app without the panel stealing focus
**Depends on**: Phase 2
**Requirements**: PAST-01, PAST-02, PAST-03, PNUI-04, PNUI-09
**Success Criteria** (what must be TRUE):
  1. User presses a global hotkey and the panel appears over the active app
  2. User double-clicks a card and its content is pasted into the app that was active before the panel appeared
  3. User navigates cards with arrow keys and presses Enter to paste the selected item
  4. Panel does not steal focus from the active app (non-activating window)
  5. On first launch, user is guided through Accessibility permission with a clear explanation of why it is needed
**Plans**: 2 plans

Plans:
- [x] 03-01-PLAN.md -- PasteService (CGEvent paste simulation), AccessibilityService, sandbox removal, AppState/PanelController wiring
- [x] 03-02-PLAN.md -- Keyboard navigation (arrow keys + Enter), double-click paste, selection highlight, Accessibility onboarding prompt

### Phase 4: Organization
**Goal**: Users can search, label, filter, and manage their clipboard history so it remains useful as it grows
**Depends on**: Phase 3
**Requirements**: ORGN-01, ORGN-02, ORGN-03, ORGN-04, ORGN-05, ORGN-06
**Success Criteria** (what must be TRUE):
  1. User types in a search field and results filter to matching clipboard items in real time
  2. User creates a label, assigns it to items, and can filter the panel view by that label using a chip bar
  3. User can delete an individual clipboard item and it disappears from history
  4. User can clear all clipboard history at once
**Plans**: 3 plans

Plans:
- [x] 04-01-PLAN.md -- Label model, search field, FilteredCardListView with dynamic @Query, PanelContentView restructure
- [x] 04-02-PLAN.md -- LabelColor enum, ChipBarView with label filtering, context menu with label assignment and delete
- [x] 04-03-PLAN.md -- Robust individual delete with image cleanup, clear all history with confirmation dialog

### Phase 5: Settings and Polish
**Goal**: Users can configure Pastel to fit their workflow -- panel position, launch at login, and all preferences accessible from a settings window
**Depends on**: Phase 4
**Requirements**: INFR-02, INFR-03, PNUI-03
**Success Criteria** (what must be TRUE):
  1. User opens a Settings window from the menu bar icon and can view/change all preferences
  2. User can change the panel position to any screen edge (top, left, right, bottom) and the panel appears at the new position
  3. User can enable launch at login and the app starts automatically after system restart
**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md -- Settings window infrastructure, General tab (launch at login, hotkey recorder, panel position picker, retention), PanelEdge enum, PanelController 4-edge refactor, RetentionService
- [x] 05-02-PLAN.md -- Labels tab with full CRUD, horizontal panel layout adaptation for top/bottom edges, keyboard nav direction swap

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Clipboard Capture and Storage | 3/3 | Complete | 2026-02-06 |
| 2. Sliding Panel | 2/2 | Complete | 2026-02-06 |
| 3. Paste-Back and Hotkeys | 2/2 | Complete | 2026-02-06 |
| 4. Organization | 3/3 | Complete | 2026-02-06 |
| 5. Settings and Polish | 2/2 | Complete | 2026-02-06 |
