---
phase: quick-32
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/ChipBarView.swift
  - Pastel/Views/Settings/SettingsView.swift
  - Pastel/Views/Settings/SettingsWindowController.swift
autonomous: true
requirements: [QT-32]

must_haves:
  truths:
    - "Right-clicking a label chip in the panel chip bar shows a context menu with Delete, Edit, Reorder"
    - "Right-clicking a label chip in the History browser chip bar shows the same context menu"
    - "Delete removes the label from the database"
    - "Edit opens inline color/emoji palette for the label"
    - "Reorder opens the Settings window on the Labels tab"
  artifacts:
    - path: "Pastel/Views/Panel/ChipBarView.swift"
      provides: "Context menu on label chips with Delete, Edit, Reorder actions"
      contains: "contextMenu"
    - path: "Pastel/Views/Settings/SettingsView.swift"
      provides: "Public SettingsTab enum and selectedTab binding for external navigation"
      contains: "SettingsTab"
    - path: "Pastel/Views/Settings/SettingsWindowController.swift"
      provides: "showSettings with optional tab parameter for deep-linking"
      contains: "initialTab"
  key_links:
    - from: "Pastel/Views/Panel/ChipBarView.swift"
      to: "Pastel/Views/Settings/SettingsWindowController.swift"
      via: "Reorder menu item calls SettingsWindowController.shared.showSettings with labels tab"
      pattern: "showSettings.*labels"
---

<objective>
Add a right-click context menu to label chips in ChipBarView with three options: Delete (removes label), Edit (opens color/emoji palette inline), and Reorder (opens Settings on the Labels tab).

Purpose: Let users manage labels directly from the chip bar without navigating to Settings for every operation.
Output: Context menu on all label chips in both the panel and the History browser.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/ChipBarView.swift
@Pastel/Views/Panel/LabelChipView.swift
@Pastel/Views/Settings/SettingsView.swift
@Pastel/Views/Settings/SettingsWindowController.swift
@Pastel/Views/Settings/LabelSettingsView.swift
@Pastel/Models/Label.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Enable deep-linking to Settings Labels tab</name>
  <files>
    Pastel/Views/Settings/SettingsView.swift
    Pastel/Views/Settings/SettingsWindowController.swift
  </files>
  <action>
1. In `SettingsView.swift`, make `SettingsTab` non-private (change `private enum SettingsTab` to `enum SettingsTab`). This allows external code to reference the tab enum.

2. Add an `initialTab` parameter to `SettingsView`:
   - Change `SettingsView` init to accept `initialTab: SettingsTab = .general`
   - Change `@State private var selectedTab: SettingsTab = .general` to use the initialTab parameter: `@State private var selectedTab: SettingsTab`
   - Add init: `init(initialTab: SettingsTab = .general) { _selectedTab = State(initialValue: initialTab) }`

3. In `SettingsWindowController.swift`, update `showSettings` to accept an optional `initialTab` parameter:
   - Change signature to `func showSettings(modelContainer: ModelContainer, appState: AppState, initialTab: SettingsTab = .general)`
   - Pass `initialTab` to `SettingsView(initialTab: initialTab)` when creating the view
   - IMPORTANT: When window already exists and is visible, we still need to handle the tab navigation. Since SettingsView owns its state internally, for the "already visible" case, post a notification. Add a `static let switchTab = Notification.Name("SettingsWindowSwitchTab")` to SettingsWindowController. In the `if let window, window.isVisible` branch, post this notification with `userInfo: ["tab": initialTab.rawValue]`. In SettingsView, add `.onReceive(NotificationCenter.default.publisher(for: SettingsWindowController.switchTab))` that reads the tab rawValue from notification userInfo and updates `selectedTab`.
  </action>
  <verify>Project builds with `xcodebuild -scheme "Pastel AppStore" -configuration Debug build 2>&1 | tail -5` (or check for zero compile errors).</verify>
  <done>SettingsWindowController.showSettings accepts an initialTab parameter. Calling showSettings with .labels opens Settings directly on the Labels tab. Works both for new window creation and bringing existing window to front.</done>
