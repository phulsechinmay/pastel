---
phase: quick-021
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/FilteredCardListView.swift
  - Pastel/Views/Panel/PanelContentView.swift
  - Pastel/Views/Panel/PanelController.swift
  - Pastel/Views/Settings/SettingsView.swift
  - Pastel/Views/Settings/HistoryBrowserView.swift
  - Pastel/Views/MenuBar/StatusPopoverView.swift
  - Pastel/Views/Onboarding/OnboardingView.swift
autonomous: true
must_haves:
  truths:
    - "Holding an arrow key rapidly iterates through cards (key repeat works)"
    - "All UI text uses the rounded font design (except monospaced code/hex)"
    - "In top/bottom panel edge modes, header-to-cards gap is tighter"
  artifacts:
    - path: "Pastel/Views/Panel/FilteredCardListView.swift"
      provides: "Key repeat navigation via .onKeyPress phases: [.down, .repeat]"
    - path: "Pastel/Views/Panel/PanelContentView.swift"
      provides: "Rounded font + reduced horizontal-mode padding"
  key_links:
    - from: "FilteredCardListView.swift"
      to: ".onKeyPress"
      via: "phases parameter including .repeat"
      pattern: "phases.*\\.repeat"
---

<objective>
Enable key repeat for arrow key navigation, apply rounded font design across the app, and reduce header-to-cards padding in top/bottom panel modes.

Purpose: Improve navigation feel (rapid card browsing), visual polish (rounded font), and density (less wasted space in horizontal mode).
Output: Updated FilteredCardListView, PanelContentView, PanelController, and font propagation across views.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/FilteredCardListView.swift
@Pastel/Views/Panel/PanelContentView.swift
@Pastel/Views/Panel/PanelController.swift
@Pastel/Views/Settings/SettingsView.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Enable key repeat on arrow key navigation</name>
  <files>Pastel/Views/Panel/FilteredCardListView.swift</files>
  <action>
In FilteredCardListView.swift, update the four arrow key `.onKeyPress` handlers to include the `.repeat` phase so holding an arrow key rapidly iterates through cards.

Current pattern (all four arrow handlers):
```swift
.onKeyPress(.upArrow) { ... }
.onKeyPress(.downArrow) { ... }
.onKeyPress(keys: [.leftArrow]) { keyPress in ... }
.onKeyPress(keys: [.rightArrow]) { keyPress in ... }
```

Change to:
```swift
.onKeyPress(.upArrow, phases: [.down, .repeat]) { ... }
.onKeyPress(.downArrow, phases: [.down, .repeat]) { ... }
.onKeyPress(keys: [.leftArrow], phases: [.down, .repeat]) { keyPress in ... }
.onKeyPress(keys: [.rightArrow], phases: [.down, .repeat]) { keyPress in ... }
```

The `.onKeyPress` API with `KeyEquivalent` (upArrow, downArrow) supports `phases:` as a second parameter. The variant with `keys:` Set also supports `phases:` as a second parameter. The body closures remain unchanged.

Do NOT add `.repeat` to the Return key, digit keys, shifted digit keys, or alphanumeric type-to-search handlers -- only the four arrow keys.
  </action>
  <verify>Build succeeds with `cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodebuild -scheme Pastel -configuration Debug build 2>&1 | tail -5`. Open panel, hold right arrow -- card selection should advance rapidly through items.</verify>
  <done>All four arrow key handlers include `phases: [.down, .repeat]`. Holding any arrow key rapidly iterates through cards.</done>
</task>

<task type="auto">
  <name>Task 2: Apply rounded font design and reduce horizontal header padding</name>
  <files>
    Pastel/Views/Panel/PanelContentView.swift
    Pastel/Views/Panel/PanelController.swift
    Pastel/Views/Settings/SettingsView.swift
    Pastel/Views/Settings/HistoryBrowserView.swift
    Pastel/Views/MenuBar/StatusPopoverView.swift
    Pastel/Views/Onboarding/OnboardingView.swift
  </files>
  <action>
**Part A: Rounded font via `.fontDesign(.rounded)` at top-level views**

Apply `.fontDesign(.rounded)` as a modifier on the root view hierarchy so it cascades to all child views using semantic fonts (`.headline`, `.caption`, `.subheadline`, `.body`, `.callout`, `.title`, etc.).

1. In `PanelContentView.swift`, add `.fontDesign(.rounded)` to the outermost `VStack` (before `.frame(maxWidth:maxHeight:)`):
   ```swift
   .fontDesign(.rounded)
   .frame(maxWidth: .infinity, maxHeight: .infinity)
   ```

2. In `PanelController.swift`, on the hosted `PanelContentView()` (line ~412), the `.fontDesign(.rounded)` will cascade from PanelContentView itself, so no change needed here.

3. In `SettingsView.swift`, add `.fontDesign(.rounded)` to the root TabView or outermost container.

4. In `HistoryBrowserView.swift`, add `.fontDesign(.rounded)` to the outermost container.

5. In `StatusPopoverView.swift`, add `.fontDesign(.rounded)` to the outermost container.

6. In `OnboardingView.swift`, add `.fontDesign(.rounded)` to the outermost container.

