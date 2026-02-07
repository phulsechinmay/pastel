# Phase 10: Drag-and-Drop Label Assignment - Research

**Researched:** 2026-02-07
**Domain:** SwiftUI Drag and Drop (macOS 14+, NSPanel, SwiftData)
**Confidence:** HIGH

## Summary

This phase adds drag-and-drop label assignment: users drag a label chip from ChipBarView and drop it onto a ClipboardCardView to assign that label. This is entirely in-app, same-window interaction -- no cross-app or cross-process transfer is needed.

SwiftUI provides two API generations for drag and drop: the older `onDrag`/`onDrop` with `NSItemProvider`, and the modern `draggable`/`dropDestination` with `Transferable`. For this use case, the modern API with `String` as the transfer type is the simplest and most appropriate approach. Since `String` already conforms to `Transferable`, we can encode the label's `PersistentIdentifier` as a JSON string and use it as the drag payload -- no custom UTType, no Info.plist changes, no Transferable conformance on SwiftData models.

The main technical risks are: (1) gesture conflict between `.draggable` and `Button`'s implicit tap gesture on the chip bar, requiring a refactor from `Button` to a plain `View` with `.onTapGesture`; (2) ensuring the NSPanel's `.nonactivatingPanel` style mask doesn't interfere with drag-and-drop events (it should not, since drag-and-drop is handled by the view system not the window activation system); and (3) providing clear visual feedback on drop targets within the existing card design.

**Primary recommendation:** Use `.draggable(encodedLabelID)` on chip views and `.dropDestination(for: String.self)` on card views. Encode `PersistentIdentifier` via `JSONEncoder` to pass the label reference. This avoids all custom UTType/Transferable complexity.

## Standard Stack

### Core

| Library/API | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| SwiftUI `.draggable(_:)` | macOS 13+ | Make label chips draggable | Built-in, zero dependencies |
| SwiftUI `.dropDestination(for:action:isTargeted:)` | macOS 13+ | Accept drops on cards | Built-in, provides `isTargeted` for visual feedback |
| `Transferable` (String conformance) | macOS 13+ | Transfer data type | String already conforms; no custom work needed |
| `PersistentIdentifier` (Codable) | macOS 14+ | Encode label identity for transfer | Already Codable; JSON-encode to String |

### Supporting

| API | Purpose | When to Use |
|-----|---------|-------------|
| `JSONEncoder`/`JSONDecoder` | Encode PersistentIdentifier to/from String | On drag start / drop receive |
| `ModelContext.model(for:)` | Resolve PersistentIdentifier back to Label | On drop, to assign label to item |
| `.onTapGesture` | Replace Button for chips that need drag | When chip must be both tappable and draggable |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `String` transfer type | Custom `Transferable` struct | More type safety but requires custom UTType, Info.plist entry, and Transferable conformance -- overkill for same-window transfer |
| `.draggable`/`.dropDestination` | `onDrag`/`onDrop` with `NSItemProvider` | Older API, more boilerplate (NSItemProvider, async callbacks, DispatchQueue.main), no `isTargeted` convenience |
| Encoding `PersistentIdentifier` as JSON | Using label name as String | Fragile if labels can have duplicate names; PersistentIdentifier is unique |
| Drag-and-drop system | Shared `@State`-based approach with DragGesture | Would avoid system DnD entirely but loses native drag preview, cross-view barriers, and platform conventions |

**No additional packages needed.** Everything uses built-in SwiftUI and Foundation APIs.

## Architecture Patterns

### Modified View Hierarchy

```
PanelContentView
  |-- ChipBarView
  |     |-- ForEach(labels) { label in
  |     |     labelChip(for: label)
  |     |       .draggable(encodedLabelID)    // <-- NEW: make chip draggable
  |     |-- createChip (NOT draggable)
  |
  |-- FilteredCardListView
        |-- ForEach(items) { item in
              ClipboardCardView(item: item, ...)
                .dropDestination(for: String.self)  // <-- NEW: accept label drops
```

### Pattern 1: Encode PersistentIdentifier as String for Transfer

