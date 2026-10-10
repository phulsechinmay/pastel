# Other App Learnings

Date: 2026-10-10
Status: Items 1–3 implemented on `ux-learnings`; build and model checks pass. Live interaction and accessibility verification remain before release. Items 4–7 are later opportunities, outside this delivery. Competitor screenshots below are inspiration; Pastel keeps its own visual design and the familiar Space-to-preview interaction.

## Implementation progress (2026-10-10)

**Item 1 — retrieval:** The first loaded result is selected; refreshes reconcile the selected clip and Shift range by persistent identity; an exact-query Return waits for matching results and activates once; stale cards cannot be activated during a query replacement. Typing from results hands the full key event to the native search editor, with Tab to move focus back to results. Search commands stay with the text editor.

**Item 2 — actions:** A visible action bar names the configured primary action and, when available, its destination. Command-K opens Actions with explicit Copy, Paste, Paste as Plain Text, Preview, and item-management commands. Default activation, explicit Copy, and explicit Paste now have distinct intent; the panel captures the target app when opened and checks it again before posting a paste. A changed or absent target leaves the requested clip on the clipboard with clear feedback. The legacy `copyAndPaste` preference resolves to Paste.

**Item 3 — preview:** Space from results opens a single adjacent read-only preview; Space or Escape closes it. The panel and selected clip remain in place. The preview supports text, code, rich text, image, URL, color, and local files (using Quick Look when available), with unavailable states for missing content. It shares the primary action, supports scoped arrow navigation, and closes with the panel. Its adaptive, quiet header/content/footer uses Pastel's own styling rather than a competitor layout.

**Item 2 design follow-up (implemented in source; live QA pending):** The horizontal bottom action strip is replaced with compact `↵ Paste`/`↵ Copy` and More controls in the top row. Cards keep the Command-1–9 chip at bottom right with type-specific subtext on the same baseline at left. Full destination and action names remain in Help, accessibility, More, and Space preview; right-click and Command-K remain available. See [the implementation plan](horizontal-panel-ux-1-4.md), [card layout review](../docs/design/card-layout-review.md), and concept boards. The shorter panel, toolbar crowding, rendered card spacing, and assistive behavior still need live inspection.

**Verification:** Both App Store and Sparkle macOS schemes build without code-signing, and standalone action-policy and selection-reconciliation smoke checks pass. Source and build verification cannot establish live focus behavior, paste delivery, VoiceOver order, appearance, or multi-display placement. Live app inspection was blocked by computer-use timeouts and missing assistive access. Run the acceptance matrices below on an accessible macOS session before marking release verification complete.

## Purpose

Make Pastel's everyday retrieval loop fast, predictable, and easy to discover:

**Open → type if necessary → recognize the selected clip → activate a clearly named action → return to work.**

Pastel already has search, keyboard navigation, rich previews, context menus, and paste-back. The opportunity is to connect these capabilities into a dependable interaction contract, rather than add another set of overlapping features.

This plan follows PRODUCT.md: the panel is transit, native behavior comes first, and the outcome should be knowable before the user commits.

## Evidence and scope boundaries

- Ground truth: current working-tree source, inspected October 9, 2026. Repository screenshots and older competitive analysis documents predate recent design changes and must not be treated as the current UI.
- Competitor behavior comes from official documentation. Recommendations below are Pastel proposals, not claims that every competitor implements exactly these rules.
- Live Pastel inspection was blocked by computer-use permissions/timeouts. Runtime focus, accessibility, and target-app behavior require verification during implementation.
- Existing unrelated working-tree changes must be preserved. Re-read touched files before implementation.
- This plan does not replace `.plans/paste-reliability.md`. Preserve its established capture suppression, modifier handling, permission checks, and focus handoff mechanisms.
- No changes to capture, retention, sync, pin ordering, or ranking are required for items 1 and 2.

## Learning inventory

| Item | Inspiration | Problem solved | Status |
|---|---|---|---|
| 1. Short, reliable retrieval | Maccy | Extra navigation and unstable selection slow down routine retrieval | Implemented; live QA pending |
| 2. Explicit actions | Raycast | People cannot reliably predict whether activation copies or pastes; secondary commands are hidden | Implemented; live QA pending |
| 3. Inspect before using | Paste and PastePal | Truncated cards cannot reliably distinguish long or similar clips | Implemented; live QA pending |
| 4. Separate library window | PastePal | Content management is buried in Settings | Later |
| 5. Recent versus Saved | Paste pinboards | Pinned content competes with fresh copies; durability is implicit | Later |
| 6. Adjustable density | Paste compact mode and Maccy's compact retrieval | One card size does not serve text and visual workflows equally well | Later |
| 7. Sequential paste | Paste Stack and PastePal Queue | Reopening history for every field interrupts multi-step work | Later |

