# Project Research Summary

**Project:** Pastel v1.1 -- Rich Content & Enhanced Paste
**Domain:** Native macOS Clipboard Manager (enrichment layer on shipped v1.0)
**Researched:** 2026-02-07
**Confidence:** MEDIUM-HIGH

## Executive Summary

Pastel v1.1 adds five feature areas to a stable v1.0 foundation: code snippet detection with syntax highlighting, color value detection with swatches, URL preview cards with auto-fetched Open Graph metadata, Cmd+1-9 direct paste hotkeys, and label emoji with an expanded color palette. All four research streams agree on the core approach: v1.1 is an enrichment layer that adds new optional metadata fields to the existing ClipboardItem model and introduces three new detection/fetch services, with no changes to the existing content ingestion pipeline's control flow. The v1.0 architecture is well-suited for these additions -- ClipboardMonitor is the single ingestion point, ContentType drives card routing, and SwiftData lightweight migration handles new optional fields cleanly.

The recommended approach minimizes new dependencies. Only one new third-party library is needed: Highlightr for syntax highlighting (190+ language grammars with auto-detection). Everything else uses Apple frameworks (LinkPresentation for URL metadata), the already-installed KeyboardShortcuts library (for Cmd+1-9 hotkeys), or pure Swift (color detection regex, emoji input). There is a key disagreement between researchers on two topics -- whether to add `.code`/`.color` as new ContentType enum cases vs. treating them as display enrichments on `.text`, and whether to use Highlightr vs. a custom regex-based highlighter. These are resolved below with clear recommendations.

The three highest risks are: (1) Cmd+1-9 global hotkey conflicts with browsers and other apps -- this is the single decision most likely to cause user frustration if handled incorrectly; (2) URL metadata fetching introducing network I/O into a previously offline capture pipeline -- must be fully decoupled from clipboard capture; (3) SwiftData schema migration when adding new fields -- all fields must be optional with nil defaults, tested against a v1.0 database before shipping. The label emoji and color detection features are low risk and should be built first.

## Key Findings

### Recommended Stack

v1.1 requires only one new third-party dependency. The existing stack (Swift 6, SwiftUI+AppKit hybrid, SwiftData, KeyboardShortcuts 2.4.0, LaunchAtLogin-Modern 1.1.0) is unchanged and validated.

**New and reused technologies:**

- **Highlightr** (`from: "2.2.0"`, VERIFY): Syntax highlighting via highlight.js -- 190+ languages, auto-detection, dark themes. The only new SPM dependency. MEDIUM confidence (verify current version, Swift 6 compatibility, maintenance status on GitHub before adding).
- **LinkPresentation (LPMetadataProvider)**: Apple first-party framework for URL metadata extraction -- title, favicon, og:image. Ships with macOS 10.15+, zero dependencies. HIGH confidence.
- **KeyboardShortcuts (existing, v2.4.0)**: Already installed. Supports `.one` through `.nine` key constants, `Shortcut` construction, `enable/disable` API. Verified against checked-out source. HIGH confidence.
- **Pure Swift regex**: Color detection (hex/rgb/hsl patterns) and code detection heuristic. No library needed. HIGH confidence.
- **SwiftUI native colors**: `.teal`, `.indigo`, `.brown`, `.mint` available on macOS 14+ for expanded label palette. HIGH confidence.

**Stack items explicitly rejected:**
- Splash (Swift-only highlighting -- insufficient for a clipboard manager that captures all languages)
- TreeSitter (heavyweight grammar binaries, overkill for preview cards)
- WKWebView for code rendering (performance disaster in scrolling lists)
- SwiftSoup/Kanna for HTML parsing (LPMetadataProvider handles this)
- Raw Carbon RegisterEventHotKey (duplicates KeyboardShortcuts, more error-prone)

### Expected Features

**Must have (table stakes):**
- Monospaced, syntax-highlighted code previews with auto language detection
- Color swatch rendering for hex and rgb values alongside original text
- URL cards showing page title and domain (fetched from page metadata)
- Non-blocking URL metadata fetch with graceful fallback to plain URL card
- Cmd+Shift+1-9 hotkeys to paste Nth item without opening panel
- Enable/disable toggle for quick paste hotkeys in Settings
- Expanded label color palette (8 to 12 colors)
- Optional emoji per label replacing color dot when set
- Backward-compatible SwiftData migration for all model changes

**Should have (differentiators):**
- Language badge on code cards ("Swift", "Python")
- Favicon display on URL cards
- og:image header on URL cards (progressive enhancement)
- Position number badges (1-9) on panel cards when hotkeys active
- Alternate color format display (copy hex, see rgb and vice versa)
- System emoji picker access via Ctrl+Cmd+Space in label settings

