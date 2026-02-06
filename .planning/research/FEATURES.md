# Feature Research

**Domain:** macOS Clipboard Manager
**Researched:** 2026-02-05
**Confidence:** MEDIUM (based on training data through May 2025; WebSearch/WebFetch unavailable for live verification)

## Competitors Analyzed

| App | Price Model | Positioning | Notes |
|-----|-------------|-------------|-------|
| PastePal | Freemium / one-time purchase | Feature-rich, screen-edge panel, label organization | Primary inspiration for Pastel |
| Paste (by Lingual) | Subscription ($1.99/mo or Setapp) | Premium, visual-first, iCloud sync, pinboards | Market leader in polished UX |
| Maccy | Free / open source | Lightweight, keyboard-driven, minimalist | Most popular free option |
| CopyClip / CopyClip 2 | Free / Paid | Simple menu bar history | Basic tier, many downloads due to free |
| Flycut | Free / open source | Developer-focused, Jumpcut fork | Very minimal, text-only |
| Clipy | Free / open source | Japanese origin, snippet support | Aging, not updated frequently |
| Alfred Clipboard History | Included with Alfred Powerpack | Integrated into Alfred launcher | Not standalone, but very popular |
| Raycast Clipboard History | Included with Raycast | Integrated into Raycast launcher | Growing fast, especially among developers |
| CopyLess 2 | Paid (one-time) | 10-item quick paste via number keys | Pioneered the Cmd+number paste paradigm |
| Unclutter | Paid (one-time) | Clipboard + files + notes in one panel | Multi-tool, not clipboard-focused |

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing any of these and users will switch to an alternative immediately.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Clipboard monitoring (text) | Core purpose of the app | LOW | NSPasteboard polling or timer-based; every competitor does this |
| Clipboard monitoring (images) | Users copy images constantly; screenshots, design assets | MEDIUM | Must handle various image formats (PNG, JPEG, TIFF, HEIC); storage strategy matters |
| Clipboard monitoring (URLs) | URLs are the most-copied content type after text | LOW | Detect and present URLs distinctly from plain text |
| Clipboard monitoring (files) | Users copy files in Finder regularly | MEDIUM | Store file references/paths, handle moved/deleted files gracefully |
| Persistent history across restarts | Users expect history survives app/system restarts | MEDIUM | Requires local persistence (SQLite, SwiftData, or Core Data) |
| History list/panel UI | Users need to browse and select from history | HIGH | The core UI surface; must be fast, scrollable, visually clear |
| Search | Users accumulate hundreds/thousands of items | MEDIUM | Full-text search across all clipboard content; must be fast |
| Keyboard shortcut to open | Power users (the target audience) expect hotkey access | LOW | Global hotkey registration via Carbon API or modern alternatives |
| Paste-back into active app | The whole point -- select an item and it goes into the active app | HIGH | Requires Accessibility permissions; must handle paste simulation reliably |
| Menu bar residence | Clipboard managers live in the menu bar, not the dock | LOW | Standard LSUIElement / NSApplication.activationPolicy pattern |
| History size limit / retention | Users need control over storage growth | LOW | Settings for max items or time-based retention |
| Delete individual items | Users copy sensitive data (passwords) and need to remove specific entries | LOW | Basic CRUD operation on history |
| Clear all history | Quick way to nuke everything (privacy concern) | LOW | Single action, confirmation dialog |
| Launch at login | Clipboard managers must run always; users expect auto-start | LOW | SMLoginItemSetEnabled or ServiceManagement framework |
| Duplicate detection | Don't store the same content twice in a row | LOW | Compare new clipboard content with most recent entry; every good manager does this |

### Differentiators (Competitive Advantage)

Features that separate good from great. Not every competitor has these; having them well-implemented creates real value.