## 1. Short, reliable retrieval

### Core problem

A keyboard-first clipboard utility should not require an arrow press merely to establish a selection before Return can work. Selection should also refer to a clip, not whichever clip happens to occupy a changing array position.

Example today: open panel → type a query → press an arrow to select → Return.
Target: open panel → type a query → Return.

### What exists and why it needs an update

- `Pastel/Views/Panel/FilteredCardListView.swift` clears `selectedIndex` on appearance, panel reopening, query changes, label changes, filter changes, and pin changes.
- `moveSelection` establishes index zero only when navigation begins; Return requires an existing selection.
- Selection and range anchors are array indices. A background reload can change the item at that index.
- `PanelContentView.swift` separates raw search text from a debounced query. Visible results can therefore belong to an earlier query while a person is still typing.
- An AppKit key monitor handles commands across the panel. Its Command-C branch checks whether cards are selected, rather than first checking whether a text editor owns the command. Automatic selection would make this existing weakness much more common.
- The existing code provides the pieces, but lacks a unified selection/focus/search-generation contract. This is a structural observation, not an inference about why past authors made those choices.

### Proposed behavior contract

| Event | Required result |
|---|---|
| Open panel; first page finishes loading | Select the first displayed result and make its selection ring visible |
| New query or deliberate filter change resolves | Select the first result in the new result set |
| No results, load failure, or initial load pending | No actionable selection; disable primary action |
| New capture, sync update, or metadata refresh | Preserve selected clip by persistent identity if it remains in the result set |
| Selected clip disappears | Select the nearest surviving neighbor from the previous order, then first result if no neighbor survives |
| Page appended | Preserve selection and scroll anchor; do not jump to the first item |
| Shift-range selection | Preserve selected identities on passive updates; deliberate query/filter changes reset to one item |
| Fresh panel invocation | Retain the existing fresh-search behavior; select first displayed result after loading |

“First displayed” deliberately preserves the current pins-first ordering. Changing Recent/Saved behavior is item 5, not a hidden dependency here.

### Focus and asynchronous search rules

1. Track focus explicitly: results, search editor, action menu, or secondary editor/window. Visual result selection can remain visible while search owns text input.
2. Typing from results transfers the complete text input to search. Preserve IME composition, composed Unicode, punctuation, and spaces; do not rely on forwarding only the first character of a composition.
3. While editing search, ordinary cursor navigation, selection, Command-A/C/V/X/Z and composition commands belong to the text editor. Tab moves between search and results. Vertical Up/Down can enter result navigation when not composing; Left/Right must remain text movement while editing.
4. Return in search activates the current matching result only after composition is committed and results correspond to the current raw query.
5. If Return arrives during debounce/loading, flush the debounce and queue one activation bound to that exact query generation. Activate only after matching results and selection are displayed. Cancel the queued intent if the query, focus surface, or panel visibility changes, or the load fails/returns empty. Never paste an old visible result for a newer typed query.
6. Repeated Return while one activation is pending must not post multiple pastes. A loading/disabled primary action communicates the wait.
7. Numbered shortcuts target the currently displayed numbered items; do not remap them to hidden entries. Prevent activation of stale results during a pending query replacement.
8. Ignore result commands when Settings, an editor, permission UI, or another secondary window owns input.

### Implementation work

- Introduce a small selection coordinator/model using persistent item identity as its source of truth. Derive visible indices for scrolling, badges, and range navigation.
- Reconcile selection when a result generation is accepted, rather than unconditionally clearing it around every reload.
- Make query generation, pending activation, and focus ownership explicit. Reuse existing cancellation/generation checks and bounded paging.
- Wire search submission through `SearchFieldView` / `FocusableTextField` to the same primary activation dispatcher as Return on results.
- Keep focus distinct from selection. Add accessible selected-state semantics and an accessible activate action to cards.
- Avoid stealing text-field Undo/Copy while introducing automatic selection.

Primary files: `FilteredCardListView.swift`, `PanelContentView.swift`, `SearchFieldView.swift`, `FocusableTextField.swift`, `ClipboardCardView.swift`; shared identity reconciliation may also be reusable by `HistoryGridView.swift`, but do not redesign that view in this step.

### Acceptance criteria

