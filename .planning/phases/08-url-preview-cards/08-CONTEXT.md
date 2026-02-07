# Phase 8: URL Preview Cards - Context

**Gathered:** 2026-02-06
**Status:** Ready for planning

<domain>
## Phase Boundary

URL clipboard items auto-fetch page metadata and display rich preview cards with title, favicon, and og:image. Graceful fallback when fetching fails or is disabled. Settings toggle to opt out. Existing plain URL display remains the fallback.

</domain>

<decisions>
## Implementation Decisions

### Card layout & hierarchy
- og:image as top banner spanning full card width (like iMessage/Slack link previews)
- Below banner: favicon (16pt) + page title only — no description, no domain line
- Raw URL text hidden once metadata loads — cleaner card, less redundancy
- No og:image available: compact card with just favicon + title row, no placeholder banner (card is shorter)
- No favicon available: generic globe/link icon in the favicon slot
- og:image banner at fixed 2:1 aspect ratio, image cropped to fit — consistent card heights

### Loading & transitions
- While fetching: show existing plain URL card with a small loading spinner indicator
- Transition to enriched state: smooth animation — card height animates open as banner appears, content fades in
- Progressive reveal: show favicon + title immediately when metadata arrives, add banner image when it downloads
- Cached metadata displayed instantly for old cards — no re-fetch, metadata persisted in SwiftData

### Metadata display rules
- Page title truncated to 1 line with ellipsis — maximum information density
- Favicon at 16pt (standard size) — subtle, doesn't compete with title text
- og:image banner fixed 2:1 ratio, cropped to fill
- Missing favicon → globe icon placeholder
- Missing og:image → no banner, compact favicon + title card

### Fetch scope & privacy
- Only fetch for http:// and https:// URLs — skip file://, ftp://, custom schemes
- Skip localhost, 127.0.0.1, 192.168.x.x, 10.x.x.x, and other private/local addresses
- Duplicate URLs reuse cached metadata from previous entry — instant enrichment, no network call
- 5-second timeout — cancel and fall back to plain URL card if exceeded

### Claude's Discretion
- Exact spinner placement and style on the loading state
- Animation timing and easing curves for the enrichment transition
- SwiftData field layout for cached metadata
- Image disk caching strategy details
- RetentionService cleanup approach for cached images

</decisions>

<specifics>
## Specific Ideas

- Banner image style inspired by iMessage/Slack link previews — full-width, prominent
- Cards should feel like a progression from the existing URL card, not a completely different design
- Progressive loading gives the feel of the card "building itself" — responsive, not blocking

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-url-preview-cards*
*Context gathered: 2026-02-06*