| Feature | Value Proposition | Complexity | Who Has It | Notes |
|---------|-------------------|------------|------------|-------|
| Screen-edge sliding panel | Accessible from any app without context-switching; feels native and spatial | HIGH | PastePal, Paste | Pastel's core UI concept. Most competitors use a dropdown or popup. This is the single biggest differentiator for the "premium panel" category |
| Rich content previews (images, code, colors) | See what you copied at a glance without pasting first | HIGH | PastePal, Paste | Thumbnails for images, syntax highlighting for code, color swatches for hex/rgb values. Most free tools show text-only or tiny icons |
| Label/tag organization | Categorize clipboard items for later retrieval; turns clipboard into a lightweight knowledge tool | MEDIUM | PastePal (labels), Paste (pinboards) | Maccy/Flycut/CopyClip have zero organization. This is a clear differentiator |
| Hotkey paste (Cmd+1-9) | Paste any of the last 9 items without opening the panel at all | MEDIUM | CopyLess 2, PastePal | Extremely fast for power users. Most competitors require opening UI first. Pastel should have this |
| Configurable sidebar position (edges) | Let users choose which screen edge the panel slides from | MEDIUM | PastePal (limited), Paste (bottom only) | Most tools only offer one position. Multi-edge support is genuinely useful for different monitor setups |
| Code snippet detection + syntax highlighting | Developers copy code constantly; showing it highlighted saves time identifying snippets | HIGH | PastePal (basic), none do it exceptionally | Requires language detection and highlighting. High value for developer audience |
| Color detection (hex, RGB, HSL swatches) | Designers copy color values all day; showing a visual swatch is immediately useful | MEDIUM | PastePal | Detect color strings and render swatches. Niche but delightful |
| URL preview cards | Show page title, favicon, maybe a thumbnail for copied URLs | HIGH | Paste (limited) | Requires fetching metadata (Open Graph tags). Can be done lazily. Adds visual richness |
| Drag-and-drop from panel | Drag items out of the clipboard panel into other apps | MEDIUM | Paste, PastePal | Alternative to paste-back; especially useful for images and files |
| Favorite/pin items | Pin frequently used items so they stay accessible regardless of history age | LOW | Paste (pinboards), PastePal (favorites) | Simple but high-value. Pinned items persist beyond retention limits |
| Merge/combine clipboard items | Select multiple items and combine them into one | MEDIUM | Paste | Niche but valued by users who assemble content from multiple sources |
| Paste as plain text option | Strip formatting when pasting rich text | LOW | Most competitors | Simple but users specifically seek this out. Should be a modifier key (e.g., Shift+click or Opt+paste) |
| App-specific clipboard history | Show what was copied from which app, filter by source app | MEDIUM | Paste, PastePal | Requires tracking source app via NSWorkspace. Useful for context |
| Intelligent content type detection | Auto-categorize items as text, code, URL, image, file, color | MEDIUM | PastePal | Makes search and filtering much more useful. Foundation for rich previews |
| Keyboard-driven navigation | Navigate history, select, and paste entirely with keyboard | MEDIUM | Maccy (excellent), Alfred, Raycast | Power users hate touching the mouse. Arrow keys + Enter to paste is essential for speed |
| Animated panel transitions | Smooth slide-in/out animation for the edge panel | MEDIUM | PastePal, Paste | Feels polished vs. an abrupt popup. SwiftUI animations make this achievable |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems. Deliberately do NOT build these (or defer indefinitely).

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| iCloud sync across devices | "I want my clipboard on my iPhone too" | Massive complexity: conflict resolution, storage costs, privacy concerns (syncing passwords/sensitive data to cloud), unreliable offline behavior. Paste charges a subscription primarily because of this feature's server costs | Do NOT build for v1. If ever, treat as a separate milestone with its own research. Universal Clipboard (built into macOS) already handles basic cross-device paste |
| Snippet templates / text expansion | "Let me save templates and expand them with shortcuts" | This is an entirely different product category (TextExpander, Typinator, Espanso). Building it dilutes focus and creates a mediocre version of a specialized tool | Keep clipboard manager focused. If users want templates, they'll pair Pastel with a dedicated text expander |
| Browser extension integration | "Detect what I copy in Chrome specifically" | NSPasteboard already captures browser copies. A browser extension adds maintenance burden (Chrome, Firefox, Safari each need separate extensions), review processes, and security concerns | The standard pasteboard monitoring already captures browser content. No extension needed |
| AI-powered features (summarize, transform) | "Use AI to summarize my clipboard" or "translate copied text" | Requires API keys or local model, adds latency, cost, and complexity. Tangential to core value. Every app is adding AI; it's not a differentiator, it's a distraction | Keep the app fast and focused. If anything, add a "copy as plain text" or "transform case" as simple text operations, not AI |
| Real-time collaboration / shared clipboard | "Share clipboard with my team" | Networking, authentication, conflict resolution, privacy nightmares. Completely different product category | Out of scope. Teams use Slack/messaging for sharing content |
| Plugin/extension system | "Let me write plugins for custom behavior" | Massive API surface to design, maintain, and support. Premature for v1. Plugin APIs are hard to get right and hard to change once published | Build a solid, opinionated app first. Plugin system is a v3+ consideration if there's proven demand |
| Clipboard rules / automation | "Auto-process items matching a pattern" (e.g., auto-strip tracking params from URLs) | Rules engines are complex to build and UX-heavy to configure. Scope creep. Users who want this use Keyboard Maestro or Shortcuts | Keep processing manual. At most, offer "paste as plain text" as the one transformation |
| Multi-window / detachable panels | "Let me have clipboard panels on multiple monitors" | Window management complexity multiplies. Focus on one excellent panel | Single panel, configurable position. Support multiple displays by letting user choose which screen edge |
| Encrypting clipboard history | "Encrypt my clipboard database" | Adds complexity, degrades search performance (can't index encrypted content easily), gives false sense of security since data was already in plaintext on clipboard | Offer "clear history" and "exclude sensitive apps" instead. The clipboard itself is unencrypted at the OS level |
| Allow/Ignore app lists (for v1) | "Don't capture from my password manager" | Useful but adds complexity to the monitoring pipeline and requires a settings UI for app selection. Already marked out of scope for v1 in PROJECT.md | Defer to v2 as planned. For v1, users can manually delete sensitive items. The "clear history" button covers the acute need |
| Complex theming / custom colors | "Let me customize the UI colors" | Design maintenance burden, visual inconsistency, QA surface area. The always-dark decision is correct | Always-dark is a feature, not a limitation. Ship one polished theme |

## Feature Dependencies

```
[Clipboard Monitoring]
    |
    |-- (required by all features below) -->
    |
    +-- [History Persistence (DB)]
    |       |
    |       +-- [Search] -- (enhanced by) --> [Label/Tag System]
    |       |       |
    |       |       +-- [Keyboard Navigation in Results]
    |       |
    |       +-- [History Retention Settings]
    |       |
    |       +-- [Delete Individual / Clear All]
    |       |
    |       +-- [Favorite/Pin Items]
    |
    +-- [Content Type Detection]
    |       |
    |       +-- [Rich Previews (Images)]
    |       |       |
    |       |       +-- [Image Disk Storage + Thumbnails]
    |       |
    |       +-- [Rich Previews (Code + Syntax Highlighting)]
    |       |
    |       +-- [Rich Previews (URL Cards)]
    |       |       |
    |       |       +-- [URL Metadata Fetching (Open Graph)]
    |       |
    |       +-- [Rich Previews (Color Swatches)]
    |       |
    |       +-- [Source App Tracking]
    |
    +-- [History Panel UI (Sidebar)]
    |       |
    |       +-- [Animated Panel Transitions]
    |       |
    |       +-- [Configurable Sidebar Position]
    |       |
    |       +-- [Drag-and-Drop from Panel]
    |       |
    |       +-- [Keyboard-Driven Navigation]
    |
    +-- [Paste-Back Mechanism]
            |
            +-- [Hotkey Paste (Cmd+1-9)]
            |
            +-- [Paste as Plain Text]
            |
            +-- [Configurable Paste Behavior (direct vs. copy-then-paste)]

[Menu Bar App] -- (independent, parallel) --> [Launch at Login]

[Settings Window]
    |
    +-- [History Retention Settings]
    +-- [Sidebar Position Config]
    +-- [Paste Behavior Config]
    +-- [Hotkey Configuration]
```

### Dependency Notes

- **Everything requires Clipboard Monitoring:** This is the foundation. Without reliable monitoring, nothing else works.
- **History Persistence requires Clipboard Monitoring:** Items must be captured before they can be stored.
- **Search requires History Persistence:** You search over stored items, not the live clipboard.
- **Rich Previews require Content Type Detection:** Must know what type of content an item is before rendering the appropriate preview.
- **Image Thumbnails require Image Disk Storage:** Thumbnails are generated from stored images; the storage strategy must exist first.
- **URL Preview Cards require URL Metadata Fetching:** Optional enhancement; cards can show just the URL if fetching fails.
- **Paste-Back is independent of UI:** The mechanism works regardless of whether the user triggers it from the panel, a hotkey, or keyboard navigation.
- **Hotkey Paste (Cmd+1-9) requires Paste-Back:** Uses the same underlying paste simulation, just triggered differently.
- **Label System enhances Search:** Labels are a search/filter dimension, not a prerequisite. Search can work without labels, labels make search more powerful.
- **Settings Window depends on having configurable features:** Build settings as features that need configuration are implemented.

## MVP Definition

### Launch With (v1)

Minimum viable product -- what's needed for a usable clipboard manager that validates the screen-edge panel concept.

- [x] Clipboard monitoring (text, images, URLs, files) -- core purpose
- [x] History persistence (local DB, survives restart) -- useless without this
- [x] Screen-edge sliding panel UI -- the core differentiator to validate
- [x] Basic text previews + image thumbnails -- must show what's in history
- [x] Search across history -- essential once history exceeds ~20 items
- [x] Paste-back into active app (double-click or Enter) -- the core action
- [x] Hotkey to open panel -- power user access pattern
- [x] Duplicate detection -- prevents cluttered history
- [x] Delete individual items + clear all -- privacy baseline
- [x] Menu bar residence + launch at login -- always-running daemon pattern
- [x] History retention settings -- storage management
- [x] Always-dark theme -- ship one polished look

### Add After Validation (v1.x)

Features to add once core panel experience is working and stable.

- [ ] Hotkey paste (Cmd+1-9) -- add when paste-back mechanism is proven reliable
- [ ] Label/tag organization -- add when users accumulate enough history to need organization
- [ ] Configurable sidebar position -- add when single-position panel is stable
- [ ] Code syntax highlighting -- add after content type detection is solid
- [ ] Color swatch detection -- add alongside code detection
- [ ] Paste as plain text -- add when users request it (they will)
- [ ] Favorite/pin items -- add when retention limits cause users to lose important items
- [ ] Keyboard-driven navigation -- add when panel UX is finalized
- [ ] Animated panel transitions -- polish pass after core is working
- [ ] Source app tracking -- add when content type detection is mature

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] URL preview cards with metadata -- requires network fetching, caching; defer until core is rock solid
- [ ] Drag-and-drop from panel -- nice but not essential; paste-back covers the core need
- [ ] Allow/ignore app lists -- privacy enhancement, not needed at launch
- [ ] iCloud sync -- entirely separate scope if ever
- [ ] Merge/combine items -- niche power feature
- [ ] Import/export history -- data portability, defer to v2

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority | Phase |
|---------|------------|---------------------|----------|-------|
| Clipboard monitoring (all types) | HIGH | MEDIUM | P1 | v1 |
| History persistence | HIGH | MEDIUM | P1 | v1 |
| Screen-edge panel UI | HIGH | HIGH | P1 | v1 |
| Search | HIGH | MEDIUM | P1 | v1 |
| Paste-back | HIGH | HIGH | P1 | v1 |
| Global hotkey | HIGH | LOW | P1 | v1 |
| Menu bar + launch at login | HIGH | LOW | P1 | v1 |
| Duplicate detection | MEDIUM | LOW | P1 | v1 |
| Delete/clear history | MEDIUM | LOW | P1 | v1 |
| History retention settings | MEDIUM | LOW | P1 | v1 |
| Basic image thumbnails | HIGH | MEDIUM | P1 | v1 |
| Hotkey paste (Cmd+1-9) | HIGH | MEDIUM | P2 | v1.x |
| Label/tag system | MEDIUM | MEDIUM | P2 | v1.x |
| Configurable sidebar position | MEDIUM | MEDIUM | P2 | v1.x |
| Code syntax highlighting | MEDIUM | HIGH | P2 | v1.x |
| Paste as plain text | MEDIUM | LOW | P2 | v1.x |
| Favorite/pin items | MEDIUM | LOW | P2 | v1.x |
| Keyboard navigation | HIGH | MEDIUM | P2 | v1.x |
| Color swatch detection | LOW | MEDIUM | P2 | v1.x |
| Animated transitions | MEDIUM | MEDIUM | P2 | v1.x |
| Source app tracking | LOW | MEDIUM | P2 | v1.x |
| URL preview cards | LOW | HIGH | P3 | v2+ |
| Drag-and-drop | LOW | MEDIUM | P3 | v2+ |
| Allow/ignore apps | MEDIUM | MEDIUM | P3 | v2+ |
| Merge/combine | LOW | MEDIUM | P3 | v2+ |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | PastePal | Paste | Maccy | CopyClip 2 | Flycut | Raycast | Pastel Plan |
|---------|----------|-------|-------|------------|--------|---------|-------------|
| Text clipboard | Yes | Yes | Yes | Yes | Yes | Yes | Yes (v1) |
| Image clipboard | Yes | Yes | No | No | No | Yes | Yes (v1) |
| URL clipboard | Yes | Yes | Yes | Yes | No | Yes | Yes (v1) |
| File clipboard | Yes | Yes | No | No | No | Yes | Yes (v1) |
| Code detection | Basic | No | No | No | No | No | Yes (v1.x) |
| Color detection | Yes | No | No | No | No | No | Yes (v1.x) |
| Screen-edge panel | Yes | Yes (bottom) | No (popup) | No (menu) | No (menu) | No (launcher) | Yes (v1, configurable) |
| Search | Yes | Yes | Yes | Basic | No | Yes | Yes (v1) |
| Labels/Tags | Yes (labels) | Yes (pinboards) | No | No | No | No | Yes (v1.x) |
| Hotkey paste (1-9) | Yes | No | No | Yes | No | No | Yes (v1.x) |
| Paste as plain text | Yes | Yes | Yes | No | No | Yes | Yes (v1.x) |
| Pin/Favorite | Yes | Yes (pinboards) | No | No | No | No | Yes (v1.x) |
| iCloud sync | No | Yes | No | No | No | No | No (out of scope) |
| Drag-and-drop | Yes | Yes | No | No | No | No | Maybe (v2+) |
| Source app tracking | Yes | Yes | No | No | No | No | Maybe (v1.x) |
| Keyboard navigation | Yes | Yes | Yes (excellent) | Basic | Basic | Yes | Yes (v1.x) |
| Animated transitions | Yes | Yes | No | No | No | Yes | Yes (v1.x) |
| Dark mode | Yes | Yes | System | System | System | System | Always dark |
| Open source | No | No | Yes | No | Yes | No | TBD |
| Price | ~$15 one-time | $1.99/mo | Free | $7.99 | Free | Free tier | TBD |