- With a nonempty history, open → Return acts on the visibly selected first item without an arrow key.
- Type a query → Return uses its first matching result, including Return pressed within the debounce interval.
- Copy a new item while another is selected: the selected clip remains the same.
- Background page loads do not reset the scroll position or selection.
- Search text selection, copy, paste, undo, and IME composition behave normally.
- Empty/error states cannot act on stale selection or overwrite the system clipboard.
- Both horizontal and vertical panels, all four edges, and multiple keyboard layouts retain their existing navigation conventions.

## 2. Explicit primary and secondary actions

### Core problem

An action's name must describe its effect. People should not need to remember a hidden preference to interpret a button labeled Paste.

The panel also exposes many useful operations mainly through right-click and undocumented shortcuts. A visible action affordance should reveal these operations and teach shortcuts progressively.

### What exists and why it needs an update

- `Pastel/Models/PasteBehavior.swift` contains Paste, Copy to Clipboard, and Copy + Paste. Paste and Copy + Paste currently have identical effects.
- `PasteService.swift` distinguishes respect-preference versus copy-only. Explicit Paste and Paste as Plain Text entry points still respect the copy-only preference.
- Cards, Return, numbered shortcuts, and the History bulk bar share callbacks whose names do not fully express whether the user requested default activation or explicit paste.
- `ClipboardCardView.swift` has a useful context menu, but there is no consistent visible primary-action label or keyboard-discoverable Actions surface.
- General settings currently uses the explanatory notation Command-N for the Nth item, which is easily confused with the actual Command-N new-snippet shortcut.

### Proposed action model

Separate action intent from representation and origin:

- Intent: default activation, explicit copy, explicit paste.
- Representation: original or plain text.
- Origin: panel or History window, retaining existing dismissal choreography.
- Target: external application captured when the panel opens, revalidated before posting; never infer a target from the source app shown on a clip.

| User action | Contract |
|---|---|
| Return, double-click, Command-1…9 | Perform the configured primary action |
| Shift-Return, Shift-double-click, Command-Shift-1…9 | Perform the configured primary action using plain text; label it Copy as Plain Text in copy mode |
| Explicit Copy menu/button; Option-click; Command-Control-1…9 | Always copy, without synthetic paste |
| Explicit Paste menu/button | Always request paste, regardless of primary-action preference |
| Explicit Paste as Plain Text menu/button | Always request paste of the plain-text representation |
| Command-C | Copy selected clips only when results own the command; otherwise preserve ordinary text editing |

Use the preference label **Primary action** with two options: **Paste into active app** and **Copy to clipboard**. Explain that it controls Return, double-click, and numbered activation shortcuts. This is more accurate than labeling the setting only “Return key.”

Migration: map stored `copyAndPaste` to `paste`; retain `copy` and `paste`; preserve existing fresh-install and permission/onboarding behavior unless deliberately changed and documented. Normalize invalid/missing defaults through one shared resolver so UI and service cannot disagree. Do not silently switch an existing copy-only user to paste mode.

### Visible interface

- Add a restrained single-row action strip integrated with the panel layout: **Paste into Notes ↵** on one side, **Actions ⌘K** on the other. In copy mode: **Copy to Clipboard ↵**.
- Both are real accessible controls. Keep the first clip visible at supported panel sizes; measure the space cost in horizontal mode before finalizing placement.
- Shift updates the primary label to its plain-text variant where meaningful. Images/files must not misleadingly advertise text conversion.
- Empty or pending result sets disable activation and communicate why. Long app names truncate with the full destination in the accessible label/help.
- If no reliable external destination exists, do not display a guessed app name or post to an arbitrary app. Explain that the item can be copied instead.
- Missing permission or Secure Input must never be reported as successful paste. Preserve copy fallback and clearly say **Copied. Press ⌘V to paste.** Offer contextual permission recovery when necessary.
- Revalidate destination before posting. If another app became active, do not silently send content somewhere different from the advertised target; keep the content copied and explain the fallback.
- Avoid success notifications for every routine successful action. Feedback is needed for changed outcomes, failures, or unexpected fallback.

### Actions surface

