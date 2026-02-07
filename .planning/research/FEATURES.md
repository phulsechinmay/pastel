# Feature Research: v1.1 Rich Content & Enhanced Paste

**Domain:** macOS Clipboard Manager (enrichment layer)
**Project:** Pastel
**Researched:** 2026-02-06
**Confidence:** MEDIUM-HIGH (based on training data through May 2025; WebSearch/WebFetch unavailable for live verification. Apple framework APIs and established patterns are HIGH confidence; third-party library specifics are MEDIUM.)

> **Scope:** This document covers only the v1.1 features. For v1.0 feature landscape, see git history of this file. Five feature areas are investigated: code snippet detection + syntax highlighting, URL preview cards, color value detection + swatches, Cmd+1-9 direct paste hotkeys, and label emoji + expanded color palette.

---

## 1. Code Snippet Detection + Syntax Highlighting

### How It Works in Clipboard Managers

**Detection approach:** Code detection is a heuristic classification problem. No clipboard manager uses a formal parser. The standard approach is regex-based pattern matching against common code indicators:

| Signal | Weight | Examples |
|--------|--------|---------|
| Leading indentation with braces/semicolons | HIGH | `function foo() {`, `if (x) {`, `for i in range:` |
| Language keywords at line start | HIGH | `import`, `func`, `def`, `class`, `const`, `let`, `var`, `return`, `public`, `private` |
| Common syntax characters | MEDIUM | `=>`, `->`, `::`, `//`, `/*`, `*/`, `#include`, `@property` |
| Multi-line content with consistent indentation | MEDIUM | 3+ lines with 2/4-space or tab indent |
| Source app is a code editor | HIGH | Bundle IDs: `com.microsoft.VSCode`, `com.sublimetext.*`, `com.apple.dt.Xcode`, `com.jetbrains.*`, `com.googlecode.iterm2` |
| Contains only ASCII printable + common whitespace | LOW | Code rarely has emoji or special Unicode |

**Expected behavior in PastePal/Paste:** When a clipboard item is detected as code, the card preview switches from plain body text to a monospaced, syntax-highlighted view. The detection runs at capture time (not at render time), and the content type is stored in the model so rendering is fast on scroll.

**Syntax highlighting approach:** Two options exist:

1. **Highlightr library** (MEDIUM confidence -- verify current maintenance status)
   - Swift wrapper around highlight.js (JavaScript-based)
   - Supports 190+ languages and 90+ themes
   - Auto-language detection via highlight.js heuristics
   - Returns NSAttributedString suitable for rendering
   - Concern: Bundles a JavaScriptCore engine. Size and performance implications for a lightweight app.
   - macOS support: YES (AppKit NSAttributedString output)
   - SwiftUI integration: Requires wrapping NSTextView or using AttributedString conversion

2. **Custom regex-based highlighting** (HIGH confidence -- no dependencies)
   - Implement a minimal highlighter for the top 5-8 languages
   - Much simpler: keyword coloring, string literal coloring, comment coloring
   - Fast (no JS engine), small footprint
   - Covers 80% of visual value with 20% of complexity
   - Languages to cover: Swift, Python, JavaScript/TypeScript, JSON, HTML/CSS, SQL, Shell/Bash, Go/Rust

**Recommendation: Start with Highlightr for auto-detection + rich highlighting. Fall back to the custom approach only if Highlightr proves too heavy or unmaintained.** Highlightr's auto-detection is the key value -- manually detecting language from a code snippet is hard to get right. A dark theme like "atom-one-dark" or "monokai" will blend naturally with Pastel's always-dark UI.

**Where detection happens:** At capture time in `ClipboardMonitor.processPasteboardContent()`. After content is classified as `.text`, run a secondary classification: "is this code?" If yes, set `contentType` to a new `.code` value. Store the detected language as metadata on the model. Rendering reads the stored type and language, applies highlighting via Highlightr or custom logic.

**Model changes needed:**
- Add `.code` case to `ContentType` enum
- Add `detectedLanguage: String?` field to `ClipboardItem`
- Card dispatcher routes `.code` to a new `CodeCardView`

### Table Stakes for Code Highlighting

