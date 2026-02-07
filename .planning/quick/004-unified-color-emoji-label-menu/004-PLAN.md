---
phase: quick
plan: 004
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Settings/LabelSettingsView.swift
autonomous: true

must_haves:
  truths:
    - "Each label row shows a single menu button (color dot or emoji) instead of separate color menu + emoji TextField + smiley button"
    - "Tapping a color circle in the popover sets that color AND clears any emoji"
    - "Tapping the emoji button in the popover opens the system emoji picker and the chosen emoji displays as the menu button"
    - "The 12 colors render in a 6x2 grid inside a popover, matching ChipBarView's palette style"
  artifacts:
    - path: "Pastel/Views/Settings/LabelSettingsView.swift"
      provides: "Unified color+emoji palette popover in LabelRow"
  key_links:
    - from: "LabelRow unified button"
      to: "label.colorName / label.emoji"
      via: "popover color tap sets colorName + clears emoji; emoji picker sets emoji"
---

<objective>
Replace the separate color dot Menu and emoji TextField+smiley button in LabelRow with a single unified palette popover. The button shows the label's emoji (if set) or color dot (otherwise). The popover contains a 6x2 LazyVGrid of color circles plus an emoji row/button. Selecting a color clears the emoji; the emoji button opens the system character palette.

Purpose: Cleaner, more compact label editing UX -- one control instead of three.
Output: Updated LabelSettingsView.swift with unified palette popover.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Settings/LabelSettingsView.swift
@Pastel/Views/Panel/ChipBarView.swift (reference for 6x2 LazyVGrid color palette)
@Pastel/Models/LabelColor.swift (12 color cases)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Replace separate color menu and emoji controls with unified palette popover</name>
  <files>Pastel/Views/Settings/LabelSettingsView.swift</files>
  <action>
In LabelRow, remove these three UI elements:
1. The `Menu { ForEach(LabelColor.allCases...) } label: { ... }` color dot dropdown (lines ~102-127)
2. The `HStack(spacing: 2)` containing the emoji TextField and smiley Button (lines ~130-150)
3. The `@FocusState private var isEmojiFieldFocused: Bool` property (no longer needed)

Keep the `emojiBinding` computed property -- it will be reused.

Replace them with a single Button + popover pattern:

```swift
@State private var showingPalette = false

// In body, as the first element of the outer HStack(spacing: 12):
Button {
    showingPalette.toggle()
} label: {
    if let emoji = label.emoji, !emoji.isEmpty {
        Text(emoji)
            .font(.system(size: 14))
    } else {
        Circle()
            .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
            .frame(width: 14, height: 14)
    }
}
.buttonStyle(.plain)
.popover(isPresented: $showingPalette, arrowEdge: .trailing) {
    colorEmojiPalette
}
```

Add a computed property `colorEmojiPalette` to LabelRow:

```swift
private var colorEmojiPalette: some View {
    VStack(alignment: .leading, spacing: 8) {
        // 6x2 color grid (same layout as ChipBarView)
        let columns = Array(repeating: GridItem(.fixed(20), spacing: 6), count: 6)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(LabelColor.allCases, id: \.self) { labelColor in
                Circle()
                    .fill(labelColor.color)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                label.colorName == labelColor.rawValue
                                    ? Color.white : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .onTapGesture {
                        label.colorName = labelColor.rawValue
                        label.emoji = nil   // color selection clears emoji
                        try? modelContext.save()
                        showingPalette = false
                    }
            }
        }

        Divider()

        // Emoji row
        HStack(spacing: 6) {
            Text("Emoji")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            TextField("", text: emojiBinding)
                .textFieldStyle(.plain)
                .frame(width: 24)
                .multilineTextAlignment(.center)
            Button {
                // Open system emoji picker targeting the TextField
                // We need a small delay to let focus settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.orderFrontCharacterPalette(nil)
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open emoji picker")
        }
    }
    .padding(10)
    .frame(width: 160)
}
```

Key behaviors:
- Color tap: sets colorName, clears emoji to nil, saves, dismisses popover
- Emoji TextField: user types/pastes emoji directly (emojiBinding truncates to 1 char)
- Smiley button: opens system character palette so user can pick emoji from OS picker
- The popover does NOT auto-dismiss on emoji selection (user may want to browse); color selection does dismiss since it is a single-tap action
- Current color is highlighted with a white border stroke (matching ChipBarView pattern)
  </action>
  <verify>
Build the project with Cmd+B (or `xcodebuild build`). Open Settings > Labels tab. Verify:
1. Each label row shows only one button before the name (dot or emoji), no separate TextField/smiley
2. Clicking the button opens a popover with 12 color circles in a 6x2 grid
3. Below the grid there is an "Emoji" row with a small text field and smiley button
4. Tapping a color changes the dot color and dismisses the popover
5. Setting an emoji shows the emoji as the button instead of the dot
6. Setting a color after an emoji clears the emoji
  </verify>
  <done>
LabelRow shows a single unified palette button. The popover contains a 6x2 color grid and an emoji row. Color selection clears emoji and dismisses. Emoji picker opens via smiley button. The button dynamically shows emoji or color dot based on current state.
  </done>
</task>

</tasks>

<verification>
- Build succeeds with zero errors
- Label rows show single palette button (no separate emoji controls)
- Color palette popover renders 12 colors in 6x2 grid
- Emoji row in popover allows emoji input and opens system picker
- Color selection clears emoji; emoji display overrides color dot
</verification>

<success_criteria>
- The separate color Menu, emoji TextField, and smiley Button are fully removed from LabelRow
- A single Button + popover replaces them with a unified color + emoji palette
- All 12 LabelColor cases are selectable in the palette grid
- Emoji can be set via text input or system character palette
- Setting a color clears any existing emoji (color takes precedence when newly selected)
- The palette button dynamically shows emoji (if set) or color dot (if no emoji)
</success_criteria>

<output>
After completion, create `.planning/quick/004-unified-color-emoji-label-menu/004-SUMMARY.md`
</output>
