# Project Research Summary

**Project:** Pastel
**Domain:** Native macOS Clipboard Manager
**Researched:** 2026-02-05
**Confidence:** MEDIUM-HIGH

## Executive Summary

Pastel is a native macOS clipboard manager with a screen-edge sliding panel interface. Based on research of established clipboard managers (Maccy, Clipy, Paste, PastePal), the recommended approach is a hybrid AppKit/SwiftUI architecture targeting macOS 14+ with Swift 6. The core technical pattern is well-established: timer-based NSPasteboard polling (0.5s intervals) for clipboard monitoring, NSPanel with non-activating configuration for the floating panel, and CGEvent-based Cmd+V simulation for paste-back.

The primary architectural decision is mandating AppKit NSPanel over pure SwiftUI windows. This is non-negotiable because paste-back functionality requires the panel to remain non-activating, which only NSPanel can provide. Pure SwiftUI windows steal focus and break the entire paste workflow. The recommended stack is Swift 6 + SwiftUI (for UI content) + AppKit bridges (for window management and system integration) + SwiftData (for persistence) + direct disk storage for images.

Key risks center on three areas: (1) NSPasteboard polling must be tuned correctly (0.5s interval) to avoid battery drain or missed clipboard changes, (2) NSPanel focus management must be configured perfectly or paste-back fails entirely, and (3) image storage must be disk-based from day one or memory/database bloat causes crashes at scale. These are all preventable with correct foundational architecture. The domain is well-documented with multiple open-source reference implementations, giving high confidence in the technical approach.

## Key Findings

### Recommended Stack

The macOS clipboard manager domain has converged on a standard technical stack built on Apple's native frameworks. Swift is the only sensible choice for native macOS development, with Swift 6 providing complete concurrency checking essential for background clipboard polling. SwiftUI handles UI content using modern declarative patterns, but AppKit integration is mandatory for window management (NSPanel), clipboard access (NSPasteboard), and paste simulation (CGEvent).

**Core technologies:**
- **Swift 6.0 + Xcode 16**: Native language with full concurrency checking for clipboard polling on background threads
- **SwiftUI (macOS 14+)**: Declarative UI framework for view content, MenuBarExtra for status bar presence
- **AppKit (bridged)**: Essential for NSPanel (non-activating floating window), NSPasteboard (clipboard access), and system integration
- **SwiftData (macOS 14+)**: Modern persistence with @Model macro, automatic SwiftUI integration via @Query, eliminates Core Data boilerplate
- **NSPasteboard + Timer polling**: Only reliable clipboard monitoring approach; poll changeCount every 0.5s (no notification API exists)
- **CGEvent API**: Simulate Cmd+V keystroke for paste-back; requires Accessibility permission
- **FileManager + disk storage**: Images stored as files in Application Support directory, database holds only file paths

**Critical version constraint:** macOS 14.0 (Sonoma) minimum deployment target enables SwiftData and @Observable macro. This covers vast majority of active users while unlocking best-in-class developer experience.

### Expected Features

Research across competitors (PastePal, Paste, Maccy, Clipy, CopyClip, Raycast) reveals a clear feature landscape with 15 table stakes features, 17 competitive differentiators, and 11 anti-features to deliberately avoid.

**Must have (table stakes):**
- Clipboard monitoring (text, images, URLs, files) — core purpose, every competitor has this
- Persistent history across restarts — users expect data survives
- History list/panel UI — the core browsing surface
- Search across history — essential once history exceeds ~20 items
- Paste-back into active app — the whole point of the product
- Global hotkey to open panel — power users expect hotkey access
- Menu bar residence + launch at login — always-running daemon pattern
- Duplicate detection — don't store same content twice consecutively
- Delete individual items + clear all — privacy baseline
- History size limit / retention settings — storage management

**Should have (competitive differentiators):**
- Screen-edge sliding panel — Pastel's core differentiator vs. dropdown/popup competitors
- Rich content previews (images, code, colors) — see what you copied at a glance
- Label/tag organization — turns clipboard into lightweight knowledge tool
- Hotkey paste (Cmd+1-9) — paste last 9 items without opening panel
- Configurable sidebar position (all edges) — useful for different monitor setups
- Code snippet detection + syntax highlighting — high value for developer audience
- Keyboard-driven navigation — full workflow without touching mouse
- Paste as plain text option — strip formatting, users specifically seek this

**Defer to v2+ (nice-to-have):**
- URL preview cards with Open Graph metadata — requires network fetching, adds complexity
- Drag-and-drop from panel — covered by paste-back for v1
- App-specific allow/ignore lists — useful but adds complexity to monitoring pipeline
- iCloud sync — explicitly out of scope, massive complexity

