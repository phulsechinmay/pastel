---
phase: quick
plan: 010
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/ClipboardCardView.swift
  - Pastel/Views/Panel/FilteredCardListView.swift
  - Pastel/Views/Panel/PanelContentView.swift
autonomous: true

must_haves:
  truths:
    - "Each card shows a footer row with type-appropriate metadata text left-aligned"
    - "Text/richText cards show character count (e.g. '128 chars') in footer"
    - "URL cards show domain name (e.g. 'github.com') in footer"
    - "Image cards show pixel dimensions (e.g. '1920 x 1080') in footer"
    - "Code cards show character count + language if detected (e.g. '256 chars - Swift') in footer"
    - "Color and file cards have no footer metadata text"
    - "Cmd+N badge appears right-aligned inside the footer row, not as an overlay"
    - "Badge is text-only (no rounded rect background or border)"
    - "When Shift is held while panel is open, badges show the shift symbol (e.g. Cmd+Shift+1 instead of Cmd+1)"
    - "When Shift is released, badges revert to Cmd+N"
  artifacts:
    - path: "Pastel/Views/Panel/ClipboardCardView.swift"
      provides: "Footer row with metadata + restyled inline badge"
    - path: "Pastel/Views/Panel/FilteredCardListView.swift"
      provides: "NSEvent flagsChanged monitor for Shift tracking, passes isShiftHeld to cards"
    - path: "Pastel/Views/Panel/PanelContentView.swift"
      provides: "isShiftHeld state passed down to FilteredCardListView"
  key_links:
    - from: "PanelContentView"
      to: "FilteredCardListView"
      via: "isShiftHeld binding or parameter"
    - from: "FilteredCardListView"
      to: "ClipboardCardView"
      via: "isShiftHeld parameter on each card"
    - from: "ClipboardCardView"
      to: "KeycapBadge"
      via: "isShiftHeld parameter controlling badge text"
---

<objective>
Add a metadata footer row to clipboard cards and make the Cmd+N quick-paste badges dynamic.

Purpose: Cards currently show only content preview. Adding a footer with type-specific metadata (char count, domain, dimensions, language) gives users at-a-glance context. Moving the badge into the footer and making it react to Shift key press communicates the plain-text paste option visually.

Output: Updated ClipboardCardView with footer, restyled KeycapBadge, Shift-key tracking from PanelContentView through FilteredCardListView to cards.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/ClipboardCardView.swift
@Pastel/Views/Panel/FilteredCardListView.swift
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Models/ClipboardItem.swift
@Pastel/Models/ContentType.swift
@Pastel/Services/ImageStorageService.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add Shift key tracking in PanelContentView and FilteredCardListView</name>
  <files>
    Pastel/Views/Panel/PanelContentView.swift
    Pastel/Views/Panel/FilteredCardListView.swift
  </files>
  <action>
**PanelContentView.swift:**
1. Add `@State private var isShiftHeld = false` state variable.
2. Add an `onAppear` block (merge with the existing one) that installs an `NSEvent.addLocalMonitorForEvents(matching: .flagsChanged)` monitor. In the handler, set `isShiftHeld = event.modifierFlags.contains(.shift)` and return the event unchanged. Store the monitor reference in a `@State private var flagsMonitor: Any?` variable.
3. Add an `onDisappear` that calls `NSEvent.removeMonitor(flagsMonitor!)` if non-nil, and sets it to nil. Also reset `isShiftHeld = false` on disappear so stale state does not persist across panel show/hide cycles.
4. Pass `isShiftHeld` as a new parameter to `FilteredCardListView`. The existing `FilteredCardListView(searchText:selectedLabelID:selectedIndex:onPaste:onPastePlainText:onTypeToSearch:)` call gets an additional `isShiftHeld: isShiftHeld` argument.

