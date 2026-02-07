---
phase: quick
plan: 002
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Models/PasteBehavior.swift
  - Pastel/Services/PasteService.swift
  - Pastel/Views/Settings/GeneralSettingsView.swift
autonomous: true

must_haves:
  truths:
    - "Double-clicking a clipboard item with 'Paste' mode writes to pasteboard AND simulates Cmd+V"
    - "Double-clicking with 'Copy' mode writes to pasteboard only (no Cmd+V), still hides panel"
    - "Double-clicking with 'Copy + Paste' mode writes to pasteboard AND simulates Cmd+V"
    - "Settings General tab has a Paste Behavior dropdown with all 3 options"
    - "Default behavior is Paste (not Copy)"
  artifacts:
    - path: "Pastel/Models/PasteBehavior.swift"
      provides: "PasteBehavior enum with .paste, .copy, .copyAndPaste cases"
      contains: "enum PasteBehavior"
    - path: "Pastel/Services/PasteService.swift"
      provides: "Branching logic based on PasteBehavior setting"
      contains: "pasteBehavior"
    - path: "Pastel/Views/Settings/GeneralSettingsView.swift"
      provides: "Picker for paste behavior setting"
      contains: "pasteBehavior"
  key_links:
    - from: "Pastel/Services/PasteService.swift"
      to: "@AppStorage(\"pasteBehavior\")"
      via: "UserDefaults read at paste time"
      pattern: "UserDefaults.*pasteBehavior"
    - from: "Pastel/Views/Settings/GeneralSettingsView.swift"
      to: "@AppStorage(\"pasteBehavior\")"
      via: "Picker binding"
      pattern: "AppStorage.*pasteBehavior"
---

<objective>
Add a paste behavior setting with 3 modes: Paste (write to pasteboard + Cmd+V), Copy (write to pasteboard only), and Copy + Paste (same as Paste). Default to Paste. Surface the setting as a dropdown in the Settings window's General tab.

Purpose: The current behavior only copies to pasteboard. Users need control over whether the app also simulates Cmd+V to paste into the frontmost app.
Output: PasteBehavior enum, updated PasteService with branching logic, new Picker in GeneralSettingsView.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Models/PanelEdge.swift (pattern reference: String rawValue enum)
@Pastel/Services/PasteService.swift (modify: add behavior branching)
@Pastel/Views/Settings/GeneralSettingsView.swift (modify: add Picker)
@Pastel/App/AppState.swift (reference: paste call chain)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create PasteBehavior enum and update PasteService</name>
  <files>
    Pastel/Models/PasteBehavior.swift
    Pastel/Services/PasteService.swift
  </files>
  <action>
    1. Create `Pastel/Models/PasteBehavior.swift` following the exact pattern from PanelEdge.swift:

    ```swift
    /// Defines what happens when the user activates a clipboard item (double-click or Enter).
    ///
    /// Persisted via `@AppStorage("pasteBehavior")`.
    enum PasteBehavior: String, CaseIterable {
        /// Write to pasteboard and simulate Cmd+V to paste into frontmost app.
        case paste = "paste"
        /// Write to pasteboard only. User must manually Cmd+V.
        case copy = "copy"
        /// Write to pasteboard and simulate Cmd+V (same as .paste).
        case copyAndPaste = "copyAndPaste"

        /// Human-readable label for display in settings UI.
        var displayName: String {
            switch self {
            case .paste: return "Paste"
            case .copy: return "Copy to Clipboard"
            case .copyAndPaste: return "Copy + Paste"
            }
        }
    }
    ```

    2. Update `PasteService.paste()` to read the behavior setting and branch:

    - At the top of the `paste()` method, AFTER the secure input check but BEFORE step 3, read the user's preference:
      ```swift
      let behaviorRaw = UserDefaults.standard.string(forKey: "pasteBehavior") ?? PasteBehavior.paste.rawValue
      let behavior = PasteBehavior(rawValue: behaviorRaw) ?? .paste
      ```

    - Use UserDefaults.standard directly (NOT @AppStorage) because PasteService is not a SwiftUI view. This is the correct pattern for non-view classes.

    - For `.copy` behavior: after writing to pasteboard and setting skipNextChange, hide the panel and return early (skip the Cmd+V simulation). Do NOT check accessibility permission for copy-only mode since CGEvent is not needed.

    - Restructure the method flow:
      a. Read behavior setting first
      b. For `.copy`: skip accessibility check, write to pasteboard, set skipNextChange, hide panel, return
      c. For `.paste` and `.copyAndPaste`: keep existing full flow (accessibility check, secure input check, write pasteboard, skipNextChange, hide panel, simulate Cmd+V)

    - Important: The accessibility guard and secure input check should only apply to `.paste` and `.copyAndPaste` modes. Copy-only mode does not need accessibility permission.

    3. Add the new file to the Xcode project. Run: `grep -c "PasteBehavior" Pastel.xcodeproj/project.pbxproj` -- if 0, the file needs to be added. Since the project uses a modern Xcode structure with folder references, verify whether new files in the Models folder are auto-discovered or need manual pbxproj entry by checking if other model files (like PanelEdge.swift) have explicit entries.
  </action>
  <verify>
    - `swift -typecheck Pastel/Models/PasteBehavior.swift` or build the project with `xcodebuild -scheme Pastel -configuration Debug build 2>&1 | tail -5` to confirm no compile errors.
    - `grep "pasteBehavior" Pastel/Services/PasteService.swift` shows the setting is read.
    - `grep "\.copy" Pastel/Services/PasteService.swift` shows branching logic exists.
  </verify>
  <done>
    PasteBehavior enum exists with 3 cases (.paste, .copy, .copyAndPaste) and String raw values.
    PasteService reads "pasteBehavior" from UserDefaults and branches: .copy skips accessibility check and Cmd+V simulation; .paste and .copyAndPaste use full paste flow.
    Project compiles without errors.
  </done>
