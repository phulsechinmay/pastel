# Domain Pitfalls: v1.1 Rich Content & Enhanced Paste

**Domain:** macOS clipboard manager -- adding rich content, enhanced paste, and label enrichment to existing v1.0
**Researched:** 2026-02-06
**Confidence:** MEDIUM (WebSearch and WebFetch unavailable; findings based on training knowledge of macOS APIs, SwiftUI, SwiftData, syntax highlighting libraries, and network I/O patterns. These are mature domains with stable patterns unlikely to have changed significantly since training cutoff.)

---

## Critical Pitfalls

Mistakes that cause rewrites, broken core functionality, or significant regressions in the existing v1.0 system.

### Pitfall 1: Code Detection False Positives Flooding History with "Code" Cards

**What goes wrong:**
Naive code detection heuristics misclassify ordinary text as code. Common false positives:
1. **URLs with path components** -- `https://example.com/api/users/list?page=1` has slashes, dots, equals signs.
2. **Structured data / config** -- key=value text, JSON snippets from logs, CSV data.
3. **Terminal output** -- `ls -la` output, error messages with stack traces.
4. **Prose with inline code** -- Slack/email messages containing backtick-wrapped snippets.

The result: the majority of text items get classified as "code" and shown with syntax highlighting, making the panel noisy and the code card type meaningless.

**Why it happens:**
Code detection is inherently ambiguous. There is no single reliable heuristic. Developers overfit detection to their own usage patterns (copying Swift code from Xcode) and do not test with non-code text.

**Specific risk in Pastel's architecture:**
Content classification happens in `NSPasteboard+Reading.swift` via `classifyContent()`. Currently, the type system is `text | richText | url | image | file`. Adding a `code` subtype means the classification function must distinguish code from plain text -- but both arrive as `.string` pasteboard type with no metadata from the source app indicating "this is code."

**Prevention:**
- Do NOT add a `code` ContentType to the enum. Keep code as a **display enrichment** on text items, not a separate type. Store detected language as an optional field (e.g., `detectedLanguage: String?` on ClipboardItem), but the item remains `.text`.
- Use **multiple signals combined**, not any single heuristic:
  - Source app bundle ID: If from Xcode, VS Code, IntelliJ, Terminal, iTerm -- boost code likelihood.
  - Structural patterns: Count of semicolons, braces, indentation consistency, keyword density.
  - Length: Very short text (under 20 chars) is almost never a code snippet worth highlighting.
  - Negative signal: If the text contains mostly natural language words (articles, prepositions), suppress code detection.
- Set a **confidence threshold**. Only highlight if detection confidence exceeds 70%. When in doubt, render as plain text. False negatives (missing a code snippet) are far less annoying than false positives (highlighting prose as code).
- Make code highlighting a visual treatment, not a classification. The card shows syntax highlighting ONLY in the preview area. The item is still searchable as text, still deletable, still pasteable as text.

**Warning signs:**
- During testing, copy a paragraph of English prose. If it renders with syntax highlighting, detection is too aggressive.
- Copy a URL. If it renders as a "code" card instead of a URL card, the classification priority is wrong.

**Detection phase:** This pitfall must be addressed during the code detection implementation phase. Build the detection heuristic with a test suite of diverse clipboard content (prose, URLs, config files, actual code in 5+ languages, mixed content).

**Confidence:** HIGH -- code detection false positives are a well-known problem in every editor and tool that attempts language detection on arbitrary text.

---

### Pitfall 2: Syntax Highlighting Library Crashes or Blocks the Main Thread

**What goes wrong:**
Syntax highlighting libraries process text through tokenizers and grammar engines. Common failures:
1. **highlight.js-based libraries (Highlightr) use JavaScriptCore** -- JSContext initialization is expensive (50-200ms on first use). If initialized on the main thread during card rendering, the panel stutters visibly on first scroll past a code item.
2. **Large code blocks cause long processing times** -- A 500-line code snippet can take 100-500ms to highlight. During this time, the UI is blocked if highlighting runs synchronously.
3. **Memory pressure from attributed strings** -- Each highlighted code block becomes an `NSAttributedString` with font, color, and background attributes on every token. Hundreds of highlighted items in memory cause significant RAM growth.
4. **Crash on malformed input** -- Some highlighting engines crash on inputs with unusual Unicode, extremely long lines (10K+ chars), or binary data that was misdetected as text.

**Why it happens:**
Developers test with small, well-formed code snippets during development. Production clipboard content includes giant log dumps, minified JavaScript (single line, 100K chars), binary-looking data, and mixed encodings.

**Specific risk in Pastel's architecture:**
The card views (`TextCardView`, `ClipboardCardView`) render inside a `LazyVStack` / `LazyHStack` in `FilteredCardListView`. SwiftUI creates views on-demand during scroll. If highlighting runs synchronously in the view body, every scroll past a code item triggers a blocking highlight operation.

**Prevention:**
- **Choose Splash (JohnSundell/Splash) over Highlightr if only Swift highlighting is needed.** Splash is pure Swift with no JavaScript dependency, fast, and lightweight. However, it only supports Swift syntax. If multi-language support is needed, use Highlightr but with the mitigations below.
- **If using Highlightr (highlight.js wrapper):** Initialize the `Highlightr` instance ONCE at app startup on a background thread. Reuse that single instance. JSContext initialization is the expensive part -- do it once, not per-card.
- **Highlight asynchronously.** Use a `.task` modifier on the card view to run highlighting on a background actor. Cache the resulting `AttributedString` on the ClipboardItem model (or in a separate in-memory cache keyed by contentHash). Never highlight the same content twice.
- **Truncate before highlighting.** Cap the input to highlighting at ~2000 characters for card preview purposes. The user sees a preview, not the full content. This bounds worst-case highlighting time.
- **Guard against crashes.** Wrap highlighting calls in a do-catch (or use optional returns). If highlighting fails, fall back to plain text rendering. Never let a highlighting failure crash the app or produce a blank card.
- **Use `AttributedString` (SwiftUI native) not `NSAttributedString`.** SwiftUI's `Text` view accepts `AttributedString` directly. Converting from `NSAttributedString` to `AttributedString` is needed if using Highlightr, but the conversion should happen once during caching, not on every render.
- **Limit concurrent highlighting.** If the user scrolls quickly through many code items, queue highlighting with a `TaskGroup` limited to 2-3 concurrent operations. Do not spawn unlimited background tasks.