</task>

<task type="auto">
  <name>Task 2: Add right-click context menu to label chips in ChipBarView</name>
  <files>Pastel/Views/Panel/ChipBarView.swift</files>
  <action>
1. In ChipBarView, add state for the edit palette sheet:
   - `@State private var editingLabel: Label?` (nil = no edit sheet)

2. In the `labelChip(for:)` function, add a `.contextMenu` modifier to the LabelChipView (AFTER the existing `.onTapGesture` and `.draggable` modifiers). The context menu has three items:

   ```swift
   .contextMenu {
       Button {
           editingLabel = label
       } label: {
           SwiftUI.Label("Edit", systemImage: "pencil")
       }

       Button {
           // Open Settings on Labels tab for reordering
           if let container = try? label.modelContext?.container {
               // Get appState from environment
               SettingsWindowController.shared.showSettings(
                   modelContainer: container,
                   appState: appState,
                   initialTab: .labels
               )
           }
       } label: {
           SwiftUI.Label("Reorder", systemImage: "arrow.up.arrow.down")
       }

       Divider()

       Button(role: .destructive) {
           deleteLabel(label)
       } label: {
           SwiftUI.Label("Delete", systemImage: "trash")
       }
   }
   ```

   Note: Use `SwiftUI.Label` (fully qualified) to avoid conflict with the data model `Label` type.