| Requirement | Why Expected | Complexity | Notes |
|-------------|--------------|------------|-------|
| Monospaced font for code cards | Code must look like code; proportional font destroys readability | LOW | `.system(.callout, design: .monospaced)` |
| At least keyword + string + comment coloring | Three-color minimum makes code recognizable at a glance | MEDIUM | Even basic regex covers this |
| Auto-detection (user should not have to label items as code) | The entire value is automatic; manual tagging is not workflow-compatible | HIGH | Highlightr auto-detect or source-app heuristic |
| Dark theme highlighting | Must not clash with always-dark UI; light-background themes would look broken | LOW | Use a dark highlight.js theme |
| Text stays selectable/copyable | Users paste code, so the underlying text must remain intact | LOW | Highlighting is presentation only; pasteback uses original textContent |

### Differentiators for Code Highlighting

| Feature | Value | Complexity | Notes |
|---------|-------|------------|-------|
| Language badge on card | Small pill showing "Swift", "Python", etc. | LOW | Display `detectedLanguage` when available |
| Line numbers in preview | Helps identify code structure | MEDIUM | Adds visual noise in a small card; consider only for expanded view |
| Copy as code block (with backticks) | Paste into Slack/Discord with formatting | LOW | Transform on paste: wrap in triple backticks |

### Anti-Features for Code Highlighting

| Anti-Feature | Why Avoid | Alternative |
|--------------|-----------|-------------|
| Full syntax tree parsing (TreeSitter, etc.) | Massive dependency for marginal visual improvement over regex; overkill for card previews | Highlightr's JS-based highlighting is sufficient |
| User-selectable language per item | Adds UI complexity for rare correction; auto-detect is good enough for 90%+ of cases | Trust auto-detection; users who care will paste code elsewhere |
| Editable code in the card | Clipboard manager is not a code editor | Read-only preview |
| Code execution / REPL | Completely different product | Do not build |

---

## 2. URL Preview Cards (Open Graph Metadata)

### How It Works in Clipboard Managers

**The standard:** When a URL is copied, the clipboard manager fetches the page's Open Graph metadata (title, description, og:image, favicon) and displays a rich preview card instead of a bare URL string.

**Expected card anatomy:**

```
+-------------------------------+
| [favicon] Page Title          |
| example.com                   |
| +---------------------------+ |
| |     [og:image header]     | |
| +---------------------------+ |
+-------------------------------+
```

**Fetch flow (established pattern):**

1. URL is captured by ClipboardMonitor
2. Async metadata fetch fires immediately (non-blocking)
3. Card renders immediately with URL-only fallback (globe icon + URL text, like current URLCardView)
4. When metadata arrives, card updates to show title, favicon, og:image
5. Metadata is cached in the model so subsequent renders are instant
6. On fetch failure: card stays in fallback state permanently (no retry)

**What to fetch:**

| Metadata | Source | Priority | Fallback |
|----------|--------|----------|----------|
| Page title | `<title>` tag or `og:title` meta | MUST | Domain name (e.g., "github.com") |
| Favicon | `<link rel="icon">` or `/favicon.ico` | SHOULD | Globe SF Symbol (current behavior) |
| Header image | `og:image` meta tag | NICE | No image shown |
| Domain name | Extracted from URL | MUST | Raw URL |

**How to fetch (native, no external dependencies):**

```swift
// URLSession for HTML fetching
let (data, _) = try await URLSession.shared.data(from: url)
let html = String(data: data, encoding: .utf8)

// Parse <meta property="og:title" content="...">
// Parse <meta property="og:image" content="...">
// Parse <link rel="icon" href="...">
// Simple regex or string scanning -- no need for a full HTML parser
```

**Favicon fetching patterns:**
1. **Google Favicon API** (simplest): `https://www.google.com/s2/favicons?domain=example.com&sz=32` -- single HTTP call, returns 32px PNG. Reliable but requires network access and depends on Google.
2. **Direct /favicon.ico**: Fetch `https://example.com/favicon.ico`. Works for ~70% of sites.
3. **Parse HTML**: Find `<link rel="icon" ...>` and fetch that URL. Most reliable but requires two fetches.
4. **Apple's favicon via WebKit**: Use a WKWebView to load the page. Heavy, not recommended for a clipboard manager.