**FilteredCardListView.swift:**
1. Add `var isShiftHeld: Bool` stored property (NOT a binding, just a plain Bool parameter -- it is read-only from this view's perspective).
2. Add the parameter to the `init(...)` signature with a default of `false` so nothing else breaks.
3. In BOTH the horizontal and vertical `ForEach` loops, pass `isShiftHeld: isShiftHeld` to each `ClipboardCardView(...)` initializer.

**Important implementation notes:**
- Use `addLocalMonitorForEvents` (local), NOT `addGlobalMonitorForEvents`. The panel is our own window so local monitors capture flagsChanged within it. Global monitors require Accessibility permission which we should not add for this feature.
- The monitor must return the event (not nil) to avoid swallowing it.
- Type the monitor variable as `Any?` since `NSEvent.addLocalMonitorForEvents` returns `Any?`.
  </action>
  <verify>
Project builds successfully with `xcodebuild -scheme Pastel build 2>&1 | tail -5`. No compiler errors related to the new parameter threading.
  </verify>
  <done>
isShiftHeld state is tracked via NSEvent local monitor in PanelContentView, threaded through FilteredCardListView to ClipboardCardView. Monitor is installed on appear and removed on disappear.
  </done>
</task>

<task type="auto">
  <name>Task 2: Add card footer with metadata and restyled inline badge</name>
  <files>
    Pastel/Views/Panel/ClipboardCardView.swift
  </files>
  <action>
**Add `isShiftHeld` property to ClipboardCardView:**
1. Add `var isShiftHeld: Bool` stored property (default `false` in init).
2. Update the `init(...)` to accept `isShiftHeld: Bool = false`.

**Restyle KeycapBadge to text-only with Shift awareness:**
1. Add `var isShiftHeld: Bool = false` parameter to `KeycapBadge`.
2. Remove the `.background(RoundedRectangle...)` modifier entirely.
3. Remove the `.overlay(RoundedRectangle... strokeBorder)` modifier entirely.
4. Remove the `.padding(.horizontal, 5)` and `.padding(.vertical, 3)` that existed for the background.
5. Update the HStack content: when `isShiftHeld` is true, show three items: `"\u{2318}"` then `"\u{21E7}"` (shift symbol) then `"\(number)"`. When false, show the existing two items: `"\u{2318}"` then `"\(number)"`.
6. Keep `.foregroundStyle(.white.opacity(0.5))` -- slightly dimmer than the old 0.7 since there is no background to contrast against.
7. Use `.font(.system(size: 10, weight: .medium, design: .rounded))` for the whole HStack instead of individual font modifiers, for consistency.

**Add footer row to ClipboardCardView body:**
1. Remove the existing `.overlay(alignment: .bottomTrailing)` block that renders the badge (lines ~100-105 in the current file).
2. Inside the main `VStack(alignment: .leading, spacing: 6)`, AFTER `contentPreview`, add a new footer view conditionally. The footer should appear when EITHER there is metadata text to show OR a badge to show.
3. The footer is an `HStack(spacing: 4)`:
   - Left side: metadata text (if any) styled with `.font(.caption2)` and `.foregroundStyle(isColorCard ? colorCardTextColor.opacity(0.5) : .secondary.opacity(0.7))`, `.lineLimit(1)`.
   - `Spacer()` (pushes badge right).
   - Right side: `KeycapBadge(number: badgePosition, isShiftHeld: isShiftHeld)` if `badgePosition` is non-nil.

**Metadata text logic -- add a computed property `private var footerMetadataText: String?`:**
- `.text`, `.richText`: Return `"\(item.characterCount) chars"`. If characterCount is 0 and textContent exists, use `textContent!.count` as fallback.
- `.url`: Extract domain from `item.textContent` using `URL(string:)?.host`. If host starts with "www.", strip it. Return the domain string, or nil if URL parsing fails.
- `.image`: Read image dimensions lazily. Use `ImageStorageService.shared.resolveImageURL(item.imagePath!)` to get the file URL, then use `CGImageSourceCreateWithURL` + `CGImageSourceCopyPropertiesAtIndex` to read `kCGImagePropertyPixelWidth` and `kCGImagePropertyPixelHeight` without loading the full image into memory. Return `"\(width) x \(height)"`. If imagePath is nil or dimensions can't be read, return nil. Use the multiplication sign character `\u{00D7}` (×) between dimensions for polish.
- `.code`: Start with `"\(item.characterCount) chars"`. If `item.detectedLanguage` is non-nil and non-empty, append ` \u{00B7} \(item.detectedLanguage!.capitalized)` (middle dot separator). Return the combined string.
- `.color`: Return nil (hex is already prominent on the card).
- `.file`: Return nil (file path is already shown on the card).

**For image dimensions**, since reading from disk on every render is expensive, wrap the dimension reading in a `@State private var imageDimensions: String?` and load it in `.task { }` on the card (which runs once when the view appears). The `footerMetadataText` computed property for `.image` type should return `imageDimensions` directly. The `.task` block should only run the dimension logic if `item.type == .image`.

**Footer visibility logic:**
Only show the footer HStack if `footerMetadataText != nil || badgePosition != nil`. For color and file cards with no badge, no footer row appears at all. This keeps those cards clean.

**Do NOT change:** Card sizing, padding, background, border, or any other existing visual properties. The footer fits within the existing card layout naturally since VStack will expand to accommodate it.
  </action>
  <verify>
1. `xcodebuild -scheme Pastel build 2>&1 | tail -5` -- project compiles cleanly.
2. Run the app. Copy some text, a URL, an image, and some code. Verify each card type shows the correct footer metadata.
3. Verify Cmd+1-9 badges appear in the footer row (right-aligned), not as an overlay.
4. Verify badges have no background/border (text only).
5. Hold Shift while panel is open -- badges should show the shift symbol.
6. Release Shift -- badges should revert.
  </verify>
  <done>
Cards display type-appropriate metadata in a footer row. Badge is inline in the footer with text-only styling. Badge dynamically shows shift symbol when Shift key is held. Color and file cards show no footer unless they have a badge position.
  </done>
</task>

</tasks>

<verification>
1. Build succeeds: `xcodebuild -scheme Pastel build`
2. Text card footer shows character count (e.g., "128 chars")
3. URL card footer shows domain (e.g., "github.com")
4. Image card footer shows dimensions (e.g., "1920 x 1080")
5. Code card footer shows char count + language (e.g., "256 chars - Swift")
6. Color cards have no footer (unless badge position assigned)
7. File cards have no footer (unless badge position assigned)
8. Badge is text-only, right-aligned in footer, no background or border
9. Holding Shift changes badge from "Cmd+1" to "Cmd+Shift+1"
10. Releasing Shift reverts badge display
11. Monitor installs on panel appear, removes on disappear (no leaks)
</verification>

<success_criteria>
- All card types show correct footer metadata per their type
- Badge is repositioned from overlay to inline footer, restyled as text-only
- Shift key state dynamically reflected in badge display
- No regressions to card layout, selection, hover, context menus, or paste functionality
- Clean build with no warnings related to these changes
</success_criteria>

<output>
After completion, create `.planning/quick/010-card-footer-and-dynamic-badges/010-SUMMARY.md`
</output>