**Defer (v2+):**
- Full webpage screenshot thumbnails
- TreeSitter-grade syntax accuracy
- User-selectable language per code item
- Custom hex color input for labels
- Per-slot custom hotkey assignment (snippet/template territory)
- Configurable modifier key for quick paste hotkeys
- HUD overlay showing paste preview near cursor

### Architecture Approach

The v1.0 architecture has clean separation and well-defined extension points. v1.1 adds three new services (CodeDetectionService, ColorDetectionService, URLMetadataService), two new card views (CodeCardView, ColorCardView/ColorSwatchView), and enhances the existing URLCardView. All detection runs at capture time in ClipboardMonitor, and results are stored as optional fields on ClipboardItem. Card routing in ClipboardCardView dispatches to type-specific subviews based on ContentType and the presence of new metadata fields.

**New services:**
1. **CodeDetectionService** -- Heuristic code detection (shebang, keywords, structural patterns, indentation). Pure function, no dependencies.
2. **ColorDetectionService** -- Regex-based color parsing (hex/rgb/hsl). Pure function, no dependencies.
3. **URLMetadataService** -- Async LPMetadataProvider fetch with 5s timeout. Fire-and-forget after item insertion. Disk caching for favicon/og:image via existing ImageStorageService.

**New views:**
1. **CodeCardView** -- Syntax-highlighted preview via Highlightr, language badge, monospaced font.
2. **ColorSwatchView** -- Rounded rectangle swatch + original text value.

**Model additions (all optional, nil default):**
- ClipboardItem: `detectedLanguage`, `detectedColorHex`, `urlTitle`, `urlFaviconPath`, `urlPreviewImagePath`, `urlMetadataFetched`
- Label: `emoji`
- LabelColor enum: 4 new cases (teal, indigo, brown, mint)
- ContentType enum: 2 new cases (.code, .color)

### Critical Pitfalls

1. **Cmd+1-9 global hotkey conflicts (CRITICAL)** -- Cmd+1-9 are used by Safari, Chrome, Finder, Terminal, and most editors for tab/view switching. Registering them globally via Carbon breaks basic functionality in those apps. **Prevention:** Use Cmd+Shift+1-9 as the default modifier. Provide a Settings toggle to enable/disable.

2. **URL metadata fetching must be decoupled from capture (HIGH)** -- The clipboard capture pipeline is synchronous and offline. Network I/O must never block it. **Prevention:** Insert ClipboardItem immediately, fire async metadata fetch afterward. Update model when metadata arrives. Skip private/local URLs. 5-second timeout. Rate limit to 2-3 concurrent fetches.

3. **SwiftData migration must use optional fields only (HIGH)** -- Adding non-optional fields without defaults crashes on existing databases. **Prevention:** Every new field is `String?` or `Bool` with default. Test migration against a v1.0 database before shipping.

4. **Code detection false positives (HIGH)** -- Naive heuristics misclassify URLs, config text, and prose as code. **Prevention:** Multi-signal scoring with high threshold (3+), minimum line count, negative signals for natural language. Test with diverse non-code clipboard content.

5. **Syntax highlighting performance (MEDIUM)** -- Highlightr uses JavaScriptCore with ~100ms cold start. **Prevention:** Initialize once at app launch, highlight asynchronously, cache results by content hash. Truncate input to ~2000 chars for preview cards. Never highlight synchronously in view body.

## Key Disagreements Resolved

### ContentType Enum: New Cases vs. Display Enrichment

**STACK.md and FEATURES.md** recommend adding `.code` and `.color` cases to ContentType. **ARCHITECTURE.md and PITFALLS.md** recommend keeping these as display enrichments (optional metadata fields) on `.text` items, with no new enum cases.

**Resolution: Add `.code` and `.color` to ContentType.** ContentType is stored as a raw String and new enum cases are additive -- they do not break existing predicates. New items get the new types; existing items remain `.text`. The benefit is cleaner card routing (switch on type rather than checking nullable fields) and clearer semantics in the data model. The detection priority order (URL > color > code > text) prevents ambiguity. Ensure all existing `switch` statements on ContentType gain the new cases.

### Syntax Highlighting: Highlightr vs. Custom Regex

**STACK.md and FEATURES.md** recommend Highlightr for its 190+ language coverage and auto-detection. **ARCHITECTURE.md** recommends a custom regex-based highlighter to avoid the JavaScript dependency. **PITFALLS.md** notes Highlightr's JSContext overhead and suggests Splash as an alternative.

**Resolution: Use Highlightr.** A clipboard manager captures code from every language. A custom regex highlighter covering 5-10 languages provides a degraded experience for users copying Python, Ruby, SQL, YAML, or shell scripts. Highlightr's auto-detection is the key value -- it eliminates the need for language-specific detection heuristics. The ~2MB bundle size is negligible for a desktop app. The JSContext cold start (~100ms) is mitigated by initializing once at app launch. If Highlightr proves unmaintained or incompatible with Swift 6, fall back to the custom regex approach as a contingency.