**IMPORTANT exceptions -- do NOT change these to rounded:**
- `.design: .monospaced` fonts in `CodeCardView.swift` and `ColorCardView.swift` (hex values, code) -- these MUST stay monospaced. Since `.fontDesign(.rounded)` propagates down, explicitly add `.fontDesign(.monospaced)` on those views if needed. But since they already use `.system(size:design:.monospaced)`, the explicit `design:` parameter should take precedence. Verify this.
- `FocusableTextField.swift` uses `NSFont.systemFont(ofSize: 13)` -- this is AppKit and not affected by SwiftUI fontDesign. Leave as-is.
- `ClipboardCardView.swift` line 246 uses `NSFont.systemFont(ofSize: 12)` for NSAttributedString -- AppKit, leave as-is.

For explicit `.font(.system(size: N))` calls that DON'T have a `design:` parameter and are NOT monospaced, update them to `.font(.system(size: N, design: .rounded))`. Key files:
- `PanelContentView.swift`: gear icon `.font(.system(size: 14))` -> `.font(.system(size: 14, design: .rounded))`
- `SearchFieldView.swift`: `.font(.system(size: 12))` calls -> `.font(.system(size: 12, design: .rounded))`
- `LabelChipView.swift`: `.font(.system(size: ...))` calls -> add `design: .rounded`
- `ClipboardCardView.swift`: `.font(.system(size: 18))` (language icon, line ~300) and `.font(.system(size: 10, weight: .medium, design: .rounded))` (badge, line ~379 -- already rounded, leave it)
- Files in Settings/: `PrivacySettingsView.swift`, `GeneralSettingsView.swift`, `LabelSettingsView.swift`, `AppPickerView.swift` -- explicit `.system(size:)` calls should get `design: .rounded`

Actually, `.fontDesign(.rounded)` as an environment value DOES override `.system(size:)` calls that don't specify a design. So the top-level `.fontDesign(.rounded)` should handle most cases. Only `.system(size:design:.monospaced)` with explicit design will be unaffected (which is correct). Verify by checking: does `.fontDesign(.rounded)` on a parent override `.font(.system(size: 14))` on a child? Yes, it does -- `.fontDesign` sets the environment and `.system(size:)` without explicit design picks it up. So the top-level modifier alone should work for most views. The explicit `.system(size:weight:design:)` calls with non-rounded design will keep their specified design.

**Minimal approach:** Add `.fontDesign(.rounded)` to 4-5 root views. Do NOT individually rewrite every `.font()` call. The environment cascades.

**Part B: Reduce header padding in horizontal (top/bottom) mode**

In `PanelContentView.swift`, the horizontal mode header is the `HStack` block (lines ~58-86). Currently it has:
```swift
.padding(.horizontal, 12)
.padding(.vertical, 4)
```

The `SearchFieldView` adds its own `.padding(.vertical, 4)` and the `ChipBarView` adds `.padding(.vertical, 6)`. The FilteredCardListView horizontal layout has `.padding(.vertical, 0)`.

To reduce the gap between header and cards in horizontal mode:
1. Change the horizontal HStack padding from `.padding(.vertical, 4)` to `.padding(.vertical, 2)` -- this tightens the header row.
2. In `SearchFieldView.swift`, reduce `.padding(.vertical, 8)` (inner padding) to `.padding(.vertical, 6)` and `.padding(.vertical, 4)` (outer) to `.padding(.vertical, 2)` -- this tightens the search field.
3. In `ChipBarView.swift`, reduce `.padding(.vertical, 6)` to `.padding(.vertical, 4)` -- tightens chip bar.

These padding reductions ONLY apply globally (they affect both vertical and horizontal modes). But since horizontal mode places everything in a single row, the cumulative effect is less vertical wasted space. For vertical mode, the header padding is on lines 109-110 (`.padding(.vertical, 10)`) -- leave this untouched.

Actually, since SearchFieldView and ChipBarView are shared between modes, be careful. The changes above affect both. If the user only wants horizontal mode tightened, we need conditional padding. But since the user said "reduce padding between header and card view" in top/bottom modes, and in vertical mode the components stack vertically with their own spacing anyway, a modest global tightening (2px per component) is acceptable and won't noticeably affect vertical mode.
  </action>
  <verify>Build succeeds. Open panel in top/bottom edge mode -- header row should be more compact with less gap before cards. All text should appear in rounded font. Code cards and color hex should remain monospaced.</verify>
  <done>Rounded font applied across all main views via `.fontDesign(.rounded)`. Header padding reduced in horizontal panel mode. Monospaced fonts preserved for code and hex values.</done>
</task>

</tasks>

<verification>
1. Build: `xcodebuild -scheme Pastel -configuration Debug build` succeeds
2. Key repeat: Open panel, hold right/left arrow -- cards iterate rapidly
3. Rounded font: All UI text uses SF Rounded (visible on letters like 'a', 'g', 's')
4. Monospaced preserved: Code cards and color hex values still use monospaced font
5. Horizontal padding: Switch to top/bottom edge, header-to-cards gap is reduced
6. Vertical mode: Left/right edge layout still looks correct (not over-compressed)
</verification>

<success_criteria>
- Arrow keys support key repeat for rapid card navigation
- App-wide rounded font design via `.fontDesign(.rounded)` on root views
- Reduced header padding in top/bottom panel edge modes
- No regressions in vertical panel mode or monospaced fonts
</success_criteria>

<output>
After completion, create `.planning/quick/21-enable-key-repeat-navigation-rounded-fon/21-SUMMARY.md`
</output>
