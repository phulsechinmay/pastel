---
phase: quick-27
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Services/ColorFormatService.swift
  - Pastel/Views/Panel/ClipboardCardView.swift
autonomous: true
must_haves:
  truths:
    - "Right-clicking a color item shows a 'Copy Color As' submenu"
    - "User can copy color as Hex, RGB, HSL, or CMYK format"
    - "Copy Original Color option appears when original text differs from current hex"
    - "Non-color items do not show the color copy submenu"
  artifacts:
    - path: "Pastel/Services/ColorFormatService.swift"
      provides: "Hex-to-format conversion functions"
    - path: "Pastel/Views/Panel/ClipboardCardView.swift"
      provides: "Context menu with Copy Color As submenu"
  key_links:
    - from: "ClipboardCardView.swift"
      to: "ColorFormatService.swift"
      via: "static method calls"
      pattern: "ColorFormatService\\."
---

<objective>
Add color format copy options (Hex, RGB, HSL, CMYK) to the right-click context menu for color items, plus a "Copy Original Color" option when the original text differs from the stored hex.

Purpose: Let users quickly copy a detected color in their preferred format without manual conversion.
Output: ColorFormatService utility + updated context menu in ClipboardCardView.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Services/ColorDetectionService.swift
@Pastel/Views/Panel/ClipboardCardView.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create ColorFormatService with hex-to-format conversions</name>
  <files>Pastel/Services/ColorFormatService.swift</files>
  <action>
Create `Pastel/Services/ColorFormatService.swift` with a struct that converts a 6-digit uppercase hex string (no # prefix, e.g. "FF5733") to various color format strings:

1. `static func toHex(_ hex: String) -> String` — returns "#FF5733" (prepend #, keep uppercase)

2. `static func toRGB(_ hex: String) -> String` — parse hex to R,G,B integers (0-255), return "rgb(255, 87, 51)"

3. `static func toHSL(_ hex: String) -> String` — convert RGB to HSL using standard algorithm:
   - Normalize R,G,B to 0-1
   - L = (max + min) / 2
   - S = delta / (1 - abs(2L - 1)) if delta > 0, else 0
   - H from standard hue calculation based on which channel is max
   - Return "hsl(11, 100%, 60%)" with H as Int (0-360), S and L as Int percentages (0-100), all rounded

4. `static func toCMYK(_ hex: String) -> String` — convert RGB to CMYK:
   - K = 1 - max(R', G', B') where R'=R/255 etc.
   - If K == 1, all C/M/Y = 0
   - C = (1 - R' - K) / (1 - K), same for M, Y
   - Return "cmyk(0%, 66%, 80%, 0%)" with all values as Int percentages, rounded

Helper: `private static func hexToRGB(_ hex: String) -> (r: Int, g: Int, b: Int)?` — parse 6-char hex string to RGB tuple. Return nil if invalid.

Import only Foundation. Follow the same struct pattern as ColorDetectionService (no class, all static methods).
  </action>
  <verify>Build succeeds: `xcodebuild -project Pastel.xcodeproj -scheme Pastel build 2>&1 | tail -5` shows BUILD SUCCEEDED. Spot-check: ColorFormatService.toRGB("FF5733") would return "rgb(255, 87, 51)".</verify>
  <done>ColorFormatService exists with toHex, toRGB, toHSL, toCMYK static methods that accept 6-digit hex and return formatted strings.</done>
</task>

<task type="auto">
  <name>Task 2: Add "Copy Color As" submenu to context menu</name>
  <files>Pastel/Views/Panel/ClipboardCardView.swift</files>
  <action>
In ClipboardCardView.swift, add a "Copy Color As" submenu to the `.contextMenu` block. Insert it after the "Paste as Plain Text" button and before the first Divider (line 175).

The submenu should only appear when `item.detectedColorHex != nil`. Use `if let colorHex = item.detectedColorHex { ... }` inside the context menu builder.

Structure:

```swift
if let colorHex = item.detectedColorHex {
    Divider()
    Menu("Copy Color As") {
        Button("Hex — \(ColorFormatService.toHex(colorHex))") {
            copyToClipboard(ColorFormatService.toHex(colorHex))
        }
        Button("RGB — \(ColorFormatService.toRGB(colorHex))") {
            copyToClipboard(ColorFormatService.toRGB(colorHex))
        }
        Button("HSL — \(ColorFormatService.toHSL(colorHex))") {
            copyToClipboard(ColorFormatService.toHSL(colorHex))
        }
        Button("CMYK — \(ColorFormatService.toCMYK(colorHex))") {
            copyToClipboard(ColorFormatService.toCMYK(colorHex))
        }

        // Show "Copy Original Color" only when the original textContent
        // differs from the current hex (case-insensitive, ignoring # prefix)
        let currentHexVariants = ["#" + colorHex, colorHex, "#" + colorHex.lowercased(), colorHex.lowercased()]
        if let text = item.textContent,
           !currentHexVariants.contains(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            Divider()
            Button("Copy Original — \(item.textContent ?? "")") {
                if let original = item.textContent {
                    copyToClipboard(original)
                }
            }
        }
    }
}
```

Add a private helper method to ClipboardCardView (in the Actions MARK section):

```swift
private func copyToClipboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}
```

This uses NSPasteboard directly (same pattern as ColorToolController.swift line 51) rather than going through panelActions.copyOnlyItem, because we are copying a formatted string, not the item's original content.

Note: The "Copy Original" comparison should account for the fact that the user may have originally copied "rgb(255, 87, 51)" which got stored as hex "FF5733". The original textContent could be in any format, so just check it is not equal to the current hex (with/without #, upper/lower).
  </action>
  <verify>Build succeeds: `xcodebuild -project Pastel.xcodeproj -scheme Pastel build 2>&1 | tail -5` shows BUILD SUCCEEDED. Right-click a color item in the panel and verify "Copy Color As" submenu appears with Hex, RGB, HSL, CMYK options showing previews.</verify>
  <done>Color items show "Copy Color As" submenu with all four format options and conditional "Copy Original" option. Non-color items do not show the submenu. Selecting an option copies the formatted string to clipboard.</done>
</task>

</tasks>

<verification>
1. Build: `xcodebuild -project Pastel.xcodeproj -scheme Pastel build` succeeds
2. Right-click a color item: "Copy Color As" submenu visible with Hex, RGB, HSL, CMYK
3. Right-click a non-color item: no "Copy Color As" submenu
4. Each format option copies correct string to clipboard
5. "Copy Original" appears only when original text differs from current hex
</verification>

<success_criteria>
- ColorFormatService converts hex to all four formats correctly
- Context menu shows submenu only for color items
- Copy actions place formatted string on system clipboard
- Build compiles without warnings related to new code
</success_criteria>

<output>
After completion, create `.planning/quick/27-add-color-format-copy-options-to-right-c/27-SUMMARY.md`
</output>