**What:** Encode the Label's `PersistentIdentifier` to a JSON `String` for `.draggable`, decode it in `.dropDestination` to resolve the Label.

**When to use:** Whenever transferring SwiftData model references within the same app.

**Why:** `PersistentIdentifier` conforms to `Codable` but NOT to `Transferable` (and SwiftData @Model objects are NOT `Sendable`, blocking direct `Transferable` conformance). Encoding to `String` sidesteps both issues.

**Example:**
```swift
// Encoding helper
extension PersistentIdentifier {
    var asTransferString: String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }

    static func fromTransferString(_ string: String) -> PersistentIdentifier? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }
}
```

### Pattern 2: Chip View Refactor (Button -> View + onTapGesture)

**What:** Replace `Button` with a plain styled `View` that uses `.onTapGesture` for selection and `.draggable` for drag support.

**When to use:** When a view needs to be both tappable AND draggable on macOS.

**Why:** On macOS, `.draggable` and `Button`'s implicit tap gesture conflict. When `.draggable` is added to a `Button`, tap handling breaks. The fix is to use a non-interactive container with `.onTapGesture` instead.

**Example:**
```swift
// BEFORE (current code -- Button prevents draggable from working)
Button {
    selectedLabel = isActive ? nil : label
} label: {
    chipContent(for: label, isActive: isActive)
}
.buttonStyle(.plain)

// AFTER (refactored -- onTapGesture + draggable coexist)
chipContent(for: label, isActive: isActive)
    .contentShape(Rectangle())  // ensure full hit area
    .onTapGesture {
        selectedLabel = isActive ? nil : label
    }
    .draggable(label.persistentModelID.asTransferString)
```

### Pattern 3: Drop Target with Visual Feedback

**What:** Use `.dropDestination`'s `isTargeted` callback to highlight cards during hover.

**When to use:** On every card that can receive a label drop.

**Example:**
```swift
// In FilteredCardListView, wrapping each ClipboardCardView:
@State private var dropTargetIndex: Int? = nil

ClipboardCardView(item: item, isSelected: selectedIndex == index, ...)
    .dropDestination(for: String.self) { strings, location in
        guard let encodedID = strings.first,
              let labelID = PersistentIdentifier.fromTransferString(encodedID),
              let label = try? modelContext.model(for: labelID) as? Label else {
            return false
        }
        item.label = label
        try? modelContext.save()
        return true
    } isTargeted: { targeted in
        dropTargetIndex = targeted ? index : nil
    }
```

### Pattern 4: Drag Preview Customization

**What:** Provide a custom drag preview that looks like the label chip itself.

**When to use:** To give visual continuity -- the dragged item looks like what was picked up.

**Example:**
```swift
chipContent(for: label, isActive: false)
    .draggable(label.persistentModelID.asTransferString) {
        // Custom drag preview matching chip appearance
        HStack(spacing: 4) {
            if let emoji = label.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 10))
            } else {
                Circle()
                    .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                    .frame(width: 8, height: 8)
            }
            Text(label.name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.3), in: Capsule())
    }
```

### Anti-Patterns to Avoid

- **Making SwiftData @Model conform to Transferable:** SwiftData models are not `Sendable`. Attempting to add `Transferable` conformance triggers Swift 6 concurrency errors. Transfer identifiers instead.
- **Using custom UTType for in-app-only transfer:** Registering exported UTTypes in Info.plist is unnecessary when `String.self` suffices for same-app communication.
- **Putting `.dropDestination` on the ScrollView:** Drop targets should be on individual cards so each card can provide independent `isTargeted` visual feedback. Putting it on the scroll view loses per-card targeting.
- **Using `onDrag`/`onDrop` instead of `draggable`/`dropDestination`:** The older API requires manual `NSItemProvider` management, async callbacks, and manual `DispatchQueue.main.async` for UI updates. The modern API handles all of this automatically.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Transferable String encoding | Custom pasteboard type registration | `String` (already Transferable) | No setup needed; works out of the box |
| PersistentIdentifier serialization | Custom string format (e.g., "label:UUID") | `JSONEncoder`/`JSONDecoder` with Codable conformance | PersistentIdentifier is already Codable; JSON round-trips perfectly |
| Drop target highlighting | Manual hit-testing with DragGesture | `.dropDestination`'s `isTargeted:` callback | Built-in, frame-accurate, no gesture conflicts |
| Drag preview | Custom overlay tracking mouse position | `.draggable`'s trailing closure preview | System-managed, native feel, correct Z-ordering |

