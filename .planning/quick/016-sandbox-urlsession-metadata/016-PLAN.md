---
phase: quick-016
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Resources/Pastel.entitlements
  - Pastel/Services/URLMetadataService.swift
autonomous: true

must_haves:
  truths:
    - "App Sandbox is enabled (com.apple.security.app-sandbox is true)"
    - "URL metadata fetching works without LinkPresentation framework"
    - "Title, favicon, and og:image are extracted from URLs and saved to disk"
    - "Existing shouldFetchMetadata(), reuseDuplicateMetadata(), and isPrivateHost() remain unchanged"
  artifacts:
    - path: "Pastel/Resources/Pastel.entitlements"
      provides: "Sandbox-enabled entitlements"
      contains: "com.apple.security.app-sandbox"
    - path: "Pastel/Services/URLMetadataService.swift"
      provides: "URLSession-based metadata fetching"
      exports: ["shouldFetchMetadata", "fetchMetadata"]
  key_links:
    - from: "Pastel/Services/URLMetadataService.swift"
      to: "URLSession.shared"
      via: "data(from:) with 5s timeout"
      pattern: "URLSession\\.shared\\.data"
    - from: "Pastel/Services/URLMetadataService.swift"
      to: "ImageStorageService"
      via: "saveFavicon and savePreviewImage"
      pattern: "ImageStorageService\\.shared\\.save(Favicon|PreviewImage)"
---

<objective>
Re-enable App Sandbox and replace LPMetadataProvider with URLSession + HTML parsing for URL metadata extraction.

Purpose: LPMetadataProvider does not work under App Sandbox. Switching to URLSession-based HTML parsing makes URL metadata fetching sandbox-compatible, enabling App Store distribution.

Output: Sandbox-enabled entitlements file and a rewritten URLMetadataService that fetches HTML, parses title/og:image/favicon tags, and downloads images via URLSession.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Resources/Pastel.entitlements
@Pastel/Services/URLMetadataService.swift
@Pastel/Services/ImageStorageService.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Enable App Sandbox in entitlements</name>
  <files>Pastel/Resources/Pastel.entitlements</files>
  <action>
    In Pastel/Resources/Pastel.entitlements, change the value of com.apple.security.app-sandbox from false to true.

    Keep the existing keys:
    - com.apple.security.network.client = true (needed for URLSession)
    - com.apple.security.files.user-selected.read-write = true (needed for NSSavePanel/NSOpenPanel)

    No other entitlement changes.
  </action>
  <verify>Read the file and confirm com.apple.security.app-sandbox is true. All three keys present.</verify>
  <done>Entitlements plist has app-sandbox=true, network.client=true, files.user-selected.read-write=true.</done>
</task>

