---
phase: quick
plan: 005
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/ClipboardCardView.swift
autonomous: true

must_haves:
  truths:
    - "Cards with an assigned label show a small chip (emoji-or-dot + name) below content preview"
    - "Cards without a label show no chip (no empty space or placeholder)"
    - "Context menu Label submenu shows emoji+name as a single concatenated string for emoji labels"
  artifacts:
    - path: "Pastel/Views/Panel/ClipboardCardView.swift"
      provides: "Label chip on card + fixed context menu label rendering"
      contains: "labelChip"
  key_links:
    - from: "ClipboardCardView.body"
      to: "item.label"
      via: "optional binding to show/hide chip"
      pattern: "if let label = item\\.label"
---

<objective>
Add label indicator chips to clipboard cards and fix context menu label display.

Purpose: Labels assigned to clipboard items are invisible on the card itself -- users only discover assignments via the context menu checkmark. Showing a small chip on the card makes label assignment instantly visible during scanning. Additionally, macOS context menus have limited SwiftUI HStack layout support, so emoji labels in the Label submenu should use a single concatenated Text for reliable rendering.

Output: Modified ClipboardCardView.swift with (1) an inline label chip below contentPreview, (2) a single-Text label rendering in the context menu.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/ClipboardCardView.swift
@Pastel/Views/Panel/ChipBarView.swift (reference for chip styling pattern)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add label chip to card and fix context menu label text</name>
  <files>Pastel/Views/Panel/ClipboardCardView.swift</files>
  <action>
Two changes in ClipboardCardView.swift:

**Change 1 -- Label chip on card:**

In the `body` VStack (currently: header HStack, then contentPreview), add an optional label chip AFTER `contentPreview`. Use `if let label = item.label` to conditionally render.

Chip design (mirroring ChipBarView.labelChip pattern at smaller scale):
- HStack(spacing: 3) containing:
  - If `label.emoji` is non-nil and non-empty: `Text(emoji).font(.system(size: 9))`
  - Else: `Circle().fill(LabelColor color).frame(width: 6, height: 6)`
  - `Text(label.name).font(.caption2).lineLimit(1).foregroundStyle(.secondary)`
- Padding: `.padding(.horizontal, 6).padding(.vertical, 2)`
- Background: `Color.white.opacity(0.1)` in `Capsule()`
- No interaction (it is display-only, not a button)

This goes right after `contentPreview` inside the existing VStack. The VStack already has `spacing: 6` which will naturally separate the chip from the content above.

**Change 2 -- Context menu label text:**

In the `.contextMenu` Label submenu, replace the current `HStack` inside each Button's `label:` closure. The issue is that macOS NSMenu-backed context menus do not reliably render SwiftUI HStack layouts -- the emoji Text and name Text may not both appear.

Replace the current label: closure content (lines 73-86) with:

```swift
HStack {
    Text(labelDisplayText(label))
    if item.label?.persistentModelID == label.persistentModelID {
        Spacer()
        Image(systemName: "checkmark")
    }
}
```

Add a private helper method:

```swift
private func labelDisplayText(_ label: Label) -> String {
    if let emoji = label.emoji, !emoji.isEmpty {
        return "\(emoji) \(label.name)"
    } else {
        return label.name
    }
}
```

Note: This drops the color dot Circle for non-emoji labels in the context menu. Context menus render Text reliably but shapes (Circle) are unreliable. The name alone is sufficient identification in the menu since the chip bar and card chip already show the color dot. This is a pragmatic tradeoff for macOS context menu compatibility.
  </action>
  <verify>
Build the project with Cmd+B (or `xcodebuild build` from CLI). Verify:
1. No compiler errors
2. Run the app, add a label to a clipboard item, confirm the chip appears on the card
3. Right-click a card, open Label submenu, confirm emoji labels show "emoji name" format
  </verify>
  <done>
Cards with assigned labels display a small capsule chip (emoji-or-dot + name) below the content preview. Cards without labels show nothing extra. Context menu Label submenu items display emoji+name as a single string for emoji labels, and just the name for color-dot labels. Checkmark still appears for the currently assigned label.
  </done>
</task>

</tasks>

<verification>
- Build succeeds with no warnings in ClipboardCardView.swift
- Visual: card with label shows chip; card without label shows no chip
- Visual: context menu Label submenu shows combined emoji+name text
- Chip styling is consistent with ChipBarView (capsule, muted background, caption2 font)
</verification>

<success_criteria>
- Label assignment is visible directly on clipboard cards without opening the context menu
- Context menu label items render reliably with emoji and name together
- No layout regressions (card heights, spacing, hover/selection states unaffected)
</success_criteria>

<output>
After completion, create `.planning/quick/005-card-label-chips-and-emoji-menu-fix/005-SUMMARY.md`
</output>
