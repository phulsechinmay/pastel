# Phase 6: Data Model and Label Enhancements - Research

**Researched:** 2026-02-06
**Domain:** SwiftData schema evolution, SwiftUI color palette, emoji input (macOS)
**Confidence:** HIGH

## Summary

Phase 6 extends the existing SwiftData schema with new optional fields needed by all v1.1 phases, then ships label enhancements (expanded 12-color palette, optional emoji on labels). This is the foundation phase -- every subsequent phase (7, 8, 9) depends on the model fields added here.

The research covers three domains: (1) SwiftData lightweight migration behavior when adding optional properties and new enum raw values, (2) SwiftUI color availability for the four new LabelColor cases, and (3) emoji input/validation patterns on macOS. All three domains are well-understood with established patterns.

**Primary recommendation:** Add all new SwiftData properties as `Optional` with `nil` defaults -- this guarantees automatic lightweight migration. Store ContentType as raw String (already done) so new enum cases are purely additive. Use `NSApp.orderFrontCharacterPalette(nil)` for system emoji picker access.

## Standard Stack

### Core

No new dependencies are needed for Phase 6. Everything uses existing frameworks.

| Library/Framework | Version | Purpose | Why Standard |
|-------------------|---------|---------|--------------|
| SwiftData | macOS 14+ | Model persistence and migration | Already in use; lightweight migration handles optional field additions automatically |
| SwiftUI | macOS 14+ | Color constants (.teal, .indigo, .brown, .mint) | Built-in system colors available since macOS 10.15+ |
| AppKit | macOS 14+ | NSApp.orderFrontCharacterPalette for emoji picker | Only reliable API for invoking system emoji picker on macOS |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation | macOS 14+ | String/Character emoji detection | Validating single-emoji input in TextField |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| System emoji picker (Ctrl+Cmd+Space) | Third-party emoji picker library (MCEmojiPicker) | Unnecessary dependency; system picker is standard on macOS and well-integrated |
| TextField for emoji input | Custom emoji grid view | Over-engineered; a single-character TextField + system picker button is simpler and more accessible |
| VersionedSchema migration | Automatic lightweight migration | VersionedSchema is unnecessary when all new fields are optional with nil defaults |

## Architecture Patterns

### Recommended Project Structure

No new files needed for Plan 06-01 (schema migration). Plan 06-02 adds no new files either -- it modifies existing views.

```
Pastel/Models/
  ClipboardItem.swift      # ADD: 6 new optional fields (detectedLanguage, detectedColorHex, urlTitle, urlFaviconPath, urlPreviewImagePath, urlMetadataFetched)
  Label.swift              # ADD: emoji: String? field
  LabelColor.swift         # ADD: 4 new enum cases (teal, indigo, brown, mint)
  ContentType.swift        # ADD: 2 new enum cases (.code, .color)

Pastel/Views/Panel/
  ChipBarView.swift        # MODIFY: emoji-or-dot rendering in label chips
  ClipboardCardView.swift  # MODIFY: emoji-or-dot in context menu label submenu

Pastel/Views/Settings/
  LabelSettingsView.swift  # MODIFY: emoji input field, emoji picker button, expanded color palette in LabelRow
```

### Pattern 1: SwiftData Lightweight Migration via Optional Fields

**What:** Add new stored properties to @Model classes as Optional types with nil defaults. SwiftData automatically performs a lightweight migration -- no VersionedSchema, no SchemaMigrationPlan, no manual migration code.

**When to use:** Every time you add a new field to an existing model in a shipped app.

**How it works:** SwiftData detects that the new schema has additional columns compared to the on-disk store. Because the new columns are nullable (Optional) with a nil default, it adds them via ALTER TABLE ADD COLUMN -- the simplest SQLite migration possible. Existing rows get NULL for the new columns.

**Example:**
```swift
// BEFORE (v1.0)
@Model
final class ClipboardItem {
    var textContent: String?
    var contentType: String
    // ... existing fields
}

// AFTER (v1.1) -- just add optional properties
@Model
final class ClipboardItem {
    var textContent: String?
    var contentType: String
    // ... existing fields unchanged

    // NEW optional fields -- nil default, lightweight migration
    var detectedLanguage: String?
    var detectedColorHex: String?
    var urlTitle: String?
    var urlFaviconPath: String?
    var urlPreviewImagePath: String?
    var urlMetadataFetched: Bool?
}
```