<task type="auto">
  <name>Task 2: Replace LPMetadataProvider with URLSession + HTML parsing</name>
  <files>Pastel/Services/URLMetadataService.swift</files>
  <action>
    Rewrite the private implementation of URLMetadataService.swift to use URLSession instead of LinkPresentation. The public API signature and behavior must remain identical.

    KEEP UNCHANGED (do not modify these methods at all):
    - shouldFetchMetadata(for:) -- exact same logic
    - reuseDuplicateMetadata(for:currentItem:modelContext:) -- exact same logic
    - isPrivateHost(_:) -- exact same logic

    REMOVE:
    - `import LinkPresentation` -- remove entirely
    - fetchLinkMetadata(for:) method -- replaced by HTML fetching
    - loadImageData(from: NSItemProvider) method -- no longer needed (was for LPMetadataProvider's NSItemProvider-based image delivery)

    ADD a private static URLSession configuration:
    - Create a URLSessionConfiguration.ephemeral with timeoutIntervalForRequest = 5 and timeoutIntervalForResource = 10
    - Create a static let session = URLSession(configuration: config) stored as a static property
    - Set a Safari-like User-Agent on the configuration's httpAdditionalHeaders: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    ADD a private HTML parsing helper:
    ```
    private static func parseHTML(_ html: String, baseURL: URL) -> (title: String?, ogImageURL: URL?, faviconURL: URL?)
    ```
    This method should:
    1. Extract title: Find content between <title> and </title> tags (case-insensitive). Trim whitespace. Decode basic HTML entities (&amp; &lt; &gt; &quot; &#39;).
    2. Extract og:image: Find <meta property="og:image" content="..."> or <meta content="..." property="og:image"> (both attribute orders). Extract the content attribute value. Resolve relative URLs against baseURL.
    3. Extract favicon: Search for <link> tags with rel containing "icon" (covers "icon", "shortcut icon", "apple-touch-icon"). Extract the href attribute value. Resolve relative URLs against baseURL. If no <link rel="icon"> found, fall back to baseURL.scheme + "://" + baseURL.host + "/favicon.ico".

    Use simple string operations (range(of:options:.caseInsensitive), String slicing) -- NOT regex or NSRegularExpression. The HTML parsing needs to be lightweight, not comprehensive. Most sites have these tags in standard formats.

    REWRITE fetchMetadata(for:itemID:modelContext:):
    Keep the same signature and @MainActor attribute. Keep the same pre-flight checks and duplicate reuse call at the top. Replace the LPMetadataProvider section with:

    1. Fetch the page HTML:
       - let (data, response) = try await session.data(from: url)
       - Guard that response is HTTPURLResponse with statusCode 200..<300
       - Guard that data can be decoded as UTF-8 string (String(data:encoding:.utf8))

    2. Parse the HTML:
       - Call parseHTML(html, baseURL: url)

    3. Set the title:
       - item.urlTitle = parsedTitle

    4. Download and save favicon (if URL found):
       - let (faviconData, _) = try await session.data(from: faviconURL)
       - item.urlFaviconPath = await ImageStorageService.shared.saveFavicon(data: faviconData)
       - Wrap in do/catch -- favicon failure is non-fatal, just log warning

    5. Download and save og:image (if URL found):
       - let (imageData, _) = try await session.data(from: ogImageURL)
       - item.urlPreviewImagePath = await ImageStorageService.shared.savePreviewImage(data: imageData)
       - Wrap in do/catch -- og:image failure is non-fatal, just log warning

    6. Mark complete:
       - item.urlMetadataFetched = true
       - try modelContext.save()

    7. Error handling: Same pattern as before -- on outer catch, set urlMetadataFetched = false, save, log warning.

    Also update the doc comments:
    - Struct doc: change "LPMetadataProvider" to "URLSession + HTML parsing"
    - saveFavicon/savePreviewImage comments in ImageStorageService.swift reference LPMetadataProvider in doc comments, but those are in a different file and NOT part of this task's scope. Leave them.
  </action>
  <verify>
    Build the project: `cd /Users/phulsechinmay/Desktop/Projects/pastel && swift build 2>&1 | tail -20`

    Confirm:
    1. No import LinkPresentation anywhere: grep -r "LinkPresentation" Pastel/
    2. No LPMetadataProvider or LPLinkMetadata references: grep -r "LPMetadataProvider\|LPLinkMetadata" Pastel/Services/URLMetadataService.swift
    3. URLSession.shared.data or session.data present: grep "session.data\|URLSession" Pastel/Services/URLMetadataService.swift
    4. shouldFetchMetadata, reuseDuplicateMetadata, isPrivateHost still present
  </verify>
  <done>
    URLMetadataService uses URLSession + HTML parsing instead of LinkPresentation.
    No LinkPresentation import or types remain.
    Project compiles without errors.
    shouldFetchMetadata(), reuseDuplicateMetadata(), and isPrivateHost() are unchanged.
  </done>
</task>

</tasks>

<verification>
1. `swift build` succeeds with no errors
2. No references to LinkPresentation, LPMetadataProvider, or LPLinkMetadata in Pastel/Services/URLMetadataService.swift
3. com.apple.security.app-sandbox is true in Pastel/Resources/Pastel.entitlements
4. URLMetadataService still exports fetchMetadata(for:itemID:modelContext:) and shouldFetchMetadata(for:) with same signatures
5. parseHTML correctly handles: title extraction, og:image extraction, favicon extraction with /favicon.ico fallback
</verification>

<success_criteria>
- App Sandbox enabled with network.client and files.user-selected.read-write entitlements
- URLMetadataService fetches HTML via URLSession, parses title/og:image/favicon, downloads images
- No LinkPresentation dependency anywhere in the codebase
- Project compiles cleanly
- All unchanged methods (shouldFetchMetadata, reuseDuplicateMetadata, isPrivateHost) preserved exactly
</success_criteria>

<output>
After completion, create `.planning/quick/016-sandbox-urlsession-metadata/016-SUMMARY.md`
</output>