**Key insight:** The entire drag-and-drop system is provided by SwiftUI's built-in modifiers. The only custom code needed is the PersistentIdentifier encoding/decoding helpers and the visual feedback styling.

## Common Pitfalls

### Pitfall 1: Button + .draggable Gesture Conflict
**What goes wrong:** Adding `.draggable` to a `Button` (or a view inside a `Button`) causes the tap gesture to stop working on macOS. The drag gesture consumes the mouse-down event before the button can register a click.
**Why it happens:** macOS gesture disambiguation prioritizes drag gestures over button taps when both are registered on the same responder.
**How to avoid:** Replace `Button` with a plain `View` + `.onTapGesture` + `.contentShape(Rectangle())` for the full hit area. Keep `.buttonStyle(.plain)` aesthetic by manually styling.
**Warning signs:** Chips become un-tappable after adding `.draggable`; only drag works.

### Pitfall 2: PersistentIdentifier is NOT Transferable
**What goes wrong:** Attempting to use `.draggable(label.persistentModelID)` directly fails because `PersistentIdentifier` does not conform to `Transferable`.
**Why it happens:** Apple did not add `Transferable` conformance to `PersistentIdentifier`, and `@Model` objects are not `Sendable` (blocking custom conformance).
**How to avoid:** Encode `PersistentIdentifier` to JSON String. Use `String.self` as the transfer type.
**Warning signs:** Compile error "Type PersistentIdentifier does not conform to Transferable".

### Pitfall 3: dropDestination on Wrong View Level
**What goes wrong:** Placing `.dropDestination` on the `ScrollView` or `LazyVStack` means you get one drop zone for the entire list, not per-card targeting. You lose the ability to highlight individual cards during hover.
**Why it happens:** `.dropDestination`'s `isTargeted` fires for the entire view it's attached to, not for subviews.
**How to avoid:** Attach `.dropDestination` to each individual `ClipboardCardView` wrapper.
**Warning signs:** All cards highlight simultaneously, or no per-card feedback is visible.

### Pitfall 4: String Payload Collision
**What goes wrong:** If other drag sources in the app also use `String.self` (e.g., text content), the drop handler might receive unexpected data that's not a valid PersistentIdentifier.
**Why it happens:** `dropDestination(for: String.self)` accepts ANY string drop, not just label IDs.
**How to avoid:** Validate the dropped string with `PersistentIdentifier.fromTransferString()` and verify the resolved model is actually a `Label`. Return `false` from the action closure if validation fails. Optionally, prefix the encoded string with a known sentinel (e.g., `"label:"`) for fast rejection.
**Warning signs:** Drops from other apps or text selections trigger label assignment.

### Pitfall 5: NSPanel Focus Behavior During Drag
**What goes wrong:** The `.nonactivatingPanel` style might interfere with drag session lifecycle since the panel intentionally avoids becoming main window.
**Why it happens:** Drag sessions on macOS involve the window system's event loop. Non-standard window types can sometimes miss events.
**How to avoid:** The panel already has `canBecomeKey: true`, which should be sufficient for receiving drag events. SwiftUI's drag-and-drop is handled at the view layer, not the window activation layer. Test early and fall back to `onDrop` with `DropDelegate` if the modern API has issues in NSPanel.
**Warning signs:** Drag preview appears but drop never registers; `isTargeted` never fires.

### Pitfall 6: Modifier Order Matters
**What goes wrong:** If `.dropDestination` is placed before `.onTapGesture` or after `.clipShape`, it may not receive events correctly.
**Why it happens:** SwiftUI modifier order determines the event handling chain and the effective frame for hit testing.
**How to avoid:** Place `.dropDestination` after all visual modifiers (background, overlay, clipShape) but before or alongside gesture modifiers. The drop destination needs to match the visible card frame.
**Warning signs:** Drop only works on part of the card, or not at all.

