# Roadmap: Pastel

## Milestones

- v1.0 MVP - Phases 1-5 (shipped 2026-02-06)
- v1.1 Rich Content & Enhanced Paste - Phases 6-10 (in progress)
- v1.2 Storage & Security - Phases 11+ (planned)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-5) - SHIPPED 2026-02-06</summary>

### Phase 1: Clipboard Capture and Storage
**Goal**: App runs invisibly in the menu bar, captures everything the user copies (text, images, URLs, files), deduplicates, and persists history to disk across app and system restarts
**Depends on**: Nothing (first phase)
**Requirements**: CLIP-01, CLIP-02, CLIP-03, CLIP-04, CLIP-05, CLIP-06, INFR-01, INFR-04
**Plans**: 3 plans

Plans:
- [x] 01-01-PLAN.md -- Xcode project bootstrap, SwiftData model, menu bar app shell
- [x] 01-02-PLAN.md -- Clipboard monitoring, content classification, deduplication
- [x] 01-03-PLAN.md -- Image storage, concealed item handling, end-to-end verification

### Phase 2: Sliding Panel
**Goal**: Users can visually browse their clipboard history in a screen-edge sliding panel with rich card previews for each content type, using an always-dark theme
**Depends on**: Phase 1
**Requirements**: PNUI-01, PNUI-02, PNUI-05, PNUI-06, PNUI-07, PNUI-08, PNUI-10
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md -- NSPanel infrastructure, PanelController, dark vibrancy, menu bar toggle, Cmd+Shift+V shortcut
- [x] 02-02-PLAN.md -- Card views for all content types (text, image, URL, file), async thumbnails, source app icons

### Phase 3: Paste-Back and Hotkeys
**Goal**: Users can summon the panel with a global hotkey and paste any clipboard item into the currently active app without the panel stealing focus
**Depends on**: Phase 2
**Requirements**: PAST-01, PAST-02, PAST-03, PNUI-04, PNUI-09
**Plans**: 2 plans

Plans:
- [x] 03-01-PLAN.md -- PasteService (CGEvent paste simulation), AccessibilityService, sandbox removal, AppState/PanelController wiring
- [x] 03-02-PLAN.md -- Keyboard navigation (arrow keys + Enter), double-click paste, selection highlight, Accessibility onboarding prompt

### Phase 4: Organization
**Goal**: Users can search, label, filter, and manage their clipboard history so it remains useful as it grows
**Depends on**: Phase 3
**Requirements**: ORGN-01, ORGN-02, ORGN-03, ORGN-04, ORGN-05, ORGN-06
**Plans**: 3 plans

Plans:
- [x] 04-01-PLAN.md -- Label model, search field, FilteredCardListView with dynamic @Query, PanelContentView restructure
- [x] 04-02-PLAN.md -- LabelColor enum, ChipBarView with label filtering, context menu with label assignment and delete
- [x] 04-03-PLAN.md -- Robust individual delete with image cleanup, clear all history with confirmation dialog

### Phase 5: Settings and Polish
**Goal**: Users can configure Pastel to fit their workflow -- panel position, launch at login, and all preferences accessible from a settings window
**Depends on**: Phase 4
**Requirements**: INFR-02, INFR-03, PNUI-03
**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md -- Settings window infrastructure, General tab (launch at login, hotkey recorder, panel position picker, retention), PanelEdge enum, PanelController 4-edge refactor, RetentionService
- [x] 05-02-PLAN.md -- Labels tab with full CRUD, horizontal panel layout adaptation for top/bottom edges, keyboard nav direction swap

</details>

### v1.1 Rich Content & Enhanced Paste (In Progress)

**Milestone Goal:** Enrich clipboard cards with syntax highlighting, color swatches, and URL previews; add Cmd+Shift+1-9 direct paste hotkeys; upgrade label system with color palette and emoji support.