**Anti-features (deliberately NOT building):**
- iCloud sync across devices — massive complexity, server costs, privacy concerns
- AI-powered features (summarize, translate) — scope creep, every app has AI now
- Plugin/extension system — premature, huge API surface
- Clipboard rules/automation engine — different product category
- Browser extension integration — NSPasteboard already captures browser copies

### Architecture Approach

The architecture is a hybrid AppKit/SwiftUI system with clear separation: SwiftUI for all view content, AppKit for window management and system integration. This is the standard pattern for professional macOS menu bar utilities that need deep system integration.

**Major components:**
1. **ClipboardMonitor** — Timer-based polling of NSPasteboard.general.changeCount every 0.5s; when changed, immediately read content and classify type (text, image, URL, file, code, color)
2. **ClipboardItem Store (SwiftData)** — Persists metadata (content type, timestamp, source app, labels) in SQLite-backed database; text stored inline, images as file path references
3. **ImageStorageService** — Saves full images to ~/Library/Application Support/Pastel/images/, generates 200px thumbnails on background queue, keeps database small and fast
4. **SlidingPanel (NSPanel + NSHostingView)** — AppKit NSPanel configured as .nonactivatingPanel + .floating so it appears over other apps without stealing focus; hosts SwiftUI views via NSHostingView bridge
5. **PasteBackService** — Writes selected item to NSPasteboard, then posts CGEvent for Cmd+V keystroke to frontmost app; requires Accessibility permission
6. **HotkeyManager** — Registers global hotkeys via Carbon RegisterEventHotKey API for panel toggle and Cmd+1-9 paste shortcuts
7. **MenuBarExtra + Settings** — SwiftUI MenuBarExtra scene for status bar icon, standard Settings scene for preferences window

**Key architectural patterns:**
- NSPasteboard polling with changeCount is the ONLY reliable clipboard monitoring approach (no notification API exists)
- NSPanel with .nonactivatingPanel style mask is mandatory for paste-back to work (SwiftUI windows steal focus and break paste flow)
- Images MUST be stored on disk, not in database BLOBs (prevents database bloat and memory issues at scale)
- CGEvent paste simulation with 50-100ms delay after panel hide (gives target app time to regain focus)
- Hybrid AppKit/SwiftUI: SwiftUI for reactive UI, AppKit for system-level window control

**Data flow:**
System clipboard changes → ClipboardMonitor detects via changeCount → classifies content type → persists to SwiftData + disk (images) → UI auto-updates via @Query → User selects item → PasteBackService writes to pasteboard → panel dismisses → CGEvent Cmd+V → target app pastes

### Critical Pitfalls

Six critical pitfalls emerged from research, each capable of causing rewrites or broken core functionality:

1. **NSPasteboard polling misconfiguration** — Poll too fast (drains battery, energy warnings), too slow (misses rapid clipboard changes), or defer content reading (captures wrong content). **Prevention:** 0.5s interval with DispatchSourceTimer leeway, read content immediately on changeCount change, use main thread for NSPasteboard access (not thread-safe).

2. **NSPanel focus stealing breaks paste-back** — If panel becomes key window, Cmd+V pastes into panel instead of target app, destroying the entire value proposition. **Prevention:** Use NSPanel with .nonactivatingPanel style mask, set isFloatingPanel = true, hidesOnDeactivate = false, level = .floating. Host SwiftUI via NSHostingView. This must be correct from day one; retrofitting onto SwiftUI Window is a complete rewrite.

3. **Accessibility permission UX disaster** — Paste-back requires Accessibility permission; if not checked/handled gracefully, paste silently fails and users think app is broken. **Prevention:** Check AXIsProcessTrusted() before every paste, show onboarding explaining why permission needed before triggering system prompt, gracefully degrade to copy-only mode if denied, provide re-check button in settings.

4. **App Sandbox blocks Mac App Store distribution** — Clipboard managers need Accessibility API access (for paste-back) and global hotkeys, both incompatible with App Sandbox. **Decision:** Direct distribution outside Mac App Store, no sandbox. This enables full feature set. Attempting to sandbox later breaks paste-back.

5. **Image storage in memory/database causes OOM crashes** — Screenshots are 5-50MB uncompressed; storing 100 images in memory or as SQLite BLOBs balloons RAM/database, degrades query performance. **Prevention:** Store images as files in Application Support, generate thumbnails (200px) on background queue, database holds only file paths, lazy-load full images on demand, enforce disk budget (e.g., 500MB) with oldest-first deletion.

