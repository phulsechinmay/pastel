# Horizontal panel and card usability, items 1–4

Date: 2026-10-10
Branch: `ux-learnings`
Status: Implemented in source; live visual and accessibility QA pending

## Outcome

Make the top/bottom quick panel shorter and easier to scan without losing explicit actions or Command-1–9 shortcuts. The panel remains a fast find-and-use surface; History is outside this change. The approved card detail is a persistent shortcut chip at bottom right, with useful type-specific subtext aligned at bottom left.

## Current cause

`PanelContentView` adds a persistent action bar below the one-row card strip. Its horizontal header also competes with search and labels for space. `ClipboardCardView` reserves a footer for titles/number badges and pushes it down with a flexible spacer. A URL can reserve a 106 pt media well for only a favicon; image previews stop at 120 pt; file cards repeat full paths. The action bar already computes truthful destination and mixed-selection labels, so moving its controls must preserve that logic.

## Work and acceptance

1. **Panel structure.** Put a real, compact primary-action button (`↵ Paste` or `↵ Copy`) and one selection-level More button in the horizontal header. Reuse the existing Actions popover and activation path. Remove the horizontal bottom bar and lower the default top/bottom panel height by the recovered area. Keep the vertical bar until separately reviewed. Full action and destination remain in Help, accessibility, the popover, and Space preview. Empty/loading selection disables both controls. Verify Return, double-click, Command-K, right-click, Copy mode, absent target, and Shift plain-text behavior.
2. **Search and toolbar.** Give search a useful minimum width. Bound the inline label bar so overflow/wrapping handles long collections. Move infrequent horizontal utilities into a Tools menu while keeping New Snippet and Settings reachable with existing shortcuts. The filter control already signals active state and FilterBar has Clear; preserve those behaviors. Check narrow displays, two label rows, and expanded Type/App/Date filters without squeezing the search field or hiding actions.
3. **Cards and previews.** Use an explicit presentation context so horizontal changes do not alter History. Keep the shortcut keycap at bottom right and place content-specific subtext on the same baseline at left. Put user titles next to excerpts. Cap true URL banners in the strip and avoid a large well for favicon-only links; keep full URL via Help/Space preview. Let horizontal images fit their available content area, preserving aspect ratio. Show a bounded file thumbnail/icon plus filename and parent folder; leave full path in Space preview/Help. Maintain a high-contrast bottom row on image/color cards. Verify text, rich text, URL states, image, code, file, and color at both top and bottom edges.
4. **Selections.** Keep the actual selection ring. When several clips are selected, show the count and an accurate primary verb/eligible text count without suggesting only the focused card acts. The More menu operates on the whole selected range; card right-click retains its existing target rules. A selection change must not move card content, trigger an action, or alter the captured paste destination.

## Verification

- Both macOS schemes compile; run focused existing action and selection smoke checks.
- Inspect a running build when app automation permits: top/bottom on compact and large displays, light/dark, busy backdrop, two-row labels, long destination, no target, Copy mode, mixed range, and VoiceOver/keyboard focus.
- Mark any visual or accessibility check that cannot be observed locally as pending rather than claiming it passed.

### Implementation result, 2026-10-10

- Horizontal panel action and More moved into the top row; the bottom action strip remains in the vertical panel only. Base top/bottom panel height is 244 pt instead of 270 pt.
- Search has a 190 pt minimum and label chips a bounded 420 pt region. Infrequent colour picker and panel-position utilities share a Tools menu; New Snippet and Settings remain direct.
- Strip-specific card presentation is explicit. Titles sit with content; one label plus count fits the header; the existing Command-number chip remains at bottom right with type-specific detail opposite it. URL banners are shorter, favicon-only links omit the large well, images fit remaining height, files use system icons and parent folders, and color foreground selection uses linearized luminance. History geometry stays separate.
- Multi-selection top-row copy/paste cues and full popover commands show eligible text count; all-image/file ranges cannot claim to copy or paste text. Unknown app name now says “active app” rather than incorrectly promising Copy.
- App Store and Sparkle Debug builds pass with code signing off. Existing UX action-policy and selection-reconciliation smoke checks pass. A UI inspection attempt timed out, so actual rendered spacing, interaction timing, VoiceOver order, and narrow-display behavior remain pending.

## Non-goals

Do not redesign History, capture, ranking, retention, sync, paste delivery, or clipboard serialization. Preserve the untracked `docs/UI_UX_IMPROVEMENT_PLAN.md` supplied by another agent.