**Warning signs:**
- Panel stutters when scrolling past the first code item (JSContext init on main thread).
- Memory grows linearly with the number of code items displayed (no caching, re-highlighting every render).
- Crash logs showing JavaScriptCore or Highlightr in the stack trace.

**Detection phase:** Must be addressed during syntax highlighting implementation. Build the caching + async pipeline first, then add the actual highlighting library.

**Confidence:** MEDIUM -- Highlightr's JSContext overhead is based on training knowledge. Splash's pure-Swift approach is well-known. Specific performance numbers should be profiled during implementation.

---

### Pitfall 3: URL Metadata Fetching Blocks Clipboard Capture or Leaks Network Activity

**What goes wrong:**
Auto-fetching Open Graph metadata (title, favicon, header image) when a URL is copied introduces network I/O into a previously offline pipeline. Failures:
1. **Fetching on the main thread** blocks clipboard monitoring. If a URL points to a slow server (5s timeout), the polling timer stalls and subsequent clipboard changes are missed.
2. **Fetching synchronously in the capture pipeline** means the ClipboardItem is not persisted until the fetch completes (or times out). The user copies a URL, and it does not appear in the panel for several seconds.
3. **No timeout or cancellation** -- if the user copies 10 URLs in quick succession, 10 concurrent network requests fire. Some may never complete, holding URLSession connections open indefinitely.
4. **Fetching from private/internal URLs** -- the user copies `http://192.168.1.1/admin` or `https://internal-dashboard.company.com`. The app attempts to fetch metadata from internal networks, which is unexpected behavior and a privacy concern.
5. **Fetching from localhost** -- developers copy `http://localhost:3000/api/test`. The fetch hits their local dev server, potentially triggering side effects (webhooks, state changes) if the endpoint is not idempotent.
6. **Storing fetched images in SwiftData** -- Open Graph images can be large. Storing them as Data blobs in the ClipboardItem model bloats the database (same problem as the v1.0 image-in-database pitfall).

**Why it happens:**
Developers test with well-known public URLs (github.com, apple.com) that respond quickly with rich metadata. Production usage includes private networks, slow servers, broken SSL, redirects to login pages, and URLs behind authentication.

**Specific risk in Pastel's architecture:**
The current `processPasteboardContent()` in `ClipboardMonitor` is entirely synchronous (except for image disk I/O). Adding network fetching here would either block the capture pipeline or require significant restructuring of the data flow.

**Prevention:**
- **Decouple fetching from capture completely.** The capture pipeline must remain fast and offline. When a URL is captured:
  1. Create the ClipboardItem immediately with `textContent = urlString` and `contentType = .url`. Persist it to SwiftData right away. The item appears in the panel instantly.
  2. After persisting, enqueue a background metadata fetch task. When metadata arrives, update the existing ClipboardItem with title, favicon path, and OG image path.
- **Store fetched assets on disk, not in SwiftData.** Follow the same pattern as image storage: save favicon and OG image as files in Application Support, store only the file paths in the model. Add `ogTitle: String?`, `ogImagePath: String?`, `faviconPath: String?` fields to ClipboardItem.
- **Strict timeouts.** Set URLSession timeout to 5 seconds for metadata fetches. If the server does not respond in 5 seconds, give up and leave the URL card in its plain state. Users will not notice the missing metadata.
- **Skip private/local URLs.** Before fetching, check the URL host:
  - Skip `localhost`, `127.0.0.1`, `0.0.0.0`
  - Skip private IP ranges (`10.x.x.x`, `172.16-31.x.x`, `192.168.x.x`)
  - Skip `.local` domains
  - Only fetch for URLs with public DNS-resolvable hosts
- **Rate limit and deduplicate.** If the same URL is copied multiple times, do not fetch metadata again. Check if `ogTitle` is already populated before fetching. Limit concurrent metadata fetches to 2-3.
- **Graceful degradation is the default.** The URL card must look good WITHOUT metadata. The current `URLCardView` shows a globe icon + URL text. That is the fallback. Metadata (title, favicon) is progressive enhancement -- nice when available, invisible when missing.
- **Cancel on item deletion.** If the user deletes a ClipboardItem while its metadata fetch is in-flight, cancel the URLSession task. Otherwise, the completion handler tries to update a deleted model, causing a crash or orphaned files on disk.

**Warning signs:**
- URLs appear in the panel with a delay (fetching is blocking capture).
- Console shows network errors for `192.168.x.x` or `localhost` addresses.
- Memory grows when many URLs are copied (OG images stored in memory or in SwiftData).
- Crash on metadata fetch completion after item was deleted.

**Detection phase:** Must be addressed during URL metadata fetching implementation. The decouple-from-capture architecture must be decided before writing any networking code.

**Confidence:** HIGH -- network I/O in clipboard capture is a well-understood integration challenge. The decouple-and-background pattern is standard.

---

### Pitfall 4: Cmd+1-9 Hotkeys Conflict with System and App Shortcuts