6. **CGEvent paste fails silently in specific contexts** — Secure input fields (banking apps, password managers), certain Electron/Java apps, and timing issues cause paste simulation to fail or paste wrong content. **Prevention:** Add 50-100ms delay between panel hide and CGEvent post, pause clipboard monitoring during paste-back (set flag to ignore next changeCount), detect IsSecureEventInputEnabled() and show "copied to clipboard" toast instead, test with diverse apps (Safari, Chrome, Terminal, VS Code, IntelliJ).

## Implications for Roadmap

Based on research, the roadmap should follow a strict dependency-driven structure with five phases. The architecture mandates specific ordering: clipboard monitoring + data persistence + panel infrastructure MUST come first as the foundation, paste-back and hotkeys next to validate core value, then content richness (images/previews), organization features (labels/search), and finally polish.

### Phase 1: Foundation (Clipboard Monitoring + Basic Panel)
**Rationale:** Everything depends on reliable clipboard monitoring and data persistence. Without these, nothing else can be built or tested. The panel infrastructure (NSPanel configuration) must also be architected correctly from day one because retrofitting non-activating behavior onto a standard window is a rewrite.

**Delivers:** Functional clipboard manager that captures text/images/URLs/files, persists to SwiftData database, displays in a basic screen-edge sliding panel, supports search, and provides menu bar presence with launch-at-login.

**Addresses features:**
- Clipboard monitoring (all content types)
- Persistent history (SwiftData)
- Basic panel UI (NSPanel + NSHostingView + simple list)
- Search (SwiftData predicates)
- Menu bar + launch at login (MenuBarExtra + SMAppService)
- Duplicate detection
- Delete individual/clear all
- History retention settings

**Avoids pitfalls:**
- NSPasteboard polling configured at 0.5s with correct read-immediately pattern (Pitfall 1)
- NSPanel with .nonactivatingPanel from day one (Pitfall 2)
- Images stored on disk, not database BLOBs (Pitfall 5)
- Direct distribution decision made (Pitfall 4)

**Research needed:** None — this phase uses well-documented Apple APIs and established patterns.

### Phase 2: Core UX (Paste-Back + Hotkeys)
**Rationale:** Paste-back is the core value proposition — without it, Pastel is just a clipboard viewer. Hotkeys enable the power-user workflow. These features validate whether the NSPanel configuration is correct and whether the product concept works.

**Delivers:** Working paste-back functionality (double-click or Enter to paste into frontmost app), global hotkey to toggle panel, Accessibility permission onboarding flow, animated panel slide transitions.

**Uses stack elements:**
- CGEvent API for Cmd+V simulation
- Carbon RegisterEventHotKey for global hotkeys
- AXIsProcessTrusted for permission checking
- NSAnimationContext for panel animations

**Implements architecture:**
- PasteBackService component
- HotkeyManager component
- Screen-edge positioning calculations
- Panel animation state machine

**Avoids pitfalls:**
- 50-100ms delay between panel hide and CGEvent post (Pitfall 6)
- Pause clipboard monitoring during paste-back with isPasting flag (Pitfall 6)
- Accessibility permission check before every paste with graceful degradation (Pitfall 2)
- Detect secure input mode and fall back to copy-only (Pitfall 6)

**Research needed:** Minimal — CGEvent paste simulation is well-documented, but edge cases with specific apps (Electron, Java) may need empirical testing.

### Phase 3: Content Richness (Images + Rich Previews)
**Rationale:** Now that core capture/display/paste pipeline is solid, add visual richness that makes Pastel delightful. Images and rich previews differentiate from lightweight competitors (Maccy, Flycut). This phase depends on the storage architecture from Phase 1 being correct.

**Delivers:** Image thumbnails in panel, syntax highlighting for code snippets, color swatches for hex/RGB values, source app tracking, content type detection intelligence.

**Addresses features:**
- Rich image previews (thumbnails, full-size on click)
- Code syntax highlighting
- Color swatch detection
- Source app tracking (via NSWorkspace)
- Intelligent content type classification

**Uses stack elements:**
- ImageStorageService with thumbnail generation (NSImage/CGImage)
- Highlightr library for code syntax highlighting
- String+Detection utilities for identifying code/color/URL patterns

**Avoids pitfalls:**
- Thumbnail generation on background queue, never blocking main thread (Pitfall 5)
- Lazy-load full images on demand, only thumbnails in memory (Pitfall 5)
- Disk budget enforcement with oldest-first cleanup (Pitfall 5)

**Research needed:** Minor — Syntax highlighting library evaluation (Highlightr vs. alternatives), language detection strategies for code snippets.