### Hotkey Default Modifier

**STACK.md** recommends Cmd+1-9 defaulting to DISABLED. **FEATURES.md** recommends Ctrl+1-9 as default. **ARCHITECTURE.md** recommends Cmd+Shift+1-9. **PITFALLS.md** recommends panel-open-only via local event monitor.

**Resolution: Cmd+Shift+1-9, globally registered, enabled by default, with Settings toggle.** Cmd+Shift+1-9 conflicts with nothing in standard macOS apps. Global registration (not panel-open-only) provides the core value -- pasting without opening the panel. A Settings toggle allows users to disable if needed. This avoids the NSPanel local event monitor complexity flagged by the pitfalls researcher while keeping the feature accessible out of the box.

## Implications for Roadmap

Based on combined research, the five feature areas should be organized into 4 phases, ordered by dependency depth, risk level, and feature completeness.

### Phase 1: Data Model + Label Enhancements

**Rationale:** Schema changes must come first because every subsequent phase depends on the new model fields. Label enhancements are the lowest-risk feature and can ship alongside the schema changes to provide immediate visual value.

**Delivers:**
- New optional fields on ClipboardItem (detectedLanguage, detectedColorHex, urlTitle, urlFaviconPath, urlPreviewImagePath, urlMetadataFetched)
- New `.code` and `.color` ContentType cases
- New `emoji: String?` on Label model
- Expanded LabelColor enum (teal, indigo, brown, mint)
- Emoji-or-dot rendering in ChipBarView and context menu
- Emoji input in LabelSettingsView
- SwiftData migration validation against v1.0 database

**Features addressed:** Label emoji, expanded color palette
**Pitfalls addressed:** SwiftData migration (Pitfall 5), emoji storage/layout (Pitfall 7), color palette backward compatibility (Pitfall 11)

### Phase 2: Code + Color Detection and Card Views

**Rationale:** Code and color detection are pure-function services with no external dependencies (detection only -- highlighting is also included since it pairs directly with the code card). Building detection and card rendering together provides a complete "rich text cards" experience. Color detection is trivially simple; code detection needs careful threshold tuning.

**Delivers:**
- CodeDetectionService with multi-signal heuristic
- ColorDetectionService with hex/rgb/hsl regex parsing
- Detection wired into ClipboardMonitor.processPasteboardContent()
- CodeCardView with Highlightr syntax highlighting (singleton init, async caching)
- ColorSwatchView / ColorCardView
- Updated ClipboardCardView routing for .code and .color types
- Highlightr SPM dependency added to project.yml

**Features addressed:** Code snippet highlighting, color swatches, language badges
**Pitfalls addressed:** False positive detection (Pitfall 1), highlighting performance (Pitfall 2), scroll caching (Pitfall 9), regex greedy matching (Pitfall 6)
**Uses:** Highlightr (new SPM dependency)

### Phase 3: URL Preview Cards

**Rationale:** URL metadata fetching is the highest-risk feature due to network I/O, async complexity, and edge cases (private URLs, slow servers, non-HTML responses). Build it after the simpler detection features are stable. The existing URLCardView provides a working fallback.

**Delivers:**
- URLMetadataService with LPMetadataProvider
- Async fire-and-forget metadata fetch triggered after URL item insertion
- Enhanced URLCardView showing title + favicon + og:image when available
- Fallback to globe + URL text on fetch failure
- Favicon and og:image disk caching via ImageStorageService
- Image cleanup extension in RetentionService and clearAllHistory
- Skip logic for private/local URLs
- Settings toggle to disable URL fetching

**Features addressed:** URL preview cards, favicon display, og:image headers
**Pitfalls addressed:** Blocking capture pipeline (Pitfall 3), redundant fetches (Pitfall 8), non-HTML URLs (Pitfall 12), background thread SwiftData updates (Integration Pitfall B)
**Uses:** LinkPresentation framework (Apple, zero dependency)

### Phase 4: Quick Paste Hotkeys (Cmd+Shift+1-9)

**Rationale:** Functionally independent of the card enrichment features. Building it last means the paste pipeline is stable and all card types are rendering correctly. This phase needs Accessibility permission (already granted from v1.0) and careful testing of the hotkey-to-paste flow.

**Delivers:**
- 9 KeyboardShortcuts.Name definitions (quickPaste1-9, Cmd+Shift+1-9)
- quickPaste(index:) method on AppState
- pasteWithoutPanel flow in PasteService (writeToPasteboard + skip monitor + CGEvent)
- Settings toggle in GeneralSettingsView ("Quick Paste Shortcuts" section)
- Position number badges (1-9) on first 9 panel cards
- Correct mapping to visible (filtered) list when panel is open