**Critical rule:** New fields MUST be Optional (or have an explicit default value). Non-optional fields without defaults require a complex migration with VersionedSchema.

### Pattern 2: Additive Enum Cases with Raw String Storage

**What:** The existing ContentType enum is stored as a raw String in ClipboardItem.contentType. Adding new cases (.code, .color) is safe because existing rows contain old raw values that still decode correctly, and the new raw values are only written for new items.

**When to use:** When adding new classification categories to an enum that is stored via rawValue.

**Key insight:** The Pastel codebase already uses the safe pattern -- ContentType is NOT stored as a Codable enum directly. Instead, ClipboardItem stores `contentType: String` (the raw value) and provides a computed `type` property:

```swift
// Already in ClipboardItem.swift -- this pattern is migration-safe
var type: ContentType {
    get { ContentType(rawValue: contentType) ?? .text }
    set { contentType = newValue.rawValue }
}
```

The `?? .text` fallback means that if a hypothetical future enum case is removed, old data still loads as `.text`. And new cases are just new String values in the column -- no schema change needed.

**What would break:** Changing the rawValue type (e.g., Int to String) or renaming existing raw values. Neither applies here.

### Pattern 3: Emoji-or-Dot Conditional Rendering

**What:** When a label has an emoji set, show the emoji character instead of the color dot. When emoji is nil or empty, fall back to the color dot.

**When to use:** In ChipBarView label chips, in ClipboardCardView context menu, and in LabelSettingsView rows.

**Example:**
```swift
// Reusable pattern for emoji-or-dot
@ViewBuilder
func labelIndicator(for label: Label) -> some View {
    if let emoji = label.emoji, !emoji.isEmpty {
        Text(emoji)
            .font(.system(size: 10))
    } else {
        Circle()
            .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
            .frame(width: 8, height: 8)
    }
}
```

### Pattern 4: System Emoji Picker Invocation

**What:** Call `NSApp.orderFrontCharacterPalette(nil)` to open the macOS system emoji and symbols picker. The selected emoji is inserted into whichever text field has first responder status.

**When to use:** When the user clicks an emoji button next to the emoji TextField in LabelSettingsView.

**Example:**
```swift
Button {
    // Ensure the emoji text field has focus first
    NSApp.orderFrontCharacterPalette(nil)
} label: {
    Image(systemName: "face.smiling")
}
```

**Important:** The system emoji picker inserts the selected character into the current first responder (the focused TextField). The emoji TextField must be focused before calling orderFrontCharacterPalette. Alternatively, the user can press Ctrl+Cmd+Space while the TextField is focused -- this is the standard macOS shortcut for the emoji picker.

### Anti-Patterns to Avoid

- **Non-optional new fields on @Model:** Adding a non-optional property without a default to an existing @Model class will crash on launch with a migration failure. Every new field must be `String?`, `Bool?`, `Int?`, etc.

- **Storing enums via Codable instead of rawValue:** SwiftData encodes Codable enums as binary data, making them hard to query with #Predicate and fragile across schema changes. The existing rawValue String pattern in ClipboardItem is correct -- do not change it.

- **Using VersionedSchema for simple additions:** VersionedSchema and SchemaMigrationPlan are needed for complex migrations (renaming, type changes, data transforms). For adding optional fields, they add unnecessary boilerplate. Skip them.

- **Filtering by new ContentType cases in existing @Query predicates:** The existing FilteredCardListView predicates do not filter by contentType -- they filter by label and text search. Adding new ContentType cases does not break any existing query. But if someone adds a contentType filter later, they must handle all cases.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Emoji picker UI | Custom emoji grid/palette view | `NSApp.orderFrontCharacterPalette(nil)` + standard TextField | System picker has all emojis, skin tones, search, recents -- impossible to replicate well |
| Schema migration | Manual VersionedSchema/MigrationPlan | Automatic lightweight migration (optional fields) | SwiftData handles ALTER TABLE ADD COLUMN automatically for nullable fields |
| Emoji validation | Complex Unicode parsing library | Simple `String.count == 1` check after trimming | A single grapheme cluster check is sufficient for the "one emoji" constraint |
| Color constants | Custom hex-to-Color mapping for new palette colors | SwiftUI built-in `.teal`, `.indigo`, `.brown`, `.mint` | System colors adapt to dark/light mode and accessibility settings |