### Phase 4: Organization (Labels + Enhanced Search)
**Rationale:** As users accumulate history, organization features become valuable. Labels and enhanced search help at scale but aren't needed when users have 50 items. These can be built independently of content types from Phase 3.

**Delivers:** Label system for categorizing items, label-based filtering, enhanced search across labels, pinned/favorite items, keyboard-driven navigation in panel.

**Addresses features:**
- Label/tag organization
- Label filtering (chip bar UI)
- Favorite/pin items
- Keyboard navigation (arrow keys + Enter + Escape + Cmd+1-9)
- Search combined with label filters

**Implements architecture:**
- LabelManager component
- SwiftData many-to-many relationships (ClipboardItem ↔ Label)
- Label chip UI components
- Keyboard navigation state machine

**Avoids pitfalls:**
- Labels are optional, not mandatory (UX Pitfall: forced organization adds friction)
- Default view shows ALL items, labels are filter dimension (UX Pitfall)
- Search performs well at scale with SwiftData predicates or FTS5 if needed (Performance Trap)

**Research needed:** Optional — If search performance degrades at 2000+ items, research SQLite FTS5 integration alongside SwiftData.

### Phase 5: Polish (Settings + Configurability + Edge Cases)
**Rationale:** After all features are working, add configurability and handle edge cases. Settings depend on knowing what needs configuration (which requires all features built first). This phase is about production-ready refinement.

**Delivers:** Complete Settings window, configurable sidebar position (all four edges), hotkey customization, paste behavior settings (direct vs. copy-then-paste), always-dark theme refinement, multi-monitor support, edge case handling.

**Addresses features:**
- Configurable sidebar position (left/right/top/bottom edges)
- Paste as plain text option
- Settings window with tabs (General, Appearance, Hotkeys)
- User-configurable global hotkeys (via KeyboardShortcuts library)
- Animated panel transitions (polish pass)

**Avoids pitfalls:**
- Panel appears on screen with frontmost app (multi-monitor support) (UX Pitfall)
- Panel doesn't cover area where user wants to paste (configurable position) (UX Pitfall)
- Hotkey numbers displayed on first 9 items (UX Pitfall)
- Memory stable after 48 hours of use (tested) ("Looks Done But Isn't")
- Orphaned image files cleaned up when items deleted ("Looks Done But Isn't")

**Research needed:** None — Settings UI is standard SwiftUI, edge cases are discovered during testing.

### Phase Ordering Rationale

The five-phase structure follows strict technical dependencies:

1. **Phase 1 is non-negotiable first** because clipboard monitoring, persistence, and NSPanel configuration are architectural foundations. Every other feature builds on top. Getting NSPanel configuration wrong means a rewrite.

2. **Phase 2 must come after Phase 1** because paste-back depends on having items in history and the panel working. It validates the core product concept. If paste-back doesn't work due to NSPanel misconfiguration, we discover it here before building more features.

3. **Phase 3 (content richness) is independent of Phase 4 (organization)** but both depend on Phase 1's storage architecture. They could theoretically be parallel, but content richness delivers more user-visible value, so it comes first.

4. **Phase 4 adds organization** which becomes valuable as history grows. Can't build labels until the data model is stable (Phase 1).

5. **Phase 5 is last** because settings UI depends on having features to configure. Building settings prematurely means redesigning them as features evolve.

**Dependency-driven not feature-driven:** This ordering prevents architectural rewrites. Building paste-back before getting NSPanel right, or adding images before deciding on storage strategy, causes expensive backtracking.

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 3 (Content Richness):** Syntax highlighting library evaluation (Highlightr maintenance status, alternatives like TreeSitter), language detection for code snippets, color parsing edge cases
- **Phase 4 (Organization):** If search performance degrades at scale (2000+ items), may need SQLite FTS5 integration research