3. Add the `appState` environment to ChipBarView (it's not currently there):
   - Add `@Environment(AppState.self) private var appState`

4. For the Reorder action, getting the modelContainer is needed. The cleanest approach: access it via the modelContext environment that ChipBarView already has. Use `modelContext.container` to get the container. The Reorder button becomes:
   ```swift
   Button {
       SettingsWindowController.shared.showSettings(
           modelContainer: modelContext.container,
           appState: appState,
           initialTab: .labels
       )
   } label: {
       SwiftUI.Label("Reorder", systemImage: "arrow.up.arrow.down")
   }
   ```

5. Add a `deleteLabel` method to ChipBarView:
   ```swift
   private func deleteLabel(_ label: Label) {
       // Remove from any selected state
       selectedLabelIDs.remove(label.persistentModelID)
       modelContext.delete(label)
       saveWithLogging(modelContext, operation: "delete label from chip bar")
   }
   ```

6. Add a `.sheet(item: $editingLabel)` modifier on the outer container (the CenteredFlowLayout or its parent) that presents the edit palette. Reuse the same color/emoji palette pattern from LabelSettingsView's LabelRow. Create a private `labelEditPalette` view that shows:
   - Color grid (6-column, same as LabelRow/ChipBarView create popover)
   - Divider
   - Emoji grid (same curated emojis already defined in ChipBarView)
   - Label name text field for renaming
   - Done button to dismiss

   The sheet should look like:
   ```swift
   .sheet(item: $editingLabel) { label in
       LabelEditPalette(label: label, onDismiss: { editingLabel = nil })
   }
   ```

   Create `LabelEditPalette` as a private struct inside ChipBarView.swift:
   ```swift
   private struct LabelEditPalette: View {
       @Bindable var label: Label
       @Environment(\.modelContext) private var modelContext
       var onDismiss: () -> Void

       // Same curatedEmojis as elsewhere
       private static let curatedEmojis: [String] = [
           "📌", "📎", "📝", "📋", "📂", "💡",
           "⭐", "❤️", "🔥", "🎯", "🏷️", "🔖",
           "✅", "❌", "⚡", "🎨", "🔧", "🐛",
           "💬", "📧", "🔒", "🌟", "💎", "🚀"
       ]

       var body: some View {
           VStack(alignment: .leading, spacing: 10) {
               Text("Edit Label")
                   .font(.headline)

               TextField("Label name", text: $label.name)
                   .textFieldStyle(.roundedBorder)
                   .frame(width: 180)
                   .onSubmit {
                       saveWithLogging(modelContext, operation: "update label name")
                   }

               // 6x2 color grid
               let columns = Array(repeating: GridItem(.fixed(20), spacing: 6), count: 6)
               LazyVGrid(columns: columns, spacing: 6) {
                   ForEach(LabelColor.allCases, id: \.self) { labelColor in
                       Circle()
                           .fill(labelColor.color)
                           .frame(width: 20, height: 20)
                           .overlay(
                               Circle().strokeBorder(
                                   label.emoji == nil && label.colorName == labelColor.rawValue
                                       ? Color.white : Color.clear,
                                   lineWidth: 2
                               )
                           )
                           .onTapGesture {
                               label.colorName = labelColor.rawValue
                               label.emoji = nil
                               saveWithLogging(modelContext, operation: "update label color")
                           }
                   }
               }

               Divider()

               Text("Emoji")
                   .font(.caption)
                   .foregroundStyle(.secondary)

               LazyVGrid(columns: columns, spacing: 6) {
                   ForEach(Self.curatedEmojis, id: \.self) { emoji in
                       Text(emoji)
                           .font(.system(size: 16))
                           .frame(width: 20, height: 20)
                           .background(
                               RoundedRectangle(cornerRadius: 4)
                                   .fill(label.emoji == emoji ? Color.white.opacity(0.2) : Color.clear)
                           )
                           .onTapGesture {
                               label.emoji = emoji
                               saveWithLogging(modelContext, operation: "update label emoji")
                           }
                   }
               }

               HStack {
                   Spacer()
                   Button("Done") {
                       saveWithLogging(modelContext, operation: "update label")
                       onDismiss()
                   }
               }
           }
           .padding(12)
           .frame(width: 220)
       }
   }
   ```

   IMPORTANT: For `.sheet(item:)` to work, `Label` must conform to `Identifiable`. Check if it already does via `@Model` (SwiftData @Model provides `PersistentIdentifier` but may not provide Identifiable). If Label does not conform to Identifiable, instead use a Bool state `@State private var showingEditPalette = false` with the `editingLabel` stored separately, and use `.sheet(isPresented: $showingEditPalette)` pattern reading from `editingLabel`.

7. Verify that ChipBarView is used in both PanelContentView and HistoryBrowserView -- since both use ChipBarView, the context menu will automatically appear in both locations. HistoryBrowserView already injects `.environment(PanelActions())` and has modelContext, but check that AppState is available in the HistoryBrowserView context. HistoryBrowserView already has `@Environment(AppState.self) private var appState`, and it creates ChipBarView, so AppState will propagate via environment. Good.
  </action>
  <verify>
Build the project: `xcodebuild -scheme "Pastel AppStore" -configuration Debug build 2>&1 | tail -20` -- should compile with zero errors.
Then manually verify: right-click a label chip in the panel, see Delete/Edit/Reorder options.
  </verify>
  <done>
Right-clicking any label chip (in panel chip bar or History browser chip bar) shows a context menu with Edit (opens color/emoji/name palette), Reorder (opens Settings Labels tab), and Delete (removes the label). All three actions function correctly.
  </done>
</task>

</tasks>

<verification>
1. Build succeeds with zero errors for both schemes (Pastel AppStore, Pastel Sparkle)
2. Right-click a label chip in the panel -- context menu appears with Edit, Reorder, Delete
3. Right-click a label chip in Settings > History -- same context menu appears
4. Edit: opens palette sheet, can change name/color/emoji, changes persist
5. Reorder: opens Settings window on Labels tab (or switches to Labels tab if already open)
6. Delete: removes the label, chip disappears from chip bar
</verification>

<success_criteria>
- Context menu with Edit, Reorder, Delete appears on right-click of any label chip
- Works in both panel and History browser contexts
- Delete removes label from database
- Edit allows changing name, color, and emoji inline
- Reorder navigates to Settings Labels tab where drag-to-reorder is available
</success_criteria>

<output>
After completion, create `.planning/quick/32-add-right-click-context-menu-on-label-ch/32-SUMMARY.md`
</output>
