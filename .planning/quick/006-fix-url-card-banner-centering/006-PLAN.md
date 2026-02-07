---
phase: quick
plan: 006
type: execute
wave: 1
depends_on: []
files_modified:
  - Pastel/Views/Panel/URLCardView.swift
autonomous: true

must_haves:
  truths:
    - "og:image banner in URLCardView is horizontally center-cropped"
    - "Banner maintains 2:1 aspect ratio with rounded corners"
    - "URL copying from enriched cards still works (no overlay on transparent base)"
  artifacts:
    - path: "Pastel/Views/Panel/URLCardView.swift"
      provides: "Center-cropped banner image in enriched state"
      contains: "scaledToFill"
  key_links:
    - from: "URLCardView.enrichedState"
      to: "bannerImage"
      via: "Image(nsImage:).resizable().scaledToFill() with frame + clipped"
      pattern: "scaledToFill.*frame.*clipped"
---

<objective>
Fix the og:image banner centering in URLCardView so images are center-cropped instead of top-left cropped.

Purpose: The current banner implementation crops from an unpredictable position because GeometryReader + ZStack + position interferes with SwiftUI's natural image centering. Need to simplify to a pattern that reliably center-crops.
Output: URLCardView.swift with a corrected banner that center-crops images within a 2:1 aspect ratio frame.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Pastel/Views/Panel/URLCardView.swift
@Pastel/Views/Panel/ImageCardView.swift
@Pastel/Views/Panel/AsyncThumbnailView.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Replace GeometryReader banner with simple center-cropping pattern</name>
  <files>Pastel/Views/Panel/URLCardView.swift</files>
  <action>
Replace the banner image block in `enrichedState` (lines 95-111, the `if hasBannerSizedImage` branch) with a simpler SwiftUI pattern that reliably center-crops.

**Remove this entire block:**
```swift
GeometryReader { geo in
    let w = geo.size.width
    let h = w / 2
    ZStack {
        Image(nsImage: bannerImage)
            .resizable()
            .scaledToFill()
    }
    .frame(width: w, height: h)
    .position(x: geo.frame(in: .local).midX, y: geo.frame(in: .local).midY)
    .clipped()
}
.aspectRatio(2 / 1, contentMode: .fit)
.clipShape(RoundedRectangle(cornerRadius: 6))
.transition(.opacity)
```

**Replace with:**
```swift
Image(nsImage: bannerImage)
    .resizable()
    .scaledToFill()
    .frame(minWidth: 0, maxWidth: .infinity)
    .aspectRatio(2 / 1, contentMode: .fill)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .transition(.opacity)
```

**Why this works:** The key problem with GeometryReader + ZStack + position is that `.position()` moves the ZStack center but doesn't affect where the oversized image anchors inside the ZStack. By removing GeometryReader entirely and using the image directly with `.scaledToFill()` + `.aspectRatio(contentMode: .fill)` + `.clipped()`, SwiftUI's default centering behavior takes over. The image fills the 2:1 frame and overflows equally on all sides, then `.clipped()` trims to the frame -- producing a center crop.

**Why NOT overlay:** The `Color.clear.overlay { Image }` pattern was tried before and broke URL copying functionality. The approach above uses the Image directly in the VStack hierarchy, preserving hit-testing.

**Important:** Do NOT use `contentMode: .fit` on the aspectRatio modifier -- that would letterbox the image. Use `.fill` so the image fills the entire 2:1 frame area.

After making the change, build to verify compilation:
```
xcodebuild -project Pastel.xcodeproj -scheme Pastel -configuration Debug build 2>&1 | tail -5
```
  </action>
  <verify>
1. `xcodebuild -project Pastel.xcodeproj -scheme Pastel -configuration Debug build` succeeds
2. Visual inspection: Run the app, copy a URL with a wide og:image (e.g. any news article, GitHub repo page), and confirm the banner image appears center-cropped in the 2:1 frame rather than offset to one side
  </verify>
  <done>
The og:image banner in URLCardView enriched state displays center-cropped within a 2:1 rounded rectangle. No GeometryReader, no ZStack, no position modifier. URL copy functionality unaffected. Build succeeds.
  </done>
</task>

</tasks>

<verification>
- App builds without errors or warnings in URLCardView.swift
- Copy a URL that has a wide og:image (test with a GitHub repo URL or news article)
- The banner image appears center-cropped (focal point visible, not offset)
- Click/right-click on the enriched URL card still copies the URL (no regression from overlay pattern)
- The 2:1 aspect ratio is maintained
- Rounded corners display correctly on the banner
</verification>

<success_criteria>
- Banner images are visually center-cropped in the 2:1 frame
- No GeometryReader, ZStack, or .position() in the banner code
- Build succeeds with zero errors
- URL copying from enriched cards is unaffected
</success_criteria>

<output>
After completion, create `.planning/quick/006-fix-url-card-banner-centering/006-SUMMARY.md`
</output>