</task>

<task type="auto">
  <name>Task 2: Add Paste Behavior picker to GeneralSettingsView</name>
  <files>
    Pastel/Views/Settings/GeneralSettingsView.swift
  </files>
  <action>
    1. Add an @AppStorage property at the top of GeneralSettingsView (alongside the existing ones):
    ```swift
    @AppStorage("pasteBehavior") private var pasteBehaviorRaw: String = PasteBehavior.paste.rawValue
    ```
    Note: Use the SAME pattern as panelEdgeRaw -- store the raw String, not the enum directly.

    2. Add a new section as item #5 (after History Retention, before Spacer). Insert a Divider() after the History Retention section, then add:
    ```swift
    // 5. Paste behavior
    VStack(alignment: .leading, spacing: 6) {
        Text("Paste Behavior")
            .font(.headline)
        Picker("When activating an item:", selection: $pasteBehaviorRaw) {
            ForEach(PasteBehavior.allCases, id: \.rawValue) { behavior in
                Text(behavior.displayName).tag(behavior.rawValue)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 200)

        Text("\"Paste\" writes to clipboard and pastes into the active app.\n\"Copy to Clipboard\" only writes to clipboard.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    ```

    3. Update the doc comment at the top of the struct to mention the 5th setting (Paste behavior).
  </action>
  <verify>
    - Build the project: `xcodebuild -scheme Pastel -configuration Debug build 2>&1 | tail -10` confirms no errors.
    - `grep -c "pasteBehavior" Pastel/Views/Settings/GeneralSettingsView.swift` returns at least 2 (AppStorage + Picker binding).
    - `grep "Paste Behavior" Pastel/Views/Settings/GeneralSettingsView.swift` shows the section header exists.
  </verify>
  <done>
    GeneralSettingsView has a "Paste Behavior" dropdown section with 3 options (Paste, Copy to Clipboard, Copy + Paste).
    Default selection is "Paste" (.paste).
    Dropdown follows the same visual pattern as the existing History Retention picker (headline label, .menu style, 200pt max width).
    Helper text explains the difference between modes.
  </done>
</task>

</tasks>

<verification>
1. Build succeeds: `xcodebuild -scheme Pastel -configuration Debug build`
2. New enum file exists: `ls Pastel/Models/PasteBehavior.swift`
3. PasteService branches on behavior: `grep -A5 "pasteBehavior" Pastel/Services/PasteService.swift`
4. Settings UI has picker: `grep "Paste Behavior" Pastel/Views/Settings/GeneralSettingsView.swift`
5. Default is paste: `grep "PasteBehavior.paste.rawValue" Pastel/Views/Settings/GeneralSettingsView.swift`
</verification>

<success_criteria>
- PasteBehavior enum exists with .paste, .copy, .copyAndPaste cases and String rawValues
- PasteService reads "pasteBehavior" from UserDefaults and skips Cmd+V simulation for .copy mode
- Copy-only mode does NOT require accessibility permission
- GeneralSettingsView has a Paste Behavior dropdown defaulting to "Paste"
- Project compiles and runs
</success_criteria>

<output>
After completion, create `.planning/quick/002-add-paste-behavior-setting/002-SUMMARY.md`
</output>