**What goes wrong:**
Registering Cmd+1-9 as global hotkeys (working system-wide, even when Pastel's panel is not open) causes conflicts:
1. **Safari, Chrome, Firefox** use Cmd+1-9 to switch tabs. If Pastel registers these globally, browser tab switching breaks. Users will uninstall immediately.
2. **Finder** uses Cmd+1-4 for view modes (icons, list, columns, gallery).
3. **Terminal/iTerm** uses Cmd+1-9 for tab switching.
4. **VS Code** and most editors use Cmd+1-9 for editor group switching.
5. Even if Pastel only intercepts when the panel is open, Carbon hotkeys registered globally still fire -- you must unregister them when the panel is hidden.

**Why it happens:**
Developers think "Cmd+1-9 for quick paste" is intuitive (CopyLess 2 does it). But CopyLess 2 only activates these hotkeys when its own UI is visible. Registering them globally breaks the entire macOS ecosystem of keyboard shortcuts.

**Specific risk in Pastel's architecture:**
The current hotkey system uses `KeyboardShortcuts` (sindresorhus) which wraps Carbon `RegisterEventHotKey`. These are inherently global -- they intercept the key combination system-wide. The existing `togglePanel` shortcut (Cmd+Shift+V) is fine because no major app uses that combination. Cmd+1-9 is a completely different story.

**Prevention:**
- **Do NOT register Cmd+1-9 as global hotkeys.** This is the single most important decision.
- **Two modes for Cmd+1-9:**
  - **Mode A (Recommended): Panel-open only.** When the panel is visible, intercept Cmd+1-9 using `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` (local monitor, only catches events when Pastel has focus) or SwiftUI `.onKeyPress`. When the panel is hidden, these shortcuts do nothing -- they pass through to whatever app is active.
  - **Mode B: Global with modifier.** Use a distinct modifier like Ctrl+1-9 or Ctrl+Cmd+1-9 that does not conflict with standard apps. This allows pasting without opening the panel first, but requires an unusual key combination.
- **If panel-open only (Mode A):** The panel currently uses `NSPanel` with `.nonactivatingPanel`, which means it does NOT become the key window. Local event monitors only work when the app is the key app. Since the panel is non-activating, the local monitor will not receive key events.
  - **Solution:** Use the existing local key monitor in `PanelController.installEventMonitors()` which already intercepts Escape. Extend it to also intercept Cmd+1-9 when the panel is visible. This works because `NSEvent.addLocalMonitorForEvents` catches events delivered to the app (the panel receives them even though it is non-activating, because the monitor is installed on the app, not the window).
  - **Alternative:** Register Cmd+1-9 as Carbon hotkeys via KeyboardShortcuts ONLY when `show()` is called, and unregister them in `hide()`. This makes them effectively panel-open-only. But registration/unregistration on every show/hide adds complexity and potential race conditions.
- **Show number badges on cards.** When the panel is open, overlay "1", "2", ... "9" badges on the first 9 items. Without visual indicators, users cannot know which number corresponds to which item.
- **Handle the edge case where items are fewer than 9.** If only 5 items exist, Cmd+6 through Cmd+9 should be no-ops, not crash.

**Warning signs:**
- During testing, open Safari and press Cmd+1. If Pastel intercepts it instead of Safari switching to tab 1, the hotkeys are registered globally when they should not be.
- Users report "my browser shortcuts stopped working."

**Detection phase:** Must be addressed during Cmd+1-9 implementation. The scoping decision (global vs panel-open) must be made before any hotkey registration code is written.

**Confidence:** HIGH -- Cmd+1-9 conflicts with standard macOS app shortcuts are well-documented and universally experienced by developers who try to register these combinations globally.

---

### Pitfall 5: SwiftData Schema Migration Fails or Loses Data When Adding New Fields

**What goes wrong:**
Adding new optional fields to `ClipboardItem` (e.g., `detectedLanguage`, `ogTitle`, `ogImagePath`, `faviconPath`) requires a SwiftData schema migration. Common failures:
1. **Adding a non-optional field without a default** crashes at launch. SwiftData cannot populate existing rows with a non-optional field that has no default value. The app crashes with a Core Data migration error (SwiftData wraps Core Data under the hood).
2. **Renaming a field** (e.g., `imagePath` to `fullImagePath`) is interpreted by SwiftData as deleting one field and adding another. All existing data in the old field is lost.
3. **Changing a field type** (e.g., `colorName: String` to `colorName: LabelColor` or `labelEmoji: String?` to `labelEmoji: Character?`) can fail migration silently, producing nil values for all existing rows.
4. **Adding a new relationship** (e.g., adding a `URLMetadata` model related to ClipboardItem) requires careful migration planning. SwiftData's lightweight migration handles simple additions but not relationship restructuring.

**Why it happens:**
SwiftData's automatic lightweight migration is convenient for simple additions but opaque when it fails. Developers add fields during development (where the database is fresh) and do not test migration from a v1.0 database to the v1.1 schema. The migration fails only for existing users upgrading the app.

**Specific risk in Pastel's architecture:**
The ClipboardItem model already has 16 fields. v1.1 needs to add several more. The Label model needs `emoji: String?`. The `LabelColor` enum may need more cases (expanded palette). Each change is a potential migration issue.

**Prevention:**
- **All new fields MUST be optional with nil default.** No exceptions. `var detectedLanguage: String? = nil`, `var ogTitle: String? = nil`, etc. SwiftData handles "add optional field with nil default" as a lightweight migration automatically.
- **Never rename fields.** If you need a better name, add the new field and deprecate the old one. Migrating data from old to new field requires a manual migration step.
- **Never change field types.** If `colorName` needs to become an enum, keep it as `String` in storage and use a computed property for the enum conversion (this pattern is already used for `contentType` / `type` in the current code).
- **Test migration explicitly.** Before shipping v1.1:
  1. Build v1.0 from the current main branch.
  2. Run it, generate clipboard history (text, images, URLs, labeled items).
  3. Switch to the v1.1 branch.
  4. Run v1.1. Verify all existing data is present and the new fields are nil.
  5. If the app crashes on launch, the migration failed.
- **For the Label model:** Adding `emoji: String? = nil` is safe (optional, nil default). Expanding `LabelColor` enum cases is safe (the raw value is a String stored in `colorName`, and new enum cases just add new valid strings). Existing labels keep their existing `colorName` values.
- **Keep URL metadata on ClipboardItem, not a separate model.** Adding a new related model (`URLMetadata`) introduces a relationship migration. Instead, add `ogTitle: String?`, `ogImagePath: String?`, `faviconPath: String?` directly to ClipboardItem. These are simple optional String fields -- safe migration.

**Warning signs:**
- The app crashes on launch for existing users but works fine on fresh installs (migration failure).
- Existing labels show no color or default to gray after upgrade (color field migration issue).
- Test suite passes in CI (fresh database) but the app breaks on a developer's machine with existing data.

**Detection phase:** Must be validated at the END of v1.1 development, before any release. Build a migration test that opens a v1.0 database with the v1.1 schema.

**Confidence:** HIGH -- SwiftData migration behavior is well-documented for simple cases. The "all new fields must be optional" rule is a hard requirement documented by Apple.

---

## Moderate Pitfalls

Mistakes that cause delays, technical debt, or degraded UX but are recoverable without rewrites.

### Pitfall 6: Color Detection Regex is Too Greedy or Too Narrow

**What goes wrong:**
Color value detection (hex, rgb, hsl) uses regex patterns. Common over/under matching:
1. **Too greedy:** The pattern `#[0-9a-fA-F]{3,8}` matches git commit hashes (`#a1b2c3d`), hex-encoded IDs, and CSS hex references that are not standalone color values. A commit message like "fixed in #abc123" gets a color swatch for a brownish color.
2. **Too narrow:** Only matching `#RRGGBB` misses `#RGB` shorthand (`#fff`), `#RRGGBBAA` (8-digit with alpha), `rgb(255, 128, 0)`, `rgba(255, 128, 0, 0.5)`, `hsl(180, 50%, 50%)`, and CSS named colors.
3. **Matching colors inside larger text.** The string `"background-color: #ff0000; font-size: 14px;"` contains a color, but should the entire CSS line be treated as a "color item"? Or should the swatch just appear inline?

**Why it happens:**
Color formats are diverse. Developers implement the simplest case (#RRGGBB) and ship it. Users copy colors from Figma (hex), CSS (rgb/hsl), Sketch (hex with alpha), and design tools (various formats).

**Specific risk in Pastel's architecture:**
Like code detection, color detection should NOT change the item's `contentType`. A text item containing a color value should remain `.text` with an additional visual enrichment (swatch). If color detection creates a separate `ContentType.color`, the classification logic in `classifyContent()` becomes fragile -- what if text contains both a URL and a color value?

**Prevention:**
- **Color detection is a display enrichment, not a content type.** Add `detectedColor: String?` (the normalized hex value) to ClipboardItem. The card view checks this field and optionally renders a swatch.
- **Only detect colors when the entire clipboard content IS a color value** (with optional whitespace trimming). Do not scan for colors embedded in larger text. If the user copies `#ff5733`, show a swatch. If they copy `background: #ff5733;`, it is a text item (not a color item).
- **Support the common formats:**
  - `#RGB` (3 hex digits)
  - `#RRGGBB` (6 hex digits)
  - `#RRGGBBAA` (8 hex digits)
  - `rgb(R, G, B)` with values 0-255
  - `rgba(R, G, B, A)` with A as 0-1 or 0%-100%
  - `hsl(H, S%, L%)` and `hsla(H, S%, L%, A)`
- **Validate the match.** After regex extraction, verify the values are in valid ranges (R/G/B: 0-255, H: 0-360, S/L: 0-100%). Reject matches that fail validation.
- **Normalize to hex.** Store the detected color as a normalized hex string (e.g., `#FF5733FF`) regardless of the input format. This makes swatch rendering consistent.

**Warning signs:**
- Git commit SHAs show color swatches in the panel.
- CSS code blocks have color swatches on every line.
- `rgb(300, 400, 500)` out-of-range values render as a swatch (validation failure).

**Detection phase:** Address during color detection implementation. Build a test suite with edge cases: git hashes, CSS blocks, valid/invalid color strings, all supported formats.

**Confidence:** HIGH -- color regex pitfalls are extensively documented in web development contexts (CSS parsers, design tool plugins).

---

### Pitfall 7: Emoji in Labels Breaks Layout or SwiftData Storage

**What goes wrong:**
Adding emoji support to labels (replacing the color dot with an emoji) introduces Unicode complexity:
1. **Multi-codepoint emoji break `String.count`.** The emoji "family" (e.g., various skin tone/gender combinations) can be 7+ Unicode scalars but `String.count` returns 1. If you truncate or validate by character count, behavior is inconsistent.
2. **Emoji rendering width varies.** A flag emoji renders wider than a single letter. A country flag (e.g., flag emoji) renders as two characters on some systems. If the label chip has a fixed-width slot for the emoji, some emoji overflow and clip.
3. **SwiftData stores emoji fine as UTF-8 String**, but if a `Character` type is used instead of `String`, SwiftData may have issues. `Character` is not a native SQLite type.
4. **Emoji picker integration.** macOS has a built-in emoji picker (Ctrl+Cmd+Space or Edit > Emoji & Symbols), but activating it from a non-activating panel (NSPanel) is unreliable. The picker may not appear, or it may appear behind the panel.
5. **Empty string vs nil.** When a label has no emoji, should the field be `nil` or `""` (empty string)? This affects the conditional rendering: "show emoji if set, otherwise show color dot."

**Why it happens:**
Emoji seems simple -- it is just a string. But Unicode emoji are complex, and SwiftUI rendering of emoji has edge cases on macOS that do not appear on iOS.

**Specific risk in Pastel's architecture:**
Labels currently use `colorName: String` for the color dot. The v1.1 plan says "emoji replaces color dot when set." The `LabelRow` in `LabelSettingsView` uses a `@Bindable` pattern for inline editing. Adding an emoji field and picker must work within this pattern, AND within the chip rendering in `ChipBarView`.

**Prevention:**
- **Store emoji as `String?` (not `Character?`).** Use `var emoji: String? = nil` on the Label model. String is SQLite-friendly and SwiftData handles it cleanly. Validate that the emoji field contains at most one grapheme cluster (one "visual" emoji) if needed, using `emoji.count == 1`.
- **Use `nil` for "no emoji", not empty string.** The rendering logic becomes `if let emoji = label.emoji { Text(emoji) } else { Circle().fill(color) }`. Clear and unambiguous.
- **Fixed-width emoji rendering.** In chip views, give the emoji slot a fixed frame (e.g., `frame(width: 20, height: 20)`) and use `.lineLimit(1)`. This handles varying emoji widths gracefully.
- **Do not build a custom emoji picker.** Use a simple text field where the user can type or paste an emoji. The macOS system emoji picker (Ctrl+Cmd+Space) works in text fields. This avoids the complexity of building a custom picker UI.
- **Alternatively, provide a curated emoji grid.** Show 20-30 common emoji (smile, star, fire, heart, folder, etc.) in a grid popover. This is simpler than a full picker and ensures consistent rendering.

**Warning signs:**
- Labels with flag emoji overflow their chip bounds.
- The emoji picker does not appear when triggered from the settings window (focus issue with NSPanel).
- Labels with emoji display empty squares on older macOS versions (emoji not in the system font).

**Detection phase:** Address during label emoji implementation. Test with diverse emoji: simple (smile), compound (family), flags, and skin-tone variants.

**Confidence:** MEDIUM -- emoji rendering in SwiftUI on macOS is generally reliable but edge cases exist. SwiftData String storage for emoji is standard and reliable.

---

### Pitfall 8: URL Metadata Fetch Fires for Every URL Re-copy, Wasting Bandwidth

**What goes wrong:**
The current deduplication in `ClipboardMonitor` checks the content hash of the most recent item. If the user copies the same URL twice with different items in between (non-consecutive), a new ClipboardItem is created (the `@Attribute(.unique)` on contentHash prevents true duplicates, but the rollback+skip means the item is not stored again). However, if the user copies the same URL and a new item IS created (perhaps the URL string differs slightly due to tracking parameters), a metadata fetch fires again for the same page.

Additionally, the user may copy URLs rapidly while browsing. If each copy triggers an immediate fetch, there is a burst of network requests that mostly duplicate each other or fetch pages the user will never look at again.

**Why it happens:**
The fetch-on-copy pattern seems correct ("enrich the card as soon as possible") but does not account for bursty copy behavior or redundant fetches.

**Prevention:**
- **Deduplicate fetches by URL hostname + path** (strip query parameters and fragments). If a fetch for the same normalized URL completed in the last 24 hours, reuse the cached metadata instead of fetching again.
- **Debounce fetches.** After a URL is captured, wait 1-2 seconds before initiating the fetch. If the user copies another URL within that window, cancel the previous fetch and start a new one for the latest URL. This handles the "rapid copy while browsing" pattern.
- **Limit total concurrent fetches** to 2. Queue additional fetches. If the queue exceeds 10, drop the oldest unfetched URLs (they are likely already scrolled past).
- **Cache metadata independently.** Consider a simple dictionary cache `[normalizedURL: (title, faviconPath, ogImagePath)]` persisted to disk (or as a separate SwiftData model). When a URL is copied, check the cache before fetching. This also handles the case where the user copies the same URL days later.

**Warning signs:**
- Network activity spikes when the user copies multiple URLs quickly.
- The same OG image is downloaded and stored multiple times for the same URL.
- Console shows many concurrent URLSession tasks.

**Detection phase:** Address during URL metadata fetching implementation, specifically in the fetch scheduling logic.

**Confidence:** MEDIUM -- fetch deduplication and debouncing are standard patterns, but the specific interaction with Pastel's copy pipeline needs testing.

---

### Pitfall 9: Highlighted Code Preview Recomputed on Every Scroll

**What goes wrong:**
SwiftUI's `LazyVStack`/`LazyHStack` creates and destroys views as they scroll in and out of the visible area. If the syntax highlighting result is not cached, each time a code card scrolls into view, the highlighting computation runs again. This causes:
1. **Visible delay** -- the card appears with plain text, then flashes to highlighted text (100-300ms later).
2. **CPU waste** -- the same content is highlighted repeatedly.
3. **Scroll jank** -- if highlighting is triggered synchronously in the view body, each code card causes a frame drop during scrolling.

**Why it happens:**
Developers implement highlighting inside the view (e.g., in a `.task` modifier) without caching the result. SwiftUI's view lifecycle means `.task` runs every time the view appears, and the view appears every time it scrolls into the visible area.

**Specific risk in Pastel's architecture:**
`FilteredCardListView` uses `LazyVStack` with `ForEach(Array(items.enumerated()), ...)`. Each `ClipboardCardView` is recreated when it scrolls into view. If highlighting is done inside the card view, it runs every time the card appears.

**Prevention:**
- **Cache highlighted output on the model.** Add a transient (non-persisted) cache: `@Transient var highlightedPreview: AttributedString?` on ClipboardItem. Compute highlighting once, store in this property. On subsequent renders, use the cached value.
- **Note: `@Transient` means the property is not persisted to SwiftData.** It exists only in memory for the current app session. This is correct for cached renders -- they can be recomputed if needed.
- **Alternative: Use a separate in-memory cache.** A `[String: AttributedString]` dictionary keyed by content hash. This avoids modifying the SwiftData model. The cache lives in a service object injected via SwiftUI environment.
- **Prefetch on capture.** When a new code item is captured and the language is detected, immediately queue a background highlighting task. By the time the user opens the panel, the highlight is already cached.
- **Avoid `.task` for highlighting.** Use `.task(id: item.contentHash)` so it only runs once per unique content. But still cache the result to survive view recreation.

**Warning signs:**
- Code cards flash from plain text to highlighted on every scroll.
- CPU usage spikes during panel scrolling.
- Instruments shows repeated calls to the highlighting engine for the same content.

**Detection phase:** Address during syntax highlighting card rendering. Build the caching layer first, then integrate the highlighting library.

**Confidence:** HIGH -- LazyVStack view lifecycle behavior and the need for caching is well-documented in SwiftUI.

---

### Pitfall 10: Cmd+1-9 Paste Targets Wrong Item After Search/Filter

**What goes wrong:**
Cmd+1-9 is intended to paste the Nth most recent item. But if the user has an active search query or label filter, the visible list is a filtered subset. The question becomes: does Cmd+1 paste the 1st item in the FILTERED list or the 1st item in the UNFILTERED history?

If Cmd+1-9 always maps to the unfiltered list:
- The user filters by label "Work", sees 3 items. Presses Cmd+1. Gets a completely different item from the unfiltered list. Confusion and data loss (pasted wrong content into the target app).

If Cmd+1-9 maps to the filtered list:
- The user switches filters. The same Cmd+N number now refers to a different item. Inconsistent behavior.

**Why it happens:**
The mapping between "position number" and "item" seems obvious until filtering is introduced. Most implementations do not consider this interaction.

**Specific risk in Pastel's architecture:**
`FilteredCardListView` receives items from `@Query` with a predicate based on `searchText` and `selectedLabelID`. The visible items change based on filters. The number badges (1-9) must reflect what the user sees, but the paste-back mechanism (`PasteService.paste`) needs the actual `ClipboardItem` reference.

**Prevention:**
- **Always map Cmd+1-9 to the VISIBLE list.** Whatever items are currently displayed in the panel (filtered or not), Cmd+1 pastes the first visible item, Cmd+2 the second, etc. This matches what the user sees.
- **Update number badges when filters change.** The badges "1" through "9" are overlaid on the first 9 visible items. When the filter changes, the badges shift to the new first 9.
- **When the panel is closed and hotkeys are panel-open-only (Mode A), this is a non-issue.** The user must open the panel, see the items, and then press Cmd+N. The visible list is always what they see.
- **If implementing global Cmd+1-9 (Mode B -- not recommended), always paste from the unfiltered list.** The user cannot see the panel, so there is no visual mismatch. Cmd+1 always means "most recent item in history." But this mode is not recommended due to hotkey conflicts (Pitfall 4).

**Warning signs:**
- User filters by a label, presses Cmd+1, and gets an item not visible in the panel.
- Number badges do not update when search text changes.

**Detection phase:** Address during Cmd+1-9 implementation. Decide the mapping rule (visible vs unfiltered) before writing any code.

**Confidence:** HIGH -- this is a fundamental UX design decision, not a technical uncertainty.

---

## Minor Pitfalls

Mistakes that cause annoyance but are straightforward to fix.

### Pitfall 11: Expanded Color Palette Breaks Existing Labels

**What goes wrong:**
v1.0 has 8 label colors (`LabelColor` enum: red, orange, yellow, green, blue, purple, pink, gray). v1.1 adds more colors (e.g., teal, indigo, brown, mint). If the new colors are added to the enum but existing labels reference old `colorName` values, there is no issue. However, if the enum is restructured (e.g., changing raw values or reordering), existing labels may lose their color association.

Additionally, if the settings UI uses `LabelColor.allCases` to render the color picker grid, the grid layout changes with more colors. The 8-color grid that fit in one row may now need two rows or a different layout.

**Prevention:**
- **Only add new cases to `LabelColor`. Never remove, rename, or reorder existing cases.** Raw values are strings stored in the database -- they must remain stable.
- **Test that existing labels with `colorName = "blue"` still resolve after adding new cases.** The `LabelColor(rawValue:)` initializer must continue to work for all existing values.
- **Adjust the color picker layout** in `LabelRow` to handle 12+ colors. Consider a 4-column grid instead of a single-row menu.

**Warning signs:**
- Existing labels show as gray after upgrade (color resolution failed).
- Color picker grid is too wide for the settings window.

**Detection phase:** Address during label color palette expansion. Quick test: create labels with each existing color, add new colors, verify existing labels still show correctly.

**Confidence:** HIGH -- enum expansion is straightforward; the risk is only if someone changes existing raw values.

---

### Pitfall 12: OG Image Fetching for Non-HTML URLs

**What goes wrong:**
Not all URLs point to HTML pages with Open Graph tags. The metadata fetcher receives:
1. **Direct image URLs** (`https://example.com/photo.png`) -- fetching this returns raw image data, not HTML. Parsing it as HTML produces nothing.
2. **PDF URLs** (`https://example.com/document.pdf`) -- returns PDF binary data.
3. **API endpoints** (`https://api.example.com/v1/users`) -- returns JSON, not HTML.
4. **Redirect chains** -- URL redirects through multiple 301/302 hops before landing on the final page. The initial fetch may timeout during redirects.
5. **Login walls** -- the page returns a login form instead of the actual content. The OG tags on the login page are generic ("Sign In | Example.com").

**Prevention:**
- **Check Content-Type header before parsing.** Only parse `text/html` responses for OG tags. For `image/*` responses, use the URL itself as the preview. For other types, skip metadata fetching.
- **Follow redirects up to a limit (3 hops).** URLSession follows redirects by default, but set a maximum to avoid redirect loops.
- **Parse only the `<head>` section.** Do not download the entire HTML body. Read the first 16KB of the response -- OG tags are always in `<head>`, which is near the top of the document. This saves bandwidth and avoids downloading multi-megabyte pages.
- **Handle common meta patterns:** Open Graph (`og:title`, `og:image`, `og:description`), Twitter Cards (`twitter:title`, `twitter:image`), and standard HTML (`<title>`, `<link rel="icon">`).

**Warning signs:**
- Image URLs show a blank preview instead of the image.
- API endpoints show "Sign In" as the title.
- Metadata fetch downloads the entire page (multi-MB response bodies).

**Detection phase:** Address during URL metadata parser implementation.

**Confidence:** MEDIUM -- OG parsing patterns are well-known from web scraping, but the specific interaction with various URL types needs testing.

---

### Pitfall 13: Number Badges Overlap with Label Chips on Cards

**What goes wrong:**
Adding Cmd+1-9 number badges to the first 9 cards introduces a visual element that must coexist with the existing card layout: source app icon, timestamp, content preview, and (for labeled items) the label chip. If the badge is placed in a corner, it may overlap with:
- The source app icon (top-left).
- The timestamp (top-right).
- The content preview area (center).
- The label indicator (if shown on the card).

In horizontal mode (top/bottom edges), the fixed 260pt card width means even less space.

**Prevention:**
- **Place the badge in a consistent position that does not conflict.** Top-left corner over the source app icon area, or as a subtle inline number before the content preview.
- **Only show badges when the panel is open and Cmd+1-9 is active.** Do not always show numbers -- it adds clutter. Show them on hover of the number key area, or always show for the first 9 items.
- **Use small, semi-transparent circular badges** (12-14pt) that do not dominate the card visual hierarchy.
- **Test in both vertical and horizontal modes.** The badge position must work in both layouts.

**Warning signs:**
- Badges overlap timestamps in horizontal mode.
- Badges are not visible against certain card backgrounds (dark badge on dark card).

**Detection phase:** Address during card UI update for number badges.

**Confidence:** HIGH -- layout overlaps are straightforward to identify during development.

---

## Integration Pitfalls with Existing v1.0 System

Mistakes specific to adding v1.1 features alongside the existing, working v1.0 architecture.

### Integration Pitfall A: New Optional Fields on ClipboardItem Break Existing @Query Predicates

**What goes wrong:**
The current `FilteredCardListView` uses `#Predicate<ClipboardItem>` with `textContent?.localizedStandardContains(search)`. Adding new fields (like `ogTitle`, `detectedLanguage`) means search should potentially also match against these new fields. If the predicate is updated to include `ogTitle?.localizedStandardContains(search)` but `ogTitle` is nil for existing items, the predicate must handle the optional correctly.

The existing code already handles this with the `?.method() == true` pattern (documented in quick-003 decision). But new developers adding fields may not follow this pattern, causing predicate crashes.

**Prevention:**
- **Follow the established optional pattern:** `item.ogTitle?.localizedStandardContains(search) == true`. Never use `!` or `??` in SwiftData predicates (documented in STATE.md decisions).
- **Update the search predicate to include new searchable fields** (ogTitle) but only after the field is added to the model and migration is tested.
- **The `.id()` on FilteredCardListView must include all inputs** (documented in quick-003). If new filter dimensions are added, update the `.id()`.

**Warning signs:**
- Search crashes when a new field is included in the predicate but some items have nil values.
- Search does not match URL titles (new field not included in predicate).

**Confidence:** HIGH -- the codebase already has patterns and documented decisions for handling this.

---

### Integration Pitfall B: Background Metadata Fetching Updates SwiftData from Wrong Thread

**What goes wrong:**
URL metadata fetching runs on a background thread (URLSession completion handler). When the fetch completes, the code attempts to update the ClipboardItem's `ogTitle` and `ogImagePath` fields. But the `ModelContext` used by `ClipboardMonitor` is `@MainActor` isolated. Updating SwiftData from a background thread causes:
1. Silent data corruption (writes not visible to the main context).
2. Crashes with "ModelContext is not thread-safe" assertions.
3. The UI does not update even though the model was "updated" on the background thread.

**Why it happens:**
URLSession completionHandlers run on background queues by default. Developers write `item.ogTitle = fetchedTitle` in the completion handler without dispatching to the main thread.

**Specific risk in Pastel's architecture:**
The `ClipboardMonitor` is `@MainActor @Observable` and uses a `ModelContext` that was created on the main thread. All SwiftData writes must happen on the main actor. The existing image capture already handles this correctly (see `processImageContent` which uses `@MainActor @Sendable` completion handler). URL metadata fetching must follow the same pattern.

**Prevention:**
- **Dispatch all SwiftData updates to `@MainActor`.** Use `Task { @MainActor in ... }` or `DispatchQueue.main.async { ... }` in the URLSession completion handler.
- **Follow the existing pattern** from `ImageStorageService.saveImage(data:completion:)` which takes a `@MainActor @Sendable` completion handler.
- **Alternatively, use Swift concurrency with `async/await` URLSession API** and ensure the SwiftData update happens in a `@MainActor` context:
  ```swift
  Task.detached {
      let metadata = await MetadataFetcher.fetch(url: urlString)
      await MainActor.run {
          item.ogTitle = metadata.title
          try? modelContext.save()
      }
  }
  ```

**Warning signs:**
- URL cards never show metadata even though fetch logs show success (background thread update invisible to main context).
- Crash with "ModelContext accessed from wrong thread/actor."

**Confidence:** HIGH -- Swift concurrency and SwiftData threading rules are well-documented. The existing codebase already demonstrates the correct pattern.

---

### Integration Pitfall C: Syntax Highlighting Library Adds Significant Binary Size

**What goes wrong:**
Highlightr bundles highlight.js JavaScript files for ~190 languages. Even though most users only copy code in 3-5 languages, the entire highlight.js bundle is included in the app binary. This can add 2-5 MB to the app size.

For Splash (pure Swift), the binary size impact is minimal (~200KB), but it only supports Swift syntax.

**Prevention:**
- **If using Highlightr:** Check if the library supports selective language inclusion. Some highlight.js builds allow choosing only specific languages. If not, accept the size increase.
- **If using Splash:** Accept the limitation to Swift-only highlighting. For a macOS developer tool, this may be sufficient.
- **Consider a hybrid approach:** Use Splash for Swift, and a lightweight custom highlighter (regex-based token coloring) for 4-5 other common languages (Python, JavaScript, HTML, CSS, JSON). This avoids the full highlight.js bundle while covering the most common languages.
- **Profile the actual size impact** during implementation. If 2-5 MB is acceptable for the app, Highlightr is the easiest path. For a clipboard manager, binary size is unlikely to be a user concern.

**Warning signs:**
- App binary size jumps from ~5MB to ~10MB after adding highlighting library.
- If distributing directly (not App Store), this is less of a concern. If App Store, size impacts download/update speed.

**Confidence:** MEDIUM -- Highlightr's bundle size is based on training knowledge. The actual impact should be measured during implementation.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation | Severity |
|---|---|---|---|
| Code detection heuristic | False positives on non-code text (Pitfall 1) | Use multi-signal detection, high confidence threshold, keep as display enrichment not content type | HIGH |
| Syntax highlighting integration | Main thread blocking, JSContext init cost (Pitfall 2) | Async highlighting with caching, truncate input, single instance init at startup | HIGH |
| URL metadata fetching | Blocking clipboard capture, private URL leaks (Pitfall 3) | Decouple from capture pipeline, background fetch with timeout, skip private IPs | HIGH |
| Cmd+1-9 hotkeys | Global conflict with browser/app shortcuts (Pitfall 4) | Panel-open only via local event monitor, not global Carbon registration | CRITICAL |
| SwiftData schema changes | Migration failure for existing users (Pitfall 5) | All new fields optional with nil default, test migration from v1.0 database | HIGH |
| Color detection regex | Matches git hashes, non-color hex strings (Pitfall 6) | Only detect when entire content is a color value, validate ranges | MEDIUM |
| Label emoji storage | Unicode complexity, fixed-width layout issues (Pitfall 7) | Store as String?, fixed frame for emoji slot, curated picker | MEDIUM |
| URL metadata deduplication | Redundant fetches for same URL (Pitfall 8) | Debounce, deduplicate by normalized URL, cache results | MEDIUM |
| Highlighting cache invalidation | Recomputed on every scroll in LazyVStack (Pitfall 9) | Cache AttributedString by content hash, prefetch on capture | MEDIUM |
| Number-to-item mapping with filters | Cmd+N pastes wrong item when filtered (Pitfall 10) | Always map to visible (filtered) list, update badges on filter change | MEDIUM |

## Recovery Strategies

If pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| Code detection false positives (1) | LOW | Tighten heuristic, reprocess existing items. No data loss since code is a display enrichment, not a content type change. |
| Highlighting crashes (2) | LOW | Wrap in try-catch, fall back to plain text. No data loss. Fix crash cause and re-ship. |
| Metadata fetching blocks capture (3) | MEDIUM | Refactor to decouple fetch from capture. Existing items unaffected. New items need metadata backfill. |
| Global hotkey conflicts (4) | MEDIUM | Switch from global to panel-open-only. Requires rewriting hotkey registration but no data loss. |
| SwiftData migration failure (5) | HIGH | If shipped to users with a broken migration, recovery requires providing a migration fix or database reset tool. Test before shipping. |
| Color regex too greedy (6) | LOW | Tighten regex. Reprocess existing items. Only display is affected. |
| Emoji layout breakage (7) | LOW | Fix frame sizing. No data loss. |
| URL fetch deduplication (8) | LOW | Add cache/dedup layer. Delete redundant cached files. |
| Highlighting recomputation (9) | LOW | Add caching layer. No data loss. Performance improves immediately. |
| Wrong item paste with filters (10) | LOW | Fix mapping to use visible list. No data loss (wrong content may have been pasted, but clipboard history is intact). |

---

## Sources

- Training knowledge of macOS APIs: NSPasteboard, SwiftData migration, NSPanel, Carbon hotkeys, URLSession (HIGH confidence -- these are mature, stable Apple APIs)
- Training knowledge of Highlightr (highlight.js wrapper for Swift): JSContext initialization patterns, bundle size (MEDIUM confidence -- verify current version and performance characteristics)
- Training knowledge of Splash (JohnSundell): Pure Swift syntax highlighting, Swift-only language support (MEDIUM confidence -- verify current maintenance status)
- Training knowledge of SwiftUI LazyVStack lifecycle, view recreation patterns (HIGH confidence -- well-documented by Apple)
- Training knowledge of Open Graph protocol and metadata fetching patterns (HIGH confidence -- OG is a stable web standard)
- Training knowledge of Unicode emoji handling in Swift (HIGH confidence -- Swift's String/Character model is well-documented)
- Patterns from existing Pastel codebase: ClipboardMonitor, PasteService, PanelController, FilteredCardListView (HIGH confidence -- direct code inspection)

**Note on confidence:** WebSearch and WebFetch were unavailable during this research session. All findings are based on training knowledge of well-established macOS APIs, common integration patterns, and direct analysis of the existing Pastel codebase. Library-specific claims (Highlightr performance, Splash capabilities) should be verified against current documentation before implementation. The core pitfalls (hotkey conflicts, migration failures, threading issues, false positive detection) are based on fundamental patterns that are highly unlikely to have changed.

---
*Pitfalls research for: Pastel v1.1 Rich Content & Enhanced Paste*
*Researched: 2026-02-06*