**Key insight:** Phase 6 is entirely achievable with zero new dependencies and minimal new code. The architecture is already set up for exactly these kinds of additions.

## Common Pitfalls

### Pitfall 1: SwiftData Migration Failure on Launch

**What goes wrong:** App crashes on first launch after update because a new non-optional field was added to an @Model class without a default value.
**Why it happens:** SwiftData attempts a lightweight migration but cannot add a NOT NULL column without a default to an existing table with data.
**How to avoid:** Every single new field must be `Optional` (or provide an explicit default value in the property declaration). Use `var field: String?` not `var field: String`.
**Warning signs:** EXC_BREAKPOINT or "failed to create persistent store" crash on launch after updating the model.

### Pitfall 2: LabelColor Enum Backward Compatibility

**What goes wrong:** Existing labels with old color names (e.g., "blue") fail to render after LabelColor enum changes.
**Why it happens:** If enum cases are reordered or raw values changed, `LabelColor(rawValue:)` returns nil for existing data.
**How to avoid:** Only ADD new cases to LabelColor. Do not reorder, rename, or remove existing cases. The existing 8 cases must keep their exact raw value strings. New cases (teal, indigo, brown, mint) are appended.
**Warning signs:** Labels rendering with gray fallback color when they should show their assigned color.

### Pitfall 3: ContentType Switch Exhaustiveness

**What goes wrong:** Compiler errors across multiple files when new ContentType cases are added.
**Why it happens:** Swift requires exhaustive switch statements. Adding `.code` and `.color` cases will break every `switch item.type` in the codebase.
**How to avoid:** When adding new cases, immediately update ALL switch statements:
- `ClipboardCardView.contentPreview` -- route to existing TextCardView for now (actual card views come in Phase 7)
- `PasteService.writeToPasteboard()` -- handle .code and .color the same as .text (they have textContent)
- `ClipboardMonitor.processPasteboardContent()` -- add cases to the switch (detection logic comes in Phase 7)
- `NSPasteboard+Reading.classifyContent()` -- no change needed (returns existing types; detection is separate)
**Warning signs:** Build errors in every file that switches on ContentType.

### Pitfall 4: Emoji TextField Allowing Multiple Characters

**What goes wrong:** User pastes a long string into the emoji field, or types multiple emoji, breaking chip layout.
**Why it happens:** A plain TextField has no character limit. The system emoji picker inserts one emoji at a time, but paste or keyboard input can insert more.
**How to avoid:** Use `.onChange(of:)` to truncate the emoji field to a single grapheme cluster:
```swift
TextField("", text: $emojiBinding)
    .onChange(of: emojiBinding) { _, newValue in
        if newValue.count > 1 {
            emojiBinding = String(newValue.prefix(1))
        }
    }
```
**Warning signs:** Label chips stretching to accommodate multi-character emoji strings.

### Pitfall 5: NSApp.orderFrontCharacterPalette Not Inserting into TextField

**What goes wrong:** User clicks the emoji picker button but the selected emoji does not appear in the TextField.
**Why it happens:** The button click steals focus from the TextField. The system emoji picker inserts into whatever view has first responder status -- if the TextField lost focus, the emoji goes nowhere.
**How to avoid:** Two approaches: (1) Make the button non-focusable so clicking it does not steal focus from the TextField, or (2) add a hint label telling users to press Ctrl+Cmd+Space while the TextField is focused. The Ctrl+Cmd+Space approach is actually more reliable.
**Warning signs:** Clicking emoji button opens picker but nothing happens when user selects an emoji.

### Pitfall 6: urlMetadataFetched Type Choice

**What goes wrong:** Using `Bool` (non-optional) for urlMetadataFetched requires a default value and may not clearly distinguish "not yet fetched" from "fetched with no results."
**Why it happens:** Bool defaults to false, which could mean either "we haven't tried" or "we tried and got nothing."
**How to avoid:** Use `Bool?` where nil = "not yet fetched", false = "fetch attempted, failed", true = "fetch succeeded." This three-state flag is important for Phase 8's URL metadata service to avoid redundant fetches.
**Warning signs:** URL items being re-fetched every time the app launches because the "already fetched" state was lost.