**Features addressed:** Cmd+Shift+1-9 direct paste, number badges, settings toggle
**Pitfalls addressed:** Global hotkey conflicts (Pitfall 4), filter mapping confusion (Pitfall 10), number badge layout overlap (Pitfall 13)
**Uses:** KeyboardShortcuts (existing, v2.4.0)

### Phase Ordering Rationale

- **Phase 1 first** because every other phase adds fields to the models that Phase 1 defines. The label enhancements ride along as a low-risk quick win with immediate visual payoff.
- **Phase 2 second** because code and color detection are pure functions with no network dependency and can be unit tested in isolation. Highlightr is the only new library and should be validated early.
- **Phase 3 third** because URL metadata fetching introduces network I/O and async complexity. Building it after Phase 2 means the card rendering pipeline is already proven for the simpler cases.
- **Phase 4 last** because hotkeys are architecturally independent -- they bypass the panel entirely. They also benefit from all card types being complete (the number badges make more sense when cards show rich content).
- This ordering matches risk escalation: Phase 1 is near-zero risk, Phase 2 is low risk with one library to validate, Phase 3 is medium risk with network I/O, Phase 4 is medium risk with global hotkey conflict surface.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 2:** Verify Highlightr's current version, Swift 6 compatibility, and macOS 14 support on GitHub before implementation. Test `highlightAuto()` with diverse language samples. If Highlightr is unmaintained or broken, fall back to custom regex highlighter.
- **Phase 3:** Test LPMetadataProvider with 10+ diverse URLs (news sites, GitHub, social media, API endpoints, redirect chains) to calibrate timeout, error handling, and edge cases. Verify Content-Type header checking for non-HTML responses.

**Phases with standard patterns (skip deep research):**
- **Phase 1:** SwiftData optional field addition and enum expansion are well-documented patterns. Just test migration.
- **Phase 4:** KeyboardShortcuts API is verified against the checked-out source code. Registration, enable/disable, and handler patterns are confirmed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | All Apple frameworks are HIGH. Highlightr is MEDIUM (verify version and Swift 6 compat). Everything else is validated or zero-dependency. |
| Features | MEDIUM-HIGH | Feature scope is well-defined from PROJECT.md. Detection heuristics need tuning during implementation. URL metadata edge cases need real-world testing. |
| Architecture | HIGH | Based on direct source code analysis of all 40+ Pastel files. Integration points are concrete and verified against the codebase. |
| Pitfalls | HIGH | Pitfalls are based on well-understood patterns (hotkey conflicts, SwiftData migration, threading, regex). No novel risks. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Highlightr verification**: Current version, SPM target name, Swift 6 strict concurrency compatibility, and macOS 14 support must be checked on GitHub before adding the dependency. If unavailable or broken, the custom regex highlighter is the fallback (covers fewer languages but works).
- **LPMetadataProvider real-world behavior**: Rate limiting, behavior with paywalled sites, and non-HTML URLs need empirical testing. The manual URLSession+regex fallback is documented but should only be needed if LPMetadataProvider proves unreliable.
- **KeyboardShortcuts Cmd+Shift+1-9**: While `.one` through `.nine` key constants and modifier support are confirmed in the library source, the specific combination Cmd+Shift+1-9 should be tested for conflicts with any standard macOS system shortcut (none are expected, but verify).
- **SwiftData migration with 6+ new fields**: Adding multiple optional fields simultaneously should be safe for lightweight migration, but test on a populated v1.0 database to confirm. If it fails, fields may need to be added in stages across multiple schema versions.

## Sources

### Primary (HIGH confidence)
- Pastel v1.0 source code -- all 40+ Swift files inspected for integration points and architecture analysis
- KeyboardShortcuts v2.4.0 checked-out source -- Key.swift (.one-.nine), Shortcut constructor, enable/disable API, CarbonKeyboardShortcuts wrapping
- Package.resolved -- confirmed dependency versions (KeyboardShortcuts 2.4.0, LaunchAtLogin-Modern 1.1.0)
- Apple Developer Documentation (training knowledge) -- LPMetadataProvider, LinkPresentation, SwiftData migration, SwiftUI Color constants

### Secondary (MEDIUM confidence)
- Highlightr library (github.com/raspu/Highlightr) -- training knowledge of highlight.js wrapper, 190+ languages, auto-detection. Version and current maintenance need verification.
- Open Graph Protocol (ogp.me) -- stable web standard, unlikely to have changed
- PastePal and CopyLess 2 feature sets -- competitive reference for feature expectations

### Tertiary (LOW confidence)
- Highlightr Swift 6 compatibility -- unverified, needs testing
- LPMetadataProvider rate limiting behavior -- undocumented by Apple, needs empirical testing

---
*Research completed: 2026-02-07*
*Ready for roadmap: yes*