### Competitive Positioning Analysis

**Pastel sits between Maccy (lightweight/free) and Paste (premium/subscription).**

- Against Maccy/Flycut/CopyClip: Pastel wins on rich previews, screen-edge panel, labels, and visual polish. These lightweight tools are text-focused popups.
- Against Paste: Pastel competes on feature parity without the subscription model. Paste's main advantage is iCloud sync (which Pastel explicitly skips) and brand recognition.
- Against PastePal: Pastel is most directly competitive. Need to match PastePal's core features and differentiate on configurability (sidebar position), polish, and developer-focused features (code highlighting).
- Against Raycast/Alfred: These are launcher tools with clipboard as one feature. Pastel wins on dedicated UX, richer previews, and organization. Users who want a dedicated tool will choose Pastel.

**Pastel's competitive edge should be:**
1. Screen-edge panel that's faster and more configurable than PastePal's
2. Better code/developer content handling than any competitor
3. Keyboard-driven power user experience rivaling Maccy's speed
4. No subscription, no cloud dependency

## Sources

- PastePal app features: Based on training data knowledge of PastePal (pastepal.app), MEDIUM confidence
- Paste app features: Based on training data knowledge of Paste (pasteapp.io), MEDIUM confidence
- Maccy features: Based on training data knowledge of Maccy (maccy.app, open source on GitHub), MEDIUM confidence
- CopyClip 2 features: Based on training data knowledge (Mac App Store listing), MEDIUM confidence
- Flycut features: Based on training data knowledge (GitHub: TermiT/Flycut), MEDIUM confidence
- Raycast clipboard: Based on training data knowledge of Raycast clipboard history feature, MEDIUM confidence
- Alfred clipboard: Based on training data knowledge of Alfred Powerpack clipboard history, MEDIUM confidence

**Confidence note:** All competitor analysis is based on training data through May 2025. WebSearch and WebFetch were unavailable for live verification. Feature sets may have changed since then. Recommend manually checking competitor websites before finalizing roadmap decisions.

---
*Feature research for: macOS Clipboard Manager (Pastel)*
*Researched: 2026-02-05*