## Code Examples

### Example 1: Updated ClipboardItem Model (v1.1)

```swift
// Source: Direct analysis of existing ClipboardItem.swift + research synthesis
@Model
final class ClipboardItem {
    // --- Existing v1.0 fields (unchanged) ---
    var textContent: String?
    var htmlContent: String?
    var rtfData: Data?
    var contentType: String
    var timestamp: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var characterCount: Int
    var byteCount: Int
    var changeCount: Int
    var imagePath: String?
    var thumbnailPath: String?
    var isConcealed: Bool
    var expiresAt: Date?
    @Attribute(.unique) var contentHash: String
    var label: Label?

    // --- New v1.1 fields (all optional, nil default) ---

    /// Detected programming language (e.g., "swift", "python"). Nil = not code.
    /// Set by CodeDetectionService in Phase 7.
    var detectedLanguage: String?

    /// Detected color as 6-digit hex (no #). Nil = not a color value.
    /// Set by ColorDetectionService in Phase 7.
    var detectedColorHex: String?

    /// Page title fetched from URL metadata. Nil = not fetched or not a URL.
    /// Set by URLMetadataService in Phase 8.
    var urlTitle: String?

    /// Filename of cached favicon image on disk. Nil = not fetched.
    /// Set by URLMetadataService in Phase 8.
    var urlFaviconPath: String?

    /// Filename of cached og:image preview on disk. Nil = not fetched.
    /// Set by URLMetadataService in Phase 8.
    var urlPreviewImagePath: String?

    /// Whether URL metadata has been fetched. nil = not attempted, false = failed, true = succeeded.
    /// Set by URLMetadataService in Phase 8.
    var urlMetadataFetched: Bool?

    // --- Computed property (unchanged) ---
    var type: ContentType {
        get { ContentType(rawValue: contentType) ?? .text }
        set { contentType = newValue.rawValue }
    }

    // init updated to include new fields with nil defaults...
}
```

### Example 2: Updated Label Model (v1.1)

```swift
// Source: Direct analysis of existing Label.swift
@Model
final class Label {
    var name: String
    var colorName: String
    var sortOrder: Int

    /// Optional emoji that replaces the color dot when set.
    /// Single emoji character (one grapheme cluster) or nil.
    var emoji: String?

    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.label)
    var items: [ClipboardItem]

    init(name: String, colorName: String, sortOrder: Int, emoji: String? = nil) {
        self.name = name
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.emoji = emoji
        self.items = []
    }
}
```

### Example 3: Expanded LabelColor Enum

```swift
// Source: Direct analysis of existing LabelColor.swift + SwiftUI color docs
enum LabelColor: String, CaseIterable {
    // Existing 8 colors (unchanged, same order)
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case gray

    // New 4 colors (appended -- order matters for palette grid layout)
    case teal
    case indigo
    case brown
    case mint

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        case .teal: .teal
        case .indigo: .indigo
        case .brown: .brown
        case .mint: .mint
        }
    }
}
```

### Example 4: Updated ContentType Enum

```swift
// Source: Direct analysis of existing ContentType.swift + research synthesis
enum ContentType: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case url
    case image
    case file

    // New v1.1 cases (detection logic added in Phase 7)
    case code
    case color
}
```

### Example 5: Emoji Input Field in LabelRow

```swift
// Source: Research synthesis -- emoji TextField with system picker button
// In LabelRow within LabelSettingsView:

// Emoji binding that truncates to single character
private var emojiBinding: Binding<String> {
    Binding(
        get: { label.emoji ?? "" },
        set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            label.emoji = trimmed.isEmpty ? nil : String(trimmed.prefix(1))
            try? modelContext.save()
        }
    )
}

// In the HStack:
HStack(spacing: 4) {
    TextField("", text: emojiBinding)
        .textFieldStyle(.plain)
        .frame(width: 28)
        .multilineTextAlignment(.center)

    Button {
        NSApp.orderFrontCharacterPalette(nil)
    } label: {
        Image(systemName: "face.smiling")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .help("Open emoji picker (or press Ctrl+Cmd+Space)")
}
```

### Example 6: Emoji-or-Dot in ChipBarView