**Phases with standard patterns (skip research-phase):**
- **Phase 1:** NSPasteboard polling, SwiftData persistence, MenuBarExtra — all well-documented Apple APIs with established patterns
- **Phase 2:** CGEvent paste simulation, Carbon hotkey registration — mature APIs with reference implementations in Maccy/Clipy
- **Phase 5:** Settings UI, preferences persistence — standard SwiftUI patterns

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Swift, SwiftUI, AppKit, SwiftData are Apple first-party frameworks with stable APIs and extensive documentation. NSPasteboard, NSPanel, CGEvent are mature (10+ years). SwiftData is newer (WWDC 2023) but stable for production by late 2024. Third-party library versions (HotKey, Highlightr) are from training data and should be verified. |
| Features | MEDIUM | Competitor feature analysis based on training knowledge of PastePal, Paste, Maccy, Clipy, Raycast through May 2025. WebSearch unavailable for live verification. Feature landscape is stable (clipboard managers haven't fundamentally changed), but specific version details may have updated. |
| Architecture | HIGH | Architectural patterns (NSPasteboard polling, NSPanel non-activating, CGEvent paste, disk-based image storage) are established community consensus observed in open-source clipboard managers. These patterns are 5+ years old and proven. AppKit/SwiftUI hybrid approach is standard for pro macOS apps. |
| Pitfalls | MEDIUM-HIGH | Core pitfalls (NSPanel focus stealing, image storage OOM, polling misconfiguration, Accessibility permission UX) are well-known in macOS utility development community. Specific edge cases (CGEvent failures in certain apps) are anecdotal and may vary by macOS version. Security considerations (concealed pasteboard types) are documented Apple APIs. |

**Overall confidence:** MEDIUM-HIGH

The technical approach is sound with HIGH confidence because it's based on mature Apple APIs and proven patterns from established clipboard managers. Feature landscape confidence is MEDIUM due to lack of live competitor verification, but the core features are stable. The main uncertainty is around third-party library versions and edge cases in paste simulation with specific apps.

### Gaps to Address

**SwiftData maturity on macOS:** SwiftData was introduced WWDC 2023 (macOS 14). By late 2024 it was production-ready, but edge cases with complex queries or relationships may exist. **Mitigation:** Start with SwiftData for rapid development; if issues arise, Core Data is a well-documented fallback. They share SQLite backend and similar concepts.

**Third-party library versions:** Versions listed (HotKey ~0.2, KeyboardShortcuts ~2.0, Highlightr ~2.1) are from training data. **Mitigation:** Verify current versions on GitHub before adding to Package.swift. All libraries are widely used in macOS indie app ecosystem.

**Paste simulation edge cases:** CGEvent Cmd+V simulation may fail in specific apps (certain Electron builds, Java apps, remote desktop clients). **Mitigation:** Test with diverse apps during Phase 2 (Safari, Chrome, Firefox, Terminal, VS Code, IntelliJ, 1Password). Document known incompatibilities and provide "copied to clipboard" fallback.

**macOS Sequoia (15.x) and macOS 16 changes:** Research based on training knowledge through May 2025. macOS evolves, and new privacy restrictions or API changes may have occurred. **Mitigation:** Verify NSPasteboard behavior, Accessibility permission flow, and CGEvent posting against current macOS release notes during Phase 1 setup.

**Search performance at scale:** SwiftData predicate-based search may degrade at 5000+ items. **Mitigation:** Test search performance during Phase 4 with synthetic large datasets. If needed, research SQLite FTS5 integration as a parallel search index.

**Multi-monitor edge cases:** Panel positioning on secondary displays, different DPI scaling, vertical monitors. **Mitigation:** Test with 2+ monitor setups during Phase 5. NSScreen API handles most cases, but edge detection calculations need empirical validation.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — NSPasteboard, NSPanel, CGEvent, SwiftData, MenuBarExtra, @Observable, Core Graphics, AppKit, SwiftUI (developer.apple.com/documentation)
- Apple WWDC sessions — WWDC23 "Meet SwiftData", WWDC22 "Bring your app to the menu bar" (MenuBarExtra introduction)
- Apple Human Interface Guidelines — macOS menu bar apps, panel windows, Accessibility patterns

### Secondary (MEDIUM confidence)
- Open-source clipboard managers — Maccy (github.com/p0deje/Maccy), Clipy (github.com/Clipy/Clipy) — architectural patterns for NSPasteboard polling, CGEvent paste simulation, hotkey registration
- sindresorhus libraries — KeyboardShortcuts, LaunchAtLogin, Defaults (github.com/sindresorhus) — widely used in macOS indie app ecosystem
- soffes/HotKey — Simple Swift wrapper for Carbon RegisterEventHotKey (github.com/soffes/HotKey)
- Training knowledge of PastePal, Paste, Raycast, CopyClip feature sets through May 2025

### Tertiary (LOW confidence)
- Highlightr library for syntax highlighting — Version and maintenance status should be verified (github.com/raspu/Highlightr)
- Specific macOS Sequoia (15.x) or macOS 16 changes — Should be verified against current release notes

**Note on research conditions:** WebSearch and WebFetch were unavailable during this research session. All findings are based on training knowledge of well-established Apple frameworks and patterns through May 2025. Core APIs (NSPasteboard, NSPanel, CGEvent) have been stable for 10+ years and are unlikely to have changed fundamentally. SwiftData is newer (2023) but production-ready. Third-party library versions should be verified before implementation.

---
*Research completed: 2026-02-05*
*Ready for roadmap: yes*