**Recommendation: Use a lightweight HTML parser approach.** Fetch the page HTML once, extract og:title, og:image, and favicon link from meta/link tags using regex, then fetch the favicon image. Cache aggressively. If the page does not respond within 3-5 seconds, fall back to URL-only card. This avoids external service dependencies and is the pattern PastePal uses.

**Model changes needed:**
- Add `urlTitle: String?` to ClipboardItem
- Add `urlFaviconPath: String?` (stored on disk like thumbnails)
- Add `urlImagePath: String?` (og:image, stored on disk)
- Add `urlDomain: String?` (extracted from URL, for display)
- Add `urlMetadataFetched: Bool` (flag to avoid re-fetching on failure)

**Network considerations (critical for this app):**
- App is not sandboxed, so URLSession works without entitlements
- Fetching must be non-blocking: async/await with structured concurrency
- Respect timeouts: 5 second max per URL fetch
- Rate limit: max 2-3 concurrent fetches to avoid overwhelming the system
- Do NOT fetch for private/internal URLs (192.168.x.x, localhost, etc.)
- Do NOT fetch for URLs from password managers (isConcealed)
- User should be able to disable URL fetching in settings

### Table Stakes for URL Previews

| Requirement | Why Expected | Complexity | Notes |
|-------------|--------------|------------|-------|
| Show page title instead of raw URL | The raw URL is meaningless for most pages; title gives context | MEDIUM | Requires HTML fetch + parse |
| Show domain name | Tells user which site the URL is from | LOW | `URL(string:)?.host` extraction |
| Graceful fallback on failure | Network may be down; page may not have OG tags | LOW | Current URLCardView is the fallback |
| Non-blocking fetch | Must not freeze UI or slow clipboard capture | MEDIUM | async/await on background task |
| Cache results | Same URL copied again should not re-fetch | LOW | Store in ClipboardItem model fields |

### Differentiators for URL Previews

| Feature | Value | Complexity | Notes |
|---------|-------|------------|-------|
| Favicon display | Visual site identification at a glance | MEDIUM | Fetch + disk cache + async image loading |
| og:image header | Makes URL cards visually rich, like link previews in Slack/iMessage | HIGH | Large image fetch + storage + thumbnail |
| Click to open in browser | Tap URL card opens it in default browser | LOW | `NSWorkspace.shared.open(url)` |

### Anti-Features for URL Previews

| Anti-Feature | Why Avoid | Alternative |
|--------------|-----------|-------------|
| Full webpage screenshot/thumbnail | Extremely heavy (requires WebKit rendering), slow, storage-hungry | og:image is sufficient; most cards are small |
| Link checking (detect dead links) | Adds latency, unreliable, not the app's job | Just show the URL; user can click to verify |
| Auto-shorten URLs | Modifies clipboard content; violates user trust | Show full URL; let user paste as-is |
| Metadata refresh on every view | Wastes bandwidth, adds latency | Fetch once at capture time, cache forever |
| Fetching for every URL blindly | Privacy concern: user may copy sensitive URLs | Skip concealed items, skip local IPs, add settings toggle |

---

## 3. Color Value Detection + Visual Swatches

### How It Works in Clipboard Managers

**Detection approach:** Color detection is simpler than code detection because color formats have well-defined patterns. PastePal is the main competitor that does this. The detection runs against the text content of `.text` items.

**Supported formats (priority order):**

| Format | Regex Pattern | Example | Priority |
|--------|--------------|---------|----------|
| Hex 6-digit | `#[0-9A-Fa-f]{6}` | `#FF5733` | MUST |
| Hex 3-digit | `#[0-9A-Fa-f]{3}` | `#F53` | MUST |
| Hex 8-digit (with alpha) | `#[0-9A-Fa-f]{8}` | `#FF573380` | SHOULD |
| rgb() | `rgb\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)` | `rgb(255, 87, 51)` | MUST |
| rgba() | `rgba\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*[\d.]+\s*\)` | `rgba(255, 87, 51, 0.5)` | SHOULD |
| hsl() | `hsl\(\s*\d{1,3}\s*,\s*\d{1,3}%\s*,\s*\d{1,3}%\s*\)` | `hsl(14, 100%, 60%)` | NICE |
| Named CSS colors | Keyword match | `rebeccapurple`, `cornflowerblue` | DO NOT -- too many false positives |