- A clickable Actions control and Command-K reveal actions for the selected clip. Use a native menu/popover where feasible; no new full-screen command center.
- Show primary activation first, then explicit Copy/Paste/plain-text choices, then applicable Edit, Pin/Unpin, label assignment, and Delete. Reuse existing capability checks and callbacks.
- Display actual keyboard shortcuts alongside commands. Keep the existing right-click menu as another entry point to the same action definitions.
- Escape closes Actions first and returns focus/selection to the invoking surface. It must not immediately dismiss the entire panel as well.
- Opening or navigating Actions must not steal or change the intended paste destination.
- Searchable action filtering is optional later; a small keyboard-accessible menu is sufficient for the initial scope.
- For mixed multi-selection, describe the actual supported text count and excluded non-text clips. Disable all-non-text bulk actions that cannot produce output. Preserve existing text-only bulk serialization; broader multi-format bulk paste is separate work.

### Implementation work

1. Add shared action intent/presentation resolution so labels, enabled states, shortcuts, and execution have one source of truth.
2. Update PasteBehavior persistence/migration and settings/onboarding copy together.
3. Separate default activation from explicit paste entry points in PasteService. Preserve write validation, pending capture draining, exact change-count suppression, secure-input checks, keyboard-layout handling, and focus handoff.
4. Audit all panel, card-context-menu, History, bulk, and plain-text callers; do not fix only the footer.
5. Add destination lifecycle handling around panel presentation and the existing paste handoff, without replacing the sandbox-compatible paste mechanism.
6. Add action-strip and Actions UI with labels, focus restoration, appropriate disabled states, and light/dark appearance support.
7. Update shortcut help to use Command-1 through Command-9 explicitly; reserve Command-N wording for New Snippet.

Primary files: `PasteBehavior.swift`, `PasteService.swift`, `AppState.swift`, `PanelController.swift`, `PanelContentView.swift`, `FilteredCardListView.swift`, `ClipboardCardView.swift`, `HistoryBrowserView.swift`, `GeneralSettingsView.swift`, `OnboardingView.swift`.

### Acceptance criteria

- For every activation entry point, the visible label and actual behavior agree in both primary-action modes.
- Explicit Paste still pastes for a copy-mode user; explicit Copy never pastes for a paste-mode user.
- Legacy preferences migrate without changing their observable meaning.
- Destination app labels remain accurate through Actions and focus handoff; target changes do not misdirect content.
- Permission loss, Secure Input, missing content, or missing target produce truthful outcomes and preserve existing clipboard safeguards.
- Actions is discoverable with mouse, keyboard, and VoiceOver; closing it restores focus predictably.
- Shift/plain-text and numbered shortcuts do not inherit contaminating modifiers or regress non-QWERTY behavior.

## Delivery sequence and verification

1. Record baseline flows and inspect current implementation/tests. Reuse the paste-reliability plan's constraints.
2. Implement item 1 selection identity and focus/search contracts with focused state-transition tests.
3. Implement item 2 action resolution and preference migration with a table-driven intent × preference × representation test matrix.
4. Wire the primary-action strip and Actions surface to the same execution model; run relevant builds and existing smoke checks for touched paths.
5. Manually exercise open/type/Return, fast typing, IME, background capture, empty results, multi-selection, Actions dismissal, copy-only mode, permission fallback, and paste into TextEdit/Notes plus a code editor or terminal.
6. Check light/dark appearance, VoiceOver, Full Keyboard Access, reduced motion, narrow horizontal panels, and all four edges. Do not claim runtime accessibility support from code review alone.

Measure action count, time to correct paste, and wrong-item/wrong-destination outcomes using a repeatable local task set. No analytics collection is required. Target: eliminate the extra arrow step; zero stale-query or changed-index activations in the test matrix; no added fixed delay on an already-ready result.

## 3. Space-to-preview

Accepted direction: preserve the core preview interaction demonstrated by other clipboard apps, while designing the presentation specifically for Pastel. Details below are implementation defaults proposed by this plan, not claims that the user individually chose every detail.

### Problem and current gap

Cards intentionally truncate content. Two long clips can share the same opening lines, and a thumbnail cannot confirm fine image detail. Pastel has a custom image viewer and an Edit window, but no uniform read-only inspection command across content types. Inspection should not require entering editing mode or changing the clipboard.

### Proposed interaction

1. Select a clip using arrows or a single click.
2. Press Space while results have focus, or choose Preview from Actions/context menu.
3. Show a temporary, readable preview adjacent to the panel toward screen center. Keep the originating selection and panel visible when space permits. At top/bottom edges, position inward; clamp to the active display's usable area. A centered fallback can serve small displays.
4. Space again or Escape closes preview and restores the same clip, scroll position, query, and focus. A subsequent Escape can dismiss the panel.
5. Return performs the clearly labeled primary action, then dismisses both surfaces using existing paste choreography. When a child control owns Return, honor that control first; never intercept IME composition or editing input.
6. Preview has no capture/write/paste/edit side effects. No automatic browser navigation, remote page loading, or file execution.
7. Space in search/editor still inserts a space. Tab can move from search to results before preview; the visible Preview action also supports mouse and assistive technology use.