## Code Examples

### Complete Chip Drag Source (ChipBarView modification)

```swift
// Source: Synthesized from verified API patterns
// Replaces the existing labelChip(for:) method in ChipBarView

@ViewBuilder
private func labelChip(for label: Label) -> some View {
    let isActive = selectedLabel?.persistentModelID == label.persistentModelID

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
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
        isActive
            ? Color.accentColor.opacity(0.3)
            : Color.white.opacity(0.1),
        in: Capsule()
    )
    .overlay(
        Capsule()
            .strokeBorder(
                isActive ? Color.accentColor.opacity(0.6) : Color.clear,
                lineWidth: 1
            )
    )
    .contentShape(Capsule())
    .onTapGesture {
        if isActive {
            selectedLabel = nil
        } else {
            selectedLabel = label
        }
    }
    .draggable(label.persistentModelID.asTransferString) {
        // Drag preview: mini chip
        HStack(spacing: 4) {
            if let emoji = label.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 10))
            } else {
                Circle()
                    .fill(LabelColor(rawValue: label.colorName)?.color ?? .gray)
                    .frame(width: 8, height: 8)
            }
            Text(label.name)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.4), in: Capsule())
    }
}
```

### Complete Drop Target (FilteredCardListView modification)

```swift
// Source: Synthesized from verified API patterns
// Wrapping each ClipboardCardView in the ForEach

ClipboardCardView(
    item: item,
    isSelected: selectedIndex == index,
    badgePosition: badge,
    isDropTarget: dropTargetIndex == index  // NEW: pass drop targeting state
)
.id(index)
.dropDestination(for: String.self) { strings, location in
    guard let encodedID = strings.first,
          let labelID = PersistentIdentifier.fromTransferString(encodedID),
          let label = modelContext.model(for: labelID) as? Label else {
        return false
    }
    item.label = label
    try? modelContext.save()
    return true
} isTargeted: { targeted in
    withAnimation(.easeInOut(duration: 0.15)) {
        dropTargetIndex = targeted ? index : nil
    }
}
```

### PersistentIdentifier Extension

```swift
// Source: Based on PersistentIdentifier Codable conformance (Apple docs)
import SwiftData
import Foundation

extension PersistentIdentifier {
    /// Encode this identifier as a JSON string for drag-and-drop transfer.
    var asTransferString: String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)!
    }

    /// Decode a PersistentIdentifier from a JSON string produced by `asTransferString`.
    static func fromTransferString(_ string: String) -> PersistentIdentifier? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }
}
```

### Drop Target Visual Feedback (ClipboardCardView modification)