**Expected behavior:** When the copied text exactly matches or primarily consists of a color value, the card switches to a color preview mode. The key UX decision is: **show the color swatch alongside the text value, not instead of it.** Designers copy color values precisely because they need the text representation to paste somewhere. The swatch is additional context.

**Card anatomy:**

```
+----------------------------------+
| [app icon]              2m ago   |
| +--------+  #FF5733             |
| | swatch |  rgb(255, 87, 51)    |
| +--------+                      |
+----------------------------------+
```

**Detection criteria (important nuance):** The entire clipboard content should be a color value, OR the content should be very short (under ~30 characters) and contain a color value. Do NOT detect colors inside longer text like "Set the background to #FF5733 for the header." That should remain a text card. The threshold is: if the text, after trimming whitespace, matches a color pattern entirely, it is a color item.

**Model changes needed:**
- Add `.color` case to `ContentType` enum
- Add `detectedColorHex: String?` to ClipboardItem (normalized 6-digit hex for rendering)
- Card dispatcher routes `.color` to a new `ColorCardView`

**SwiftUI swatch rendering:**

```swift
// Convert hex to SwiftUI Color
Color(red: r/255, green: g/255, blue: b/255)

// Render as a rounded rect swatch
RoundedRectangle(cornerRadius: 6)
    .fill(swatchColor)
    .frame(width: 40, height: 40)
    .overlay(
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
    )
```

### Table Stakes for Color Swatches