**Phase Numbering:**
- Integer phases (6, 7, 8, 9): Planned milestone work
- Decimal phases (7.1, 7.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 6: Data Model and Label Enhancements** - Extend schema for rich content and ship label emoji with expanded color palette
- [x] **Phase 7: Code and Color Detection** - Detect code snippets and color values at capture time with syntax-highlighted and swatch card views
- [ ] **Phase 8: URL Preview Cards** - Auto-fetch URL metadata and render rich preview cards with title, favicon, and og:image
- [x] **Phase 9: Quick Paste Hotkeys** - Cmd+1-9 pastes the Nth item while panel is open, with position badges
- [x] **Phase 10: Drag-and-Drop Label Assignment** - Drag label chips from the chip bar onto clipboard items to assign labels

## Phase Details

### Phase 6: Data Model and Label Enhancements
**Goal**: Schema is extended for all v1.1 features and users see an upgraded label system with 12 colors and optional emoji on chips
**Depends on**: Phase 5 (v1.0 complete)
**Requirements**: LABL-01, LABL-02, LABL-03
**Success Criteria** (what must be TRUE):
  1. User opens label settings and sees 12 color options (including teal, indigo, brown, mint) instead of the original 8
  2. User assigns an emoji to a label and the emoji replaces the color dot in chip bar and card headers
  3. User opens the system emoji picker from label settings to choose an emoji
  4. Existing v1.0 clipboard history and labels load without data loss after schema migration
**Plans**: 2 plans

Plans:
- [x] 06-01-PLAN.md -- SwiftData schema migration (new optional fields on ClipboardItem, new ContentType cases, Label emoji field), LabelColor enum expansion, migration validation
- [x] 06-02-PLAN.md -- Label emoji UI (emoji input in LabelSettingsView, emoji-or-dot rendering in ChipBarView and card headers, system picker integration)

### Phase 7: Code and Color Detection
**Goal**: Copied code snippets display with syntax highlighting and language badges, and copied color values display with visual swatches
**Depends on**: Phase 6
**Requirements**: RICH-01, RICH-02, RICH-03, RICH-04, RICH-05
**Success Criteria** (what must be TRUE):
  1. User copies a code snippet (e.g., a Swift function) and the panel card shows syntax-highlighted preview with a language badge
  2. User copies a hex color value like #FF5733 and the panel card shows a colored swatch rectangle alongside the text
  3. User copies rgb(255, 87, 51) and it is detected as a color with the same swatch treatment
  4. User copies plain prose and it remains a normal text card (no false positive code or color detection)
**Plans**: 3 plans

Plans:
- [x] 07-01-PLAN.md -- ColorDetectionService (hex/rgb/hsl regex), CodeDetectionService (multi-signal heuristic), detection wired into ClipboardMonitor
- [x] 07-02-PLAN.md -- HighlightSwift SPM dependency, CodeCardView (syntax-highlighted preview, language badge, monospaced font, async caching), fire-and-forget language detection
- [x] 07-03-PLAN.md -- ColorCardView (swatch + text), updated ClipboardCardView routing for .code and .color types

### Phase 8: URL Preview Cards
**Goal**: URL clipboard items auto-fetch page metadata and display rich preview cards with title, favicon, and og:image, with graceful fallback on failure
**Depends on**: Phase 7
**Requirements**: RICH-06, RICH-07, RICH-08, RICH-09
**Success Criteria** (what must be TRUE):
  1. User copies a URL and within seconds the card updates to show the page title and favicon
  2. User copies a URL with og:image metadata and the card displays the preview image above the title
  3. User copies a URL while offline or to a non-responsive server and the card falls back to the existing plain URL display
  4. User disables URL metadata fetching in Settings and newly copied URLs remain plain URL cards
**Plans**: 2 plans

Plans:
- [x] 08-01-PLAN.md -- URLMetadataService (LPMetadataProvider, 5s timeout, async fire-and-forget), favicon/og:image disk caching via ImageStorageService, skip logic for private/local URLs
- [ ] 08-02-PLAN.md -- Enhanced URLCardView (source app + timestamp header, og:image preview, favicon + title footer), Settings toggle to disable fetching, image cleanup in RetentionService

### Phase 9: Quick Paste Hotkeys
**Goal**: Users can paste recent clipboard items instantly via Cmd+1-9 while the panel is open, with visual position badges on cards
**Depends on**: Phase 6 (model), Phase 8 (all card types complete for badge layout)
**Requirements**: PAST-10, PAST-10b, PAST-11, PAST-12
**Success Criteria** (what must be TRUE):
  1. User opens panel and presses Cmd+1, the most recent clipboard item is pasted into the active app
  2. User opens panel and presses Cmd+5, the 5th most recent item is pasted correctly
  3. User opens the panel and the first 9 cards show position number badges (⌘ 1-9) in their bottom-right corners
  4. User disables quick paste hotkeys in Settings and Cmd+1-9 no longer triggers paste and badges disappear
  5. User presses Cmd+Shift+3 and the 3rd item is pasted as plain text (RTF stripped)
**Plans**: 2 plans

Plans:
- [x] 09-01-PLAN.md -- Quick paste .onKeyPress handlers (Cmd+1-9 normal, Cmd+Shift+1-9 plain text), pastePlainText on PasteService, Settings toggle under Hotkey section
- [x] 09-02-PLAN.md -- Keycap-style position badges (⌘ 1-9) on first 9 panel cards, badge visibility tied to quickPasteEnabled setting

### Phase 10: Drag-and-Drop Label Assignment
**Goal**: Users can drag a label chip from the chip bar and drop it onto a clipboard card to assign that label, providing a faster alternative to the context menu
**Depends on**: Phase 9
**Plans**: 1 plan

Plans:
- [ ] 10-01-PLAN.md -- PersistentIdentifier transfer helpers, draggable chip bar (Button to onTapGesture refactor), per-card drop targets with visual feedback

### v1.2 Storage & Security

**Milestone Goal:** Item titles for easier discovery, multi-label support, edit modal for item management, plus storage optimization and sensitive data protection.

- [x] **Phase 11: Item Titles, Multi-Label Support, and Edit Modal** - User-assigned titles on clipboard items, multi-label relationships, and a right-click edit modal for title and label management
- [x] **Phase 12: History Browser and Bulk Actions** - Full-window history browser in Settings with responsive grid layout, search/label filtering, multi-select, and bulk copy/paste/delete

## Phase Details (v1.2)

### Phase 11: Item Titles, Multi-Label Support, and Edit Modal
**Goal**: Users can assign titles to clipboard items for easier discovery via search, items support multiple labels, and a right-click "Edit" modal provides title and label management
**Depends on**: Phase 10 (v1.1 complete)
**Success Criteria** (what must be TRUE):
  1. User right-clicks a clipboard card and selects "Edit" to open a modal where they can add/update a title
  2. The title appears on the card instead of the character count / image size footer, in a visually distinct style
  3. Search matches against item titles in addition to content text
  4. User can assign multiple labels to a single clipboard item (via the edit modal and existing context menu)
  5. Chip bar filtering shows items that have ANY of the selected label(s)
  6. Items with multiple labels display all assigned label chips/emojis on the card
**Plans**: 3 plans

Plans:
- [x] 11-01-PLAN.md -- Data model updates (title, labels array), Label inverse relationship, MigrationService, EditItemView modal
- [x] 11-02-PLAN.md -- ClipboardCardView restructure (title in header, labels in footer, multi-label context menu, edit sheet, abbreviated time)
- [x] 11-03-PLAN.md -- Multi-select chip bar, hybrid label filtering (predicate + in-memory), title search, drag-drop label append

### Phase 12: History Browser and Bulk Actions
**Goal**: Users can browse and manage their full clipboard history in a resizable Settings tab with responsive grid layout, multi-select, and bulk operations (copy, paste, delete)
**Depends on**: Phase 11
**Success Criteria** (what must be TRUE):
  1. User opens Settings and sees a "History" tab with the same clipboard cards displayed in a responsive grid that reflows on window resize
  2. User can search and filter by labels using the same search bar and chip bar as the panel
  3. User can select multiple cards (click + Shift-click or Cmd-click) with visual selection indicators
  4. User selects multiple items and uses "Copy" to concatenate their text content with newlines and copy to clipboard
  5. User selects multiple items and uses "Paste" to paste concatenated content into the active app
  6. User selects multiple items and uses "Delete" which shows a confirmation dialog stating the number of items to be deleted
**Plans**: 3 plans

Plans:
- [x] 12-01-PLAN.md -- Resizable settings window, History tab in SettingsView, HistoryBrowserView shell with search and chip bar
- [x] 12-02-PLAN.md -- HistoryGridView with adaptive LazyVGrid, @Query with in-memory label filtering, Cmd-click/Shift-click multi-selection
- [x] 12-03-PLAN.md -- Bulk action toolbar (Copy, Paste, Delete) with confirmation dialog, image cleanup, and paste-back from settings

## Progress

**Execution Order:**
Phases execute in numeric order: 6 -> 7 -> 8 -> 9 -> 10

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Clipboard Capture and Storage | v1.0 | 3/3 | Complete | 2026-02-06 |
| 2. Sliding Panel | v1.0 | 2/2 | Complete | 2026-02-06 |
| 3. Paste-Back and Hotkeys | v1.0 | 2/2 | Complete | 2026-02-06 |
| 4. Organization | v1.0 | 3/3 | Complete | 2026-02-06 |
| 5. Settings and Polish | v1.0 | 2/2 | Complete | 2026-02-06 |
| 6. Data Model and Label Enhancements | v1.1 | 2/2 | Complete | 2026-02-07 |
| 7. Code and Color Detection | v1.1 | 3/3 | Complete | 2026-02-07 |
| 8. URL Preview Cards | v1.1 | 1/2 | In progress | - |
| 9. Quick Paste Hotkeys | v1.1 | 2/2 | Complete | 2026-02-07 |
| 10. Drag-and-Drop Label Assignment | v1.1 | 1/1 | Complete | 2026-02-07 |
| 11. Item Titles, Multi-Label Support, and Edit Modal | v1.2 | 3/3 | Complete | 2026-02-09 |
| 12. History Browser and Bulk Actions | v1.2 | 3/3 | Complete | 2026-02-08 |