```swift
// NEW property on ClipboardCardView
var isDropTarget: Bool = false

// Modified cardBorderColor computed property
private var cardBorderColor: Color {
    if isDropTarget {
        return Color.accentColor  // Bright accent border during drag hover
    } else if isSelected {
        return Color.accentColor.opacity(0.5)
    } else if isColorCard {
        return Color.white.opacity(0.15)
    }
    return Color.clear
}

// Modified cardBackground to include drop target state
private var cardBackground: AnyShapeStyle {
    if isColorCard {
        return AnyShapeStyle(colorFromHex(item.detectedColorHex))
    } else if isDropTarget {
        return AnyShapeStyle(Color.accentColor.opacity(0.15))  // Subtle highlight
    } else if isSelected {
        return AnyShapeStyle(Color.accentColor.opacity(0.3))
    } else if isHovered {
        return AnyShapeStyle(Color.white.opacity(0.12))
    } else {
        return AnyShapeStyle(Color.white.opacity(0.06))
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `onDrag`/`onDrop` + `NSItemProvider` | `.draggable`/`.dropDestination` + `Transferable` | macOS 13 (2022) | Dramatically simpler API; `isTargeted` built-in |
| Custom `DropDelegate` protocol | `.dropDestination` closure API | macOS 13 (2022) | No delegate class needed for simple cases |
| Manual `registerForDraggedTypes` on NSView | SwiftUI view modifiers | macOS 11 (2020) | No AppKit bridging needed |

**Deprecated/outdated:**
- `onDrop(of:isTargeted:perform:)` with `[UTType]` array: Still works but `.dropDestination(for:)` is the modern replacement with type-safe generics.
- `NSItemProvider`-based encoding: Still works but `Transferable` protocol handles encoding automatically for conforming types.

## Open Questions

1. **NSPanel + `.dropDestination` interaction**
   - What we know: The panel uses `.nonactivatingPanel` + `canBecomeKey: true`. SwiftUI drag-and-drop operates at the view layer via `NSDraggingDestination` protocol on the underlying `NSView`. The panel should receive drag events because it can become key.
   - What's unclear: Whether `.dropDestination` works perfectly in a non-activating NSPanel. No authoritative source confirms or denies this specifically.
   - Recommendation: Implement with `.dropDestination` first. If it fails, fall back to `onDrop(of:delegate:)` with a custom `DropDelegate`. If that also fails, use AppKit's `registerForDraggedTypes` on the `NSHostingView`.
   - **Confidence: MEDIUM** -- likely works, but needs testing.

2. **Drag preview rendering in NSPanel**
   - What we know: Some macOS versions have bugs where drag previews are corrupted or missing (noted in eclecticlight.co article).
   - What's unclear: Whether this affects the current macOS 14+ target specifically.
   - Recommendation: Provide a custom drag preview (trailing closure in `.draggable`) rather than relying on the automatic snapshot. If preview is still broken, it's cosmetic only -- the drag-and-drop functionality still works.
   - **Confidence: MEDIUM** -- custom preview should mitigate.

3. **String payload disambiguation**
   - What we know: `dropDestination(for: String.self)` accepts any string from any drag source.
   - What's unclear: Whether text dragged from other apps could accidentally trigger label assignment on the panel.
   - Recommendation: Validate the dropped string by attempting JSON decode to `PersistentIdentifier`. If decode fails, return `false`. The panel is non-activating and floating, so cross-app drops are unlikely but possible.
   - **Confidence: HIGH** -- validation logic handles this cleanly.

## Sources

### Primary (HIGH confidence)
- SwiftUI `.draggable()` and `.dropDestination()` API -- verified via [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-support-drag-and-drop-in-swiftui) and [Codecademy reference](https://www.codecademy.com/resources/docs/swiftui/viewmodifier/dropDestination)
- `PersistentIdentifier` is `Codable` -- verified via [Apple Developer Forums](https://developer.apple.com/forums/thread/735534) and [Swift Forums](https://forums.swift.org/t/swiftdata-transferable/82299)
- String conforms to `Transferable` out of the box -- verified via multiple sources
- SwiftData @Model is NOT `Sendable` (blocking direct Transferable conformance) -- verified via [Swift Forums](https://forums.swift.org/t/swiftdata-transferable/82299)

### Secondary (MEDIUM confidence)
- Button + .draggable gesture conflict on macOS -- verified via [Hacking with Swift Forums](https://www.hackingwithswift.com/forums/swiftui/how-to-use-both-draggable-and-ontapgesture/26285)
- macOS drag preview bugs -- reported by [Eclectic Light Company](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/)
- `.dropDestination`'s `isTargeted:` closure for visual feedback -- verified via [SerialCoder.dev](https://serialcoder.dev/text-tutorials/swiftui/first-experience-with-transferable-implementing-drag-and-drop-in-swiftui/) and [CreateWithSwift](https://www.createwithswift.com/implementing-drag-and-drop-with-the-swiftui-modifiers/)

### Tertiary (LOW confidence)
- NSPanel + drag-and-drop compatibility -- no authoritative source found; inference only

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all APIs are built-in SwiftUI/Foundation with well-documented behavior
- Architecture: HIGH -- patterns derived from multiple verified sources and existing codebase structure
- Pitfalls: HIGH -- gesture conflict and Transferable/Sendable issues confirmed by developer forums
- NSPanel compatibility: MEDIUM -- no specific documentation found; needs runtime validation

**Research date:** 2026-02-07
**Valid until:** 2026-03-07 (stable APIs, unlikely to change)