| Requirement | Why Expected | Complexity | Notes |
|-------------|--------------|------------|-------|
| Detect hex colors (#RGB, #RRGGBB) | Most common format; designers/developers use this constantly | LOW | Simple regex |
| Detect rgb() values | Second most common format | LOW | Simple regex |
| Visual swatch rendering | The entire point; without the visual, detection is meaningless | LOW | SwiftUI Color + RoundedRectangle |
| Show text value alongside swatch | Users need the text to paste; swatch is supplementary | LOW | HStack layout |
| Paste original text, not color object | User copied text, paste text. The swatch is display-only. | LOW | No change to paste behavior; textContent is pasted as-is |

### Differentiators for Color Swatches

| Feature | Value | Complexity | Notes |
|---------|-------|------------|-------|
| Detect rgba()/hsla() with alpha | Covers more formats; designers use alpha values | LOW | Extra regex patterns |
| Show both hex and rgb representations | Copy hex, see rgb conversion and vice versa | LOW | Pure computation |
| Checkerboard behind alpha swatches | Standard pattern for showing transparency | LOW | ZStack with checkerboard pattern behind color fill |
| Copy in alternate format (context menu) | Right-click to copy as hex when original was rgb | MEDIUM | Adds context menu action; useful for designers |

### Anti-Features for Color Swatches

| Anti-Feature | Why Avoid | Alternative |
|--------------|-----------|-------------|
| Color picker / editor | Different product (Digital Color Meter, Sip); modifying clipboard content is out of scope | Read-only swatch display |
| Detect colors inside long text | Too many false positives; "Page 3 is #1 in sales" matches hex pattern | Only detect when entire content is a color value |
| Named CSS color detection | "red", "blue", "green" etc. would match common English words, causing false positives | Stick to syntactic formats (#hex, rgb(), hsl()) |
| Palette generation (complementary colors, etc.) | Feature creep; this is a clipboard manager, not a design tool | Just show what was copied |
| Color space conversion (P3, CMYK, etc.) | Niche; adds complexity for minimal value | Stick to sRGB display |

---

## 4. Cmd+1-9 Direct Paste Hotkeys

### How It Works in Clipboard Managers

**The paradigm:** CopyLess 2 pioneered this. PastePal adopted it. The concept: register global hotkeys for Cmd+1 through Cmd+9. Each corresponds to the Nth most recent clipboard item. Pressing the hotkey pastes that item directly into the active app without opening the clipboard panel.

**Expected behavior (critical details):**

1. Cmd+1 = most recent item (same as "paste last")
2. Cmd+2 = second most recent
3. ...
4. Cmd+9 = ninth most recent
5. The hotkeys work globally, regardless of whether the panel is open
6. The panel does NOT open when using these hotkeys
7. Items are ordered by timestamp descending (same as panel order)
8. Paste behavior respects the same settings as panel paste (direct paste vs. copy-to-clipboard)

**Implementation approach with KeyboardShortcuts:**

The existing codebase uses `KeyboardShortcuts` (sindresorhus) for the panel toggle hotkey. The same library can register Cmd+1 through Cmd+9. However, there is a critical consideration:

**Conflict risk:** Cmd+1 through Cmd+9 are commonly used by other applications:
- Browsers: Cmd+1-9 switch tabs
- Finder: Cmd+1-4 switch view modes
- Many editors: Cmd+1-9 switch tabs or panels

**The standard solution (used by CopyLess 2 and PastePal):** Use a **modifier combination** that does not conflict. Common choices:

| Modifier | Conflict Risk | Ergonomics | Notes |
|----------|---------------|------------|-------|
| Cmd+1-9 | HIGH -- conflicts with browser tabs, Finder | Best | Requires careful conflict management; can steal shortcuts from active app |
| Ctrl+1-9 | LOW -- rarely used by macOS apps | Good | Safe default; some terminal emulators use Ctrl+1-9 |
| Opt+1-9 | MEDIUM -- some apps use Option for special characters | Medium | Types special characters on some keyboard layouts |
| Cmd+Shift+1-9 | LOW | Acceptable | Longer reach but safe |
| Custom (user-configurable) | NONE | Best | Complex to implement; KeyboardShortcuts supports this |

**Recommendation: Default to Ctrl+1-9 with the option to disable.** Ctrl+1-9 has the lowest conflict risk and is ergonomically comfortable. Expose a toggle in Settings to enable/disable the feature entirely (some users may not want global number hotkeys). Do NOT default to Cmd+1-9 -- stealing browser tab switching would immediately frustrate users.

**Implementation flow:**

```
1. Register global hotkeys: Ctrl+1 through Ctrl+9 via KeyboardShortcuts
2. On hotkey press:
   a. Fetch the Nth most recent item from SwiftData
   b. Call AppState.paste(item:) with that item
   c. PasteService handles pasteboard write + CGEvent Cmd+V
3. Panel stays closed (or closes if open)
```

**Data access pattern:** The hotkey handler needs to query SwiftData for the Nth item:

```swift
var descriptor = FetchDescriptor<ClipboardItem>(
    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
)
descriptor.fetchLimit = n  // 1-9
descriptor.fetchOffset = n - 1  // 0-based offset
let items = try modelContext.fetch(descriptor)
guard let item = items.first else { return }
```

**KeyboardShortcuts registration (9 shortcuts):**

```swift
extension KeyboardShortcuts.Name {
    static let paste1 = Self("paste1", default: .init(.one, modifiers: [.control]))
    static let paste2 = Self("paste2", default: .init(.two, modifiers: [.control]))
    // ... through paste9
}
```

### Table Stakes for Cmd+1-9 Hotkeys

| Requirement | Why Expected | Complexity | Notes |
|-------------|--------------|------------|-------|
| Global hotkeys that work from any app | The entire point is bypassing the panel | MEDIUM | KeyboardShortcuts library handles this |
| Items ordered by recency (most recent = 1) | Matches mental model: "1 = last thing I copied" | LOW | FetchDescriptor with timestamp sort |
| Same paste behavior as panel | Consistency; user expects Cmd+V simulation or copy-to-clipboard based on setting | LOW | Reuse existing PasteService.paste() |
| Panel does NOT open | This is the quick-paste path; opening panel defeats the purpose | LOW | Do not call panelController.toggle() |
| Visual/audio feedback that paste happened | Without the panel visible, user needs confirmation something happened | MEDIUM | Brief menu bar icon flash, or system notification sound; subtle but important |
| Enable/disable toggle in Settings | Not all users want global number hotkeys; must be opt-in or easily disabled | LOW | @AppStorage boolean + conditional hotkey registration |

### Differentiators for Cmd+1-9 Hotkeys

| Feature | Value | Complexity | Notes |
|---------|-------|------------|-------|
| Tooltip/HUD showing what will be pasted | Brief floating overlay near cursor showing item 1-9 content before pasting | HIGH | Requires custom window management; deferred |
| Configurable modifier key | Let users choose between Ctrl, Cmd, Opt, Cmd+Shift | MEDIUM | KeyboardShortcuts supports custom modifiers; good UX win |
| Number overlay on panel cards | When panel IS open, show "1", "2"... badges on first 9 cards | LOW | Visual hint of hotkey mapping; easy to implement |

### Anti-Features for Cmd+1-9 Hotkeys

| Anti-Feature | Why Avoid | Alternative |
|--------------|-----------|-------------|
| Cmd+1-9 as default modifier | Conflicts with browser tab switching, Finder view modes; would frustrate users immediately | Use Ctrl+1-9 or Cmd+Shift+1-9 as default |
| More than 9 hotkeys (Cmd+0, Cmd+10+) | Diminishing returns; users cannot remember positions beyond ~5 | Cap at 9; for deeper items, use the panel |
| Custom per-slot assignment | "Cmd+1 always pastes my email signature" -- this is snippet/template functionality, not clipboard history | Slots always map to Nth most recent; for fixed content, use pinned items (v1.2) |
| Hotkeys active when panel is open | Confusing: does Cmd+3 paste the 3rd item or interact with the panel? | Hotkeys should work identically whether panel is open or closed |

---

## 5. Label Emoji + Expanded Color Palette

### How It Works in Clipboard Managers

**Current state (Pastel v1.0):**
- Label model: `name: String`, `colorName: String`, `sortOrder: Int`
- LabelColor enum: 8 colors (red, orange, yellow, green, blue, purple, pink, gray)
- Chip bar shows: `[colored dot] Label Name`
- Settings: click color dot to recolor via menu
- Context menu: assign label with colored dot + name

**Proposed v1.1 enhancements:**
1. Expand color palette from 8 to 12 colors
2. Add optional emoji per label that replaces the color dot when set

### Expanded Color Palette (8 -> 12)

**Standard expanded palette for label systems (matches Apple Notes, Reminders, Finder tags):**

| Color | Why Include | New? |
|-------|-------------|------|
| Red | Urgency, errors, important | Existing |
| Orange | Warnings, attention | Existing |
| Yellow | Highlights, caution | Existing |
| Green | Success, approved, safe | Existing |
| Blue | Default, general, info | Existing |
| Purple | Creative, special | Existing |
| Pink | Personal, playful | Existing |
| Gray | Archived, neutral | Existing |
| Teal | Design, development | NEW |
| Indigo | Deep category, formal | NEW |
| Mint | Fresh, secondary green | NEW |
| Brown | Reference, documentation | NEW |

**SwiftUI Color availability for new colors:**
- `.teal` -- available macOS 13+ (HIGH confidence)
- `.indigo` -- available macOS 13+ (HIGH confidence)
- `.mint` -- available macOS 13+ (HIGH confidence)
- `.brown` -- available macOS 13+ (HIGH confidence)

All four new colors are native SwiftUI Color constants on macOS 14 (Pastel's target). No custom hex definitions needed.

**Model impact:** No model changes needed. `colorName` is already a String. Just add new cases to `LabelColor` enum.

### Label Emoji

**Expected behavior (per PROJECT.md decision):** "Either emoji OR color, not both -- keeps chips clean."

**When emoji is NOT set:**
```
[colored dot] Label Name
```

**When emoji IS set:**
```
[emoji] Label Name
```

The emoji replaces the color dot entirely. The chip background/border can still use the label's color for filtering highlight state.

**Implementation pattern:**

```swift
// Label model gets an optional emoji field
@Model
final class Label {
    var name: String
    var colorName: String
    var sortOrder: Int
    var emoji: String?  // NEW: single emoji character, nil = use color dot
    // ...
}
```

**Emoji picker UX options:**

1. **System emoji picker** (NSApp.orderFrontCharacterPalette): The standard macOS emoji picker, triggered by Ctrl+Cmd+Space or programmatically. Reliable but launches a separate window.

2. **Inline emoji grid**: A small grid of preset emojis (20-30 common ones) in the label settings row. Simpler, more contained UX. Popular choices for productivity labels: folders, tags, bookmarks, stars, hearts, fire, lightning, etc.

3. **Text field**: Let user type or paste any emoji into a small text field. Simplest implementation but worst UX (users may not know how to type emoji).

**Recommendation: Inline preset grid with a "more" button that opens the system picker.** This gives quick access to common productivity emojis while allowing full emoji access for power users. The preset grid should include 15-20 emojis like:

```
Work: briefcase, laptop, wrench, gear, rocket
Personal: heart, star, fire, sparkles, rainbow
Categories: folder, bookmark, tag, pin, flag
Status: checkmark, warning, clock, eye, bell
```

**Clearing the emoji:** A clear/remove button (small "x" or circle-slash) to revert to color dot mode. Essential UX -- users must be able to undo an emoji choice.

**Where emoji appears (every surface that currently shows the color dot):**
1. Chip bar in panel
2. Context menu label assignment
3. Card label indicator (if shown)
4. Settings label row

### Table Stakes for Label Enhancements

| Requirement | Why Expected | Complexity | Notes |
|-------------|--------------|------------|-------|
| Expanded color palette (10-12 colors) | 8 feels limiting; Apple's own tag systems offer more | LOW | Add enum cases + SwiftUI Colors |
| Optional emoji per label | Visual differentiation beyond color; accessibility win (color-blind users) | MEDIUM | Model field + emoji picker UI |
| Emoji replaces color dot (not additive) | Keep chips clean; PROJECT.md decision | LOW | Conditional rendering in chip/context menu |
| Clear/remove emoji option | Users must be able to undo | LOW | UI button + set emoji to nil |
| Backwards-compatible (existing labels keep working) | Adding emoji field must not break existing labels | LOW | Optional field defaults to nil |

### Differentiators for Label Enhancements

| Feature | Value | Complexity | Notes |
|---------|-------|------------|-------|
| System emoji picker access | Full Unicode emoji support, not just presets | LOW | `NSApp.orderFrontCharacterPalette(nil)` |
| Emoji in context menu | Labels with emoji show the emoji in right-click menu | LOW | Replace circle with Text(emoji) in menu |
| Animated emoji on hover | Subtle scale/bounce on chip hover | LOW | SwiftUI animation; delightful polish |

### Anti-Features for Label Enhancements

| Anti-Feature | Why Avoid | Alternative |
|--------------|-----------|-------------|
| Custom hex color input | Adds UI complexity; 12 preset colors is sufficient for label categorization | Curated palette of 12 |
| Gradient label colors | Visual complexity; does not add organizational value | Solid colors only |
| Multiple emoji per label | Clutters chips; single emoji is the identifier | One emoji max |
| Auto-assign emoji based on label name | Would often guess wrong; user intent matters | Manual emoji selection |
| Custom icon upload | Way over-scoped; emoji covers this need | System emoji only |

---

## Feature Dependencies on Existing v1.0 Codebase

### What New Features Build On

| New Feature | Depends On (existing) | Integration Point | Migration Risk |
|-------------|----------------------|-------------------|----------------|
| Code detection | ClipboardMonitor.processPasteboardContent() | Secondary classification after `.text` type | LOW -- additive logic |
| Code highlighting | ClipboardCardView contentPreview switch | New case in switch + new CodeCardView | LOW -- new view, no changes to existing |
| Code highlighting | ContentType enum | Add `.code` case | MEDIUM -- must handle in all switch statements |
| URL previews | URLCardView | Replace or enhance existing view | LOW -- enhances existing view |
| URL metadata fetch | ClipboardMonitor (async post-capture) | New async service triggered after URL item saved | LOW -- new service, no changes to monitor flow |
| URL metadata storage | ClipboardItem model | New optional String fields | MEDIUM -- SwiftData migration needed |
| Color detection | ClipboardMonitor.processPasteboardContent() | Secondary classification after `.text` type | LOW -- additive logic |
| Color swatches | ClipboardCardView contentPreview switch | New case in switch + new ColorCardView | LOW -- new view |
| Color detection | ContentType enum | Add `.color` case | MEDIUM -- same as code; handle in all switches |
| Cmd+1-9 hotkeys | AppState.setupPanel() | Register 9 additional KeyboardShortcuts | LOW -- additive |
| Cmd+1-9 hotkeys | PasteService.paste() | Reuse existing paste flow | LOW -- no changes to PasteService |
| Cmd+1-9 hotkeys | KeyboardShortcuts library | 9 new shortcut names | LOW -- library already integrated |
| Label emoji | Label model | New optional String field | MEDIUM -- SwiftData migration |
| Label emoji | ChipBarView, LabelSettingsView, ClipboardCardView context menu | Conditional rendering at emoji/dot decision points | LOW -- presentation changes |
| Expanded palette | LabelColor enum | Add 4 new cases | LOW -- enum extension |

### SwiftData Migration Considerations

Adding fields to `ClipboardItem` and `Label` will trigger SwiftData's automatic lightweight migration:

- Adding optional fields (`detectedLanguage: String?`, `urlTitle: String?`, `emoji: String?`, etc.) is a lightweight migration (no data transformation)
- Adding a new enum case to ContentType is safe because it is stored as String (existing items remain `.text`, `.url`, etc.)
- Existing items will have `nil` for all new optional fields -- this is correct behavior

**Risk:** SwiftData's automatic migration should handle this. If it does not (rare but possible for complex changes), a manual migration or database reset may be needed. Test migration with a populated v1.0 database.

---

## Complexity Summary

| Feature | Detection | Storage | UI | Network | Total | Phase Recommendation |
|---------|-----------|---------|----|---------|----|---------------------|
| Code highlighting | HIGH | LOW | MEDIUM | NONE | HIGH | Phase 1 or 2 -- needs library evaluation |
| URL preview cards | LOW | MEDIUM | MEDIUM | HIGH | HIGH | Phase 2 or 3 -- network adds risk |
| Color swatches | LOW | LOW | LOW | NONE | LOW | Phase 1 -- quick win |
| Cmd+1-9 hotkeys | N/A | N/A | LOW | NONE | MEDIUM | Phase 1 -- independent feature |
| Label emoji + colors | N/A | LOW | MEDIUM | NONE | LOW-MEDIUM | Phase 1 -- quick win |

**Recommended ordering:**
1. **Label emoji + expanded palette** -- lowest risk, smallest scope, immediate visual impact
2. **Color swatches** -- low complexity, no dependencies, completes the "detection" story
3. **Cmd+1-9 hotkeys** -- independent of rich content; high user value
4. **Code highlighting** -- higher complexity but no network; can evaluate Highlightr
5. **URL preview cards** -- highest risk due to network; do last so other features are stable

---

## Sources

- Apple Developer Documentation: NSPasteboard, URLSession, SwiftData migration (HIGH confidence -- stable Apple APIs)
- Highlightr library (github.com/raspu/Highlightr): Training data knowledge (MEDIUM confidence -- verify current maintenance status and version before adopting)
- KeyboardShortcuts library (github.com/sindresorhus/KeyboardShortcuts): Already in project, known working (HIGH confidence)
- PastePal feature set: Training data knowledge (MEDIUM confidence -- features may have changed)
- CopyLess 2 Cmd+1-9 paradigm: Training data knowledge (MEDIUM confidence)
- SwiftUI Color constants (.teal, .indigo, .mint, .brown): Training data knowledge of macOS 13+ availability (HIGH confidence -- Apple framework constants are stable)
- Open Graph Protocol (ogp.me): Well-established standard, unlikely to have changed (HIGH confidence)

**Gaps requiring phase-specific research:**
- Highlightr: Current version, macOS compatibility, Swift 6 concurrency safety, bundle size impact. Verify before adopting.
- URL metadata fetching: Test with real-world URLs to calibrate timeout, error handling, and edge cases (redirects, paywalls, SPAs that render client-side).
- KeyboardShortcuts Ctrl+1-9: Verify library supports Control modifier; test conflict behavior on macOS.

---
*Feature research for: Pastel v1.1 -- Rich Content & Enhanced Paste*
*Researched: 2026-02-06*