### Content presentation proposal

| Type | Preview |
|---|---|
| Text/code | Scrollable complete content, selectable text; code uses readable syntax styling within existing work budgets |
| Rich text | Clearly distinguish formatted versus plain-text representation; final control design to discuss |
| Image | Larger fitted image with dimensions and optional zoom |
| URL | Full URL plus cached title/image; do not automatically visit the URL |
| File/PDF | System Quick Look where supported and accessible; missing/inaccessible file gets an honest unavailable state |
| Color | Larger swatch and exact stored value; alternate formats remain explicit actions |

Use native Quick Look where practical, with a consistent Pastel shell/fallback for clipboard values that are not ordinary files. Decide implementation after testing nonactivating panel focus and sandbox access. Temporary representations, if necessary, need lifecycle cleanup and must not enter clipboard history.

### Pastel's visual direction: familiar interaction, distinct appearance

- Use an **adjacent reading surface** anchored toward the screen center from the existing edge panel. Preserve the originating card, its outset selection ring, and the user's sense of place. Do not resize/reflow the history cards merely to inspect one clip.
- Reuse `PanelStyle` typography and semantic colors, `PanelLayout` geometry, system appearance, and the existing restrained accent. Use standard system controls; let the existing rounded typography carry Pastel's warmth.
- Organize the surface as a quiet header (source icon, short title/type, Close), a generous content area, and a compact footer carrying the same primary action as item 2 plus `Esc Close` help. Keep secondary metadata subdued.
- Use a readable standard material or opaque adaptive content background. Reserve any floating glass treatment for the outer shell/control layer. Honor Reduce Transparency and Increase Contrast; do not put small text on multiple nested glass surfaces.
- Avoid copying competitors' colored title slabs, toolbar composition, card proportions, branding, decorative backgrounds, or exact inspector layouts. Distinction should come from Pastel's established components, not unfamiliar interaction conventions.
- One selected item opens one preview. Promotional screenshots showing several preview windows simultaneously are content-type demonstrations, not a model for Pastel's window behavior.
- Editing remains an explicit action. Initial preview is read-only; selecting text for inspection/copy is allowed without entering Edit.
- Keep source metadata distinct from the destination label: a clip copied from Safari can still say `Paste into Notes` in the footer.

### Implementation defaults and remaining refinements

- Use temporary adjacent preview, with an in-bounds centered fallback on small displays.
- Return activates through the shared action model; Space/Escape dismiss inspection first.
- Arrows browse adjacent clips when the preview container owns focus; preserve native text-selection/scroll behavior when the content owns focus.
- Cover every existing clip type with either a supported renderer or a truthful unavailable/metadata fallback. Text/code/images are the first renderer implementation slice, not the whole feature's completion criterion.
- For multiple selected clips, preview the focused clip and indicate its position in the selection. Do not imply that one preview combines all selected content. The action footer must distinguish acting on the selection from inspecting its focused member.
- Rich text gets a native Formatted / Plain Text segmented control when both representations exist. Switching inspection representation does not silently change the configured activation mode; explicit plain-text action remains available.

Do not ship preview hints or an inert Preview command as part of items 1 and 2. Add them with the working item 3 implementation.

### Implementation sequence and acceptance

1. Add a preview coordinator bound to selected item identity, captured target app, and the invoking surface's focus/scroll state. Use one preview lifecycle for keyboard, Actions, and context-menu entry points.
2. Implement type-specific rendering, loading, unavailable states, and bounded expensive work; reuse existing image loading and text work budgets. Treat copied HTML as untrusted content and render without scripts or remote resource loads.
3. Integrate native Quick Look for supported files where sandbox access permits. Verify window levels so the preview is never hidden behind the floating panel; do not assume a standard Quick Look panel's default level works.
4. Wire hierarchical Escape handling, Space toggle, scoped arrow navigation, and the shared primary action. Explicitly test target preservation through opening, closing, and activating from preview.
5. Verify no clipboard write, new capture, timestamp mutation, or history reordering occurs merely from opening/closing a preview.
6. Test long text, large images, rich text, code, full URLs, colors, missing files, unsupported files, multiple selection, deletion/sync removal while preview is open, four panel edges, multiple displays, and fullscreen apps. When the inspected item disappears, close its preview and reconcile selection safely.
7. Validate keyboard-only operation, VoiceOver labels/order, light/dark modes, reduced motion/transparency, readable contrast, and focus restoration. Escape must not inadvertently close both surfaces on one keypress.