```swift
// Source: Direct analysis of existing ChipBarView.swift
// Replace the Circle() in labelChip(for:) with conditional rendering:

HStack(spacing: 4) {
    if let emoji = label.emoji, !emoji.isEmpty {
        Text(emoji)
            .font(.system(size: 10))
    } else {
        Circle()
            .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
            .frame(width: 8, height: 8)
    }

    Text(label.name)
        .font(.caption)
        .lineLimit(1)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| VersionedSchema for all migrations | Automatic lightweight migration for optional field additions | SwiftData initial release (WWDC23) | No migration code needed when adding optional fields |
| Custom color picker views | SwiftUI built-in `.teal`, `.indigo`, `.brown`, `.mint` | iOS 15 / macOS 12 (Xcode 13) | System colors available directly, no hex mapping needed |
| Custom emoji picker views (iOS pattern) | `NSApp.orderFrontCharacterPalette` (macOS) | Always available on macOS | Native system UI, zero custom code |

**Deprecated/outdated:**
- Custom VersionedSchema for simple field additions: unnecessary overhead for nullable columns
- NSColorPanel for preset color selection: LabelColor enum with SwiftUI Color is simpler for a fixed palette

## Open Questions

1. **Color palette grid layout with 12 colors**
   - What we know: The current ChipBarView create-label popover and LabelSettingsView color menu show all LabelColor.allCases in a single HStack/menu. With 12 colors, the HStack may be too wide.
   - What's unclear: Whether to use a 2-row grid (6x2) or keep a single scrolling row, or wrap in a LazyVGrid.
   - Recommendation: Use a 2-row layout (6 per row) in the create-label popover. The LabelSettingsView color menu (dropdown) handles any number of items natively.

2. **Emoji clear mechanism**
   - What we know: Users need a way to remove an assigned emoji and revert to the color dot.
   - What's unclear: Whether to use a small "x" button next to the emoji field or allow clearing by deleting the character in the TextField.
   - Recommendation: Both -- clearing the TextField reverts to nil (handled by the binding), and optionally show a clear button when emoji is set.

## Sources

### Primary (HIGH confidence)
- Pastel v1.0 source code -- all model files, view files, and service files read directly
- ClipboardItem.swift -- confirmed contentType stored as raw String with computed `type` property
- LabelColor.swift -- confirmed 8-case enum with String rawValue
- Label.swift -- confirmed 3 fields (name, colorName, sortOrder) with no emoji field
- ContentType.swift -- confirmed 5-case enum with String rawValue

### Secondary (MEDIUM confidence)
- [Hacking with Swift - Lightweight vs Complex Migrations](https://www.hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations) -- confirmed lightweight migration handles optional field additions automatically
- [Donny Wals - SwiftData Migrations](https://www.donnywals.com/a-deep-dive-into-swiftdata-migrations/) -- confirmed optional properties qualify for automatic migration
- [Fat Bob Man - Codable and Enums in SwiftData](https://fatbobman.com/en/posts/considerations-for-using-codable-and-enums-in-swiftdata-models/) -- confirmed rawValue String storage is safer than Codable for enum evolution
- [Apple Developer Docs - Color](https://developer.apple.com/documentation/SwiftUI/Color) -- confirmed .teal, .indigo, .brown, .mint available macOS 10.15+
- [Apple Developer Forums - Emoji Picker](https://developer.apple.com/forums/thread/744367) -- confirmed NSApp.orderFrontCharacterPalette API for macOS emoji picker
- [Apple Developer Docs - isEmojiPresentation](https://developer.apple.com/documentation/swift/unicode/scalar/properties-swift.struct/isemoji) -- confirmed emoji detection via Unicode scalar properties

### Tertiary (LOW confidence)
- None -- all findings verified against primary or secondary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all frameworks already in use or built into macOS 14+
- Architecture: HIGH -- based on direct analysis of all relevant source files in the codebase
- Pitfalls: HIGH -- migration pitfalls are well-documented; enum/emoji pitfalls verified against codebase patterns
- Code examples: HIGH -- derived from direct modification of existing source files

**Research date:** 2026-02-06
**Valid until:** 2026-03-06 (stable domain -- SwiftData migration behavior and SwiftUI colors are not changing)