Likely files: new preview coordinator/view(s), `PanelController.swift`, `PanelContentView.swift`, `FilteredCardListView.swift`, `ClipboardCardView.swift`, `ImageViewerView.swift`, shared action definitions from item 2, and existing content rendering/loading services. Do not replace the proven paste-back mechanism.

## References and screenshot provenance

Behavior sources, consulted October 9, 2026:

- [Maccy](https://maccy.app/): lightweight keyboard-first retrieval.
- [Raycast Clipboard History](https://manual.raycast.com/clipboard-history): primary-action choice and explicit secondary operations.
- [Raycast Action Panel](https://manual.raycast.com/action-panel): Return for primary action, Command-K for contextual actions, Escape to return.
- [Paste on Mac](https://pasteapp.io/help/paste-on-mac): visual retrieval and Space for Quick Look.
- [Paste keyboard shortcuts](https://pasteapp.io/help/keyboard-shortcuts): confirms Space preview shortcut.
- [PastePal Quick Start](https://docs.indiegoodies.com/pastepal/Mac/quick-start): Space preview, Shift-Space plain text, Tab between search and clips.
- [Apple keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards/): standard shortcuts and Full Keyboard Access.

Screenshot references are design examples, not screenshots of Pastel or promises about exact current competitor versions:

- [Paste official preview/edit illustration](https://pasteapp.io/_next/static/media/img-4.1zzpoo5byu-_y.png), from its Mac guide. Inspect before citing particular visual details; the page groups preview and editing together.
- [Paste official action illustration](https://pasteapp.io/_next/static/media/img-3.2xyq4uftrz_qg.png), from its Mac guide.
- [Raycast clipboard screenshot](https://www.nathanbrachotte.dev/_next/image?q=75&url=%2Fimages%2Fblog%2Fone-app-to-rule-them-all%2Fclipboard-history.webp&w=3840), reproduced in [Nathan Brachotte's article](https://www.nathanbrachotte.dev/blog/one-app-to-rule-them-all). Third-party visual reference for the selection/detail relationship and destination-aware action footer; official Raycast docs establish the behavior.

No competitor artwork is to be copied into Pastel's shipped UI.

### Screenshot inspiration board

These remote embeds are reference-only and remain attributed to their owners. They show existing preview interfaces, not proposed Pastel mockups. They may show older versions. A still image cannot prove which key opened it; keyboard behavior is established separately by the linked official documentation.

#### A. Paste: expanded previews across content types

![Paste expanded previews for links, text, files, and images](https://pasteapp.io/_next/static/media/cover.2-efsawb02v6n.png)

[Official source: Paste, Enhanced Preview and Editing Tools, July 24, 2024](https://pasteapp.io/updates). The accompanying release note explicitly identifies Space as the preview shortcut.

Borrow: a readable, expanded representation appropriate to each content type. Adapt: one Pastel reading surface with shared header/footer rather than reproducing this window styling or its editing tools.

#### B. Paste: Quick Look above the history strip

![Paste Quick Look overlay above its clipboard history](https://miro.medium.com/v2/resize%3Afit%3A2000/1%2A6SDMZ-TP9UNk4N-gE5a3cA.png)

[Source: Paste's Link previews article](https://medium.com/pasteapp/link-previews-d01f190ab06c). Historical visual reference showing the relationship between the history and temporary enlarged content.

Borrow: inspect without losing the underlying history context. Adapt: placement follows Pastel's chosen edge, with local/cached URL information instead of automatically loading a web page or video.

#### C. Pastebot: image preview with secondary metadata

![Pastebot clipping image preview with metadata](https://tapbots.com/pastebot/assets/clipboard_history/preview.jpg)

[Official source: Pastebot](https://tapbots.com/pastebot/). This is a preview-layout reference; the exact Space shortcut for this version has not been verified and is not asserted here.

Borrow: image content dominates while dimensions/source details remain secondary. Adapt: use Pastel's own header, compact action footer, typography, and adaptive material instead of a copied inspector window.

PastePal's [official quick-start guide](https://docs.indiegoodies.com/pastepal/Mac/quick-start) separately confirms Space for preview and Shift-Space for plain text. Its readily available screenshots mostly show history or menus, so they are intentionally not mislabeled here as expanded Space-to-preview screenshots.
