# Pitfalls Research

**Domain:** macOS clipboard manager (native Swift + SwiftUI)
**Researched:** 2026-02-05
**Confidence:** MEDIUM (based on training knowledge; WebSearch and WebFetch unavailable for verification. NSPasteboard, NSPanel, and Accessibility APIs are mature, stable Apple APIs unlikely to have changed significantly since training cutoff.)

---

## Critical Pitfalls

Mistakes that cause rewrites, broken core functionality, or App Store rejection.

### Pitfall 1: NSPasteboard Polling Loop Drains Battery and Misses Transient Items

**What goes wrong:**
macOS provides no notification or callback for clipboard changes. The only approach is polling `NSPasteboard.general.changeCount` on a timer. Teams make three common mistakes here:

1. **Polling too fast** (e.g., every 10ms): CPU never sleeps, battery drain is severe, and users notice the energy impact in Activity Monitor. macOS may also throttle the app or surface it in battery drain warnings.
2. **Polling too slow** (e.g., every 2 seconds): Users copy-paste quickly between apps and the clipboard manager misses intermediate items. If a user copies item A, then copies item B within the polling interval, item A is lost forever.
3. **Comparing only changeCount without reading content immediately**: The changeCount increments on every clipboard change, but the content can be replaced before the next poll cycle. If you detect changeCount changed but defer reading the pasteboard, you may capture the wrong content.

**Why it happens:**
Developers coming from other platforms expect a clipboard change notification (like Android's `ClipboardManager.OnPrimaryClipChangedListener` or Windows's `AddClipboardFormatListener`). macOS has no equivalent. The timer-based approach seems simple but the tuning is critical and easy to get wrong.

**How to avoid:**
- Poll at 0.5 seconds as the baseline interval. This is the sweet spot used by established clipboard managers (Maccy, Clipy).
- On every timer fire, check `changeCount`. If unchanged, do nothing (this is cheap -- just an integer comparison).
- When changeCount has changed, **immediately** read all pasteboard types in that same timer callback. Do not defer reading to another dispatch.
- Store the previous changeCount and the hash of the previous content to avoid storing duplicates when apps set the clipboard to the same content.
- Consider using `DispatchSourceTimer` with leeway (e.g., 100ms leeway on a 500ms timer) so the system can coalesce wake-ups for better battery life.
- For the data read itself: read on the main thread (NSPasteboard is not thread-safe), but immediately dispatch heavy processing (image thumbnail generation, etc.) to a background queue.

**Warning signs:**
- App appears in "Using Significant Energy" warnings in macOS battery menu.
- Users report clipboard items being "missed" -- they copy something, but it does not appear in history.
- Activity Monitor shows consistent CPU usage even when the user is not copying anything.

**Phase to address:**
Phase 1 (Core clipboard monitoring). This is the foundation -- get it wrong and everything built on top is unreliable.

**Confidence:** HIGH -- NSPasteboard polling is a well-documented pattern in the macOS clipboard manager ecosystem. The 0.5s interval is a community consensus.

---

### Pitfall 2: Accessibility Permission Handling is a First-Run UX Killer

**What goes wrong:**
Paste-back functionality (simulating Cmd+V in another app) requires Accessibility permissions. The failure modes are:

1. **Not checking permission before attempting paste**: The paste silently fails. The user thinks the app is broken.
2. **Using AXIsProcessTrusted() without the prompt option**: Calling `AXIsProcessTrusted()` alone checks but does not prompt. The user never sees the System Settings dialog and wonders why paste does not work.
3. **Checking permissions at launch and caching the result**: Users can revoke permissions at any time in System Settings. If you cache the result, the app breaks until restarted.
4. **Not handling the "permissions granted but app not in the list" edge case**: After macOS Ventura, the Accessibility permission list requires the app to be explicitly added. Re-signing or updating the app can invalidate the permission entry, requiring the user to remove and re-add the app.
5. **Blocking the UI on permission check**: If you show a modal dialog demanding permissions before the app is usable, users may quit rather than comply.

**Why it happens:**
Accessibility permissions are a macOS-specific concern with no equivalent on other platforms. The API surface is minimal (`AXIsProcessTrusted`, `kAXTrustedCheckOptionPrompt`), which makes developers think it is simple. But the UX around it is where the complexity lives.

**How to avoid:**
- On first launch, explain WHY accessibility permission is needed (paste-back) before triggering the system prompt. Use a clear onboarding view: "Pastel needs Accessibility access to paste items into other apps."
- Use `AXIsProcessTrusted(options: [kAXTrustedCheckOptionPrompt: true] as CFDictionary)` to trigger the system prompt. But only do this after the user clicks a "Grant Access" button in your onboarding flow, so they understand what is happening.
- Check `AXIsProcessTrusted()` (without the prompt option) before every paste operation, not just at launch. It is a cheap check.
- If permission is not granted, gracefully degrade: copy to clipboard still works, just skip the Cmd+V simulation. Show a non-intrusive banner: "Paste-back requires Accessibility access. [Open Settings]"
- Provide a "Re-check Permissions" button in Settings for users who granted access but it was invalidated.
- After the user grants permission in System Settings, macOS may require the app to be relaunched for the permission to take effect. Detect this and show a "Please relaunch Pastel" message.

**Warning signs:**
- Users report "paste does not work" as a bug.
- One-star reviews mentioning "nothing happens when I click an item."
- High uninstall rate within 5 minutes of first launch (permission friction).

**Phase to address:**
Phase 1 (Core functionality) for the permission check and graceful degradation. Phase 2 or 3 (Onboarding/Polish) for the guided permission flow.

**Confidence:** HIGH -- Accessibility permission handling is a known friction point for every macOS utility app. The pattern of checking before each operation is well-established in Clipy, Maccy, and other open-source managers.

---

### Pitfall 3: Running Outside App Sandbox Blocks Mac App Store Distribution

**What goes wrong:**
Clipboard managers need capabilities that conflict with App Sandbox:

1. **Accessibility API access**: Sandboxed apps cannot use `AXIsProcessTrusted` or `CGEvent` posting for paste simulation. There is no App Sandbox entitlement for Accessibility.
2. **Global keyboard shortcuts**: Registering hotkeys that work system-wide requires either `CGEvent` taps (needs Accessibility) or the newer `NSEvent.addGlobalMonitorForEvents` (which works in sandbox but cannot intercept/suppress events, only observe them).
3. **Reading arbitrary file paths from clipboard**: When a user copies a file in Finder, the clipboard contains a file URL. A sandboxed app cannot access arbitrary file paths without user-granted access.

The result: most clipboard managers either ship outside the Mac App Store (direct distribution) or ship a sandboxed version with reduced functionality (no paste-back, no global hotkeys for paste).

**Why it happens:**
Developers start building features without considering distribution constraints. By the time they try to sandbox the app, they discover half the features are impossible.

**How to avoid:**
- **Decide distribution strategy in Phase 0.** If Mac App Store is required, accept that paste simulation via Accessibility will not work. You would need to use `NSPasteboard` copy + rely on the user to press Cmd+V themselves.
- For direct distribution (outside App Store): disable App Sandbox entirely. Sign with Developer ID for notarization. This gives full access to Accessibility APIs, CGEvent, and the file system.
- If you want BOTH: ship a limited App Store version (clipboard history + copy-to-clipboard) and a full direct-distribution version (with paste-back). But maintaining two targets adds significant complexity.
- **Recommended for Pastel:** Direct distribution (no sandbox). The core value proposition -- hotkey paste-back -- is incompatible with App Sandbox. Trying to sandbox will result in cutting the primary feature.

**Warning signs:**
- Building paste-back features before deciding on distribution model.
- Assuming "we will sandbox it later" without testing which features survive.
- Getting deep into development and discovering Accessibility API calls fail in sandbox.

**Phase to address:**
Phase 0 (Project setup / architecture decisions). This must be decided before writing any code. It affects entitlements, signing, distribution, and feature scope.

**Confidence:** HIGH -- App Sandbox restrictions on Accessibility APIs are well-documented by Apple and universally discussed in macOS utility developer communities. Every major clipboard manager (Paste, Maccy, Clipy, CopyClip) faces this exact constraint.

---

### Pitfall 4: NSPanel Focus Stealing Breaks the Paste-Back Flow

**What goes wrong:**
The clipboard history panel must appear over other apps without stealing keyboard focus from the target app. If the panel becomes the key window:

1. The user's cursor context in the previous app is lost.
2. Cmd+V pastes INTO the clipboard panel, not the target app.
3. The user has to click back into their app, find their cursor position, and paste manually. The entire "instant paste-back" value proposition is destroyed.

Even worse: if the panel activation causes the previously active app to resign first responder, text selection in the target app may be deselected.

**Why it happens:**
Standard NSWindow/NSPanel behavior is to become the key window when shown. SwiftUI's `Window` and `.windowStyle` APIs do not expose the low-level NSPanel configuration needed. Developers either:
- Use a standard SwiftUI window that steals focus.
- Use NSPanel but configure it incorrectly (missing `nonActivatingPanel` style mask).
- Get the panel configuration right but break it with SwiftUI hosting (NSHostingView inside NSPanel can still request first responder).

**How to avoid:**
- Use `NSPanel` with `.nonactivatingPanel` style mask (`NSWindow.StyleMask.nonactivatingPanel`). This is the single most important configuration. It allows the panel to appear without activating your app or stealing key window status from the frontmost app.
- Set the panel's `isFloatingPanel = true` so it stays above other windows.
- Set `hidesOnDeactivate = false` so the panel persists when the user interacts with other apps.
- Set the window level to `.floating` or `.popUpMenu` (experiment to find the right level that stays above other app windows but below system UI).
- Host your SwiftUI content view inside the panel via `NSHostingView`, but set the panel's `canBecomeKey` to return `false` (or conditionally `true` only when the search field needs focus).
- When the user triggers paste (clicks item or presses Cmd+1-9): hide the panel, then post the `CGEvent` for Cmd+V. The previously active app will receive the paste.
- **The search field problem**: If the panel cannot become key, the user cannot type in the search field. Solution: allow `canBecomeKey = true` when the user clicks the search field, but re-activate the previous app before pasting.

**Warning signs:**
- When the panel appears, the menu bar changes to show Pastel's menus instead of the previous app's menus.
- The user has to click back to their original app after pasting.
- Text selections in the target app are lost when the panel appears.
- The panel disappears when switching to another app (hidesOnDeactivate not disabled).

**Phase to address:**
Phase 1 (Panel window infrastructure). This is architectural -- the NSPanel must be correctly configured from the start. Retrofitting focus behavior onto a standard window is a rewrite.

**Confidence:** HIGH -- NSPanel focus management is one of the most discussed topics in macOS utility development. The `nonactivatingPanel` pattern is used by Spotlight, Alfred, Raycast, and every successful clipboard manager.

---

### Pitfall 5: Storing Full-Size Images in Memory or Database Causes OOM Crashes

**What goes wrong:**
Users copy screenshots, large images, and multi-megapixel photos. Each clipboard image can be 5-50MB uncompressed (NSImage/CGImage in memory). Common mistakes:

1. **Storing NSImage objects in an in-memory array**: 100 screenshots = 500MB+ RAM. The app gets killed by macOS memory pressure.
2. **Storing image data as BLOBs in SQLite/SwiftData**: The database balloons to gigabytes. Every query that touches the images table causes massive I/O. Database operations become slow, and the app feels sluggish even for text-only operations.
3. **Generating thumbnails synchronously on the main thread**: The UI freezes for 100ms+ per image. Scrolling through history with many images becomes janky.
4. **Not limiting clipboard history size**: The app grows unbounded until it crashes or fills the disk.

**Why it happens:**
Text clipboard items are tiny (bytes to kilobytes). Developers build the system for text, then add image support and do not realize the scale difference (1000x larger data). The system that worked fine for text collapses under image load.

**How to avoid:**
- **Images on disk, metadata in database.** Store the full-size image as a file (PNG or JPEG on disk in Application Support). Store only the file path and metadata (dimensions, file size, content hash) in the database.
- **Generate thumbnails immediately on capture**, on a background queue. Store thumbnails as separate small files (e.g., 200x200 max dimension, JPEG quality 0.7). The sidebar displays only thumbnails.
- **Load full images on demand.** When the user clicks to preview or paste, load the full image from disk at that moment.
- **Set a disk budget.** Default to something like 500MB for image storage. When exceeded, delete the oldest images first (keep metadata as "image expired" so the history entry still shows "Image (deleted)").
- **Use `NSImage.init(byReferencingFile:)` or lazy loading** for thumbnails to avoid loading all thumbnails into memory at once. For SwiftUI, use `AsyncImage` with a local file URL or a custom async image loader.
- **Content deduplication**: Hash images on capture. If the same image is copied twice, reference the same file instead of storing a duplicate.

**Warning signs:**
- Memory usage in Activity Monitor grows continuously as the user copies images.
- The app becomes slow after a few days of use.
- Database file size grows to hundreds of megabytes or gigabytes.
- UI stutters when scrolling through history containing many images.

**Phase to address:**
Phase 1 (Storage architecture). The disk-based storage design must be the foundation. Migrating from in-memory or database BLOBs to disk storage later requires a data migration.

**Confidence:** HIGH -- Image memory management is a fundamental concern for any app handling user-generated images. The disk-storage pattern is standard in image-heavy macOS apps.

---

### Pitfall 6: CGEvent Paste Simulation Fails Silently in Specific App Contexts

**What goes wrong:**
Paste-back works by posting a `CGEvent` for Cmd+V (keyDown + keyUp for the V key with the Cmd modifier). This fails in several contexts:

1. **Secure input fields**: Banking apps, password managers, and any app using `EnableSecureEventInput()` block CGEvent injection. The paste event is silently swallowed.
2. **Apps that use custom key handling**: Some Electron apps, Java apps (IntelliJ), and remote desktop clients intercept keyboard events differently. CGEvent paste may not reach them.
3. **Timing issues**: If the CGEvent is posted before the target app has fully regained focus (after the panel hides), the event goes to the wrong app or is lost. A common mistake is posting the event synchronously immediately after calling `orderOut` on the panel.
4. **The clipboard is overwritten before the target app processes Cmd+V**: You copy item X to the clipboard, post Cmd+V, but between the copy and the event delivery, another clipboard monitoring cycle overwrites the clipboard. The user gets the wrong content pasted.

**Why it happens:**
CGEvent posting is a low-level mechanism that bypasses the normal event delivery chain. There are many edge cases that do not surface in basic testing (because developers test in TextEdit or Notes, which handle CGEvents perfectly).

**How to avoid:**
- **Add a small delay (50-100ms) between hiding the panel and posting the CGEvent.** Use `DispatchQueue.main.asyncAfter`. This gives the target app time to become active and accept input.
- **Pause clipboard monitoring during paste-back.** When you set the clipboard and post Cmd+V, temporarily stop the polling timer (or set a flag to ignore the next changeCount increment). Otherwise, your own paste-back triggers a new clipboard history entry, creating duplicates.
- **Detect secure input mode.** Call `IsSecureEventInputEnabled()` before attempting CGEvent paste. If secure input is active, show a toast: "Paste-back unavailable in secure fields. Content copied to clipboard."
- **Fall back to clipboard-only mode.** If the CGEvent paste fails or secure input is detected, at minimum copy the content to the clipboard and let the user paste manually.
- **Test with diverse apps:** Safari, Chrome, Terminal, VS Code, IntelliJ, Remote Desktop, 1Password. Each has different event handling.

**Warning signs:**
- Paste works in some apps but not others.
- "The wrong content was pasted" bug reports.
- Duplicate entries appearing in clipboard history every time the user pastes from the manager.

**Phase to address:**
Phase 2 (Paste-back implementation). After core monitoring and panel are working.

**Confidence:** MEDIUM -- CGEvent behavior is well-understood at the API level, but edge cases with specific apps are anecdotal and vary across macOS versions. The "pause monitoring during paste" pattern is based on common practice in open-source clipboard managers.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Storing all clipboard data in UserDefaults | Quick to implement, no database setup | UserDefaults has a practical limit around 1MB. Exceeding it causes silent data loss or crashes. Not designed for structured queries. | Never for clipboard history. Only for settings. |
| Using a SwiftUI `Window` instead of NSPanel for the history panel | Simpler code, pure SwiftUI | Cannot configure `nonactivatingPanel`, focus stealing is unavoidable, breaks paste-back flow. Requires rewrite to NSPanel later. | Never for the clipboard panel. Fine for Settings window. |
| Polling NSPasteboard from a background thread | Avoids main thread work | NSPasteboard is NOT thread-safe. Can cause crashes, data races, or reading stale/corrupt data. | Never. Always poll on main thread, dispatch heavy processing to background. |
| Using `Timer.scheduledTimer` without leeway | Simple timer setup | Prevents the system from coalescing wake-ups, increases energy impact | Only during development. Replace with `DispatchSourceTimer` with leeway for release. |
| Skipping content deduplication | Faster capture processing | Users who repeatedly copy the same thing fill history with duplicates. Wastes disk space for repeated image copies. | MVP phase only. Add dedup by Phase 2. |
| Hardcoding the panel to one screen edge | Faster to build | Users on different setups (external monitors, vertical displays) cannot use the app effectively. Requires re-architecting panel positioning later. | MVP can ship with right-edge only, but design the abstraction to support all edges from day one. |

## Integration Gotchas

Common mistakes when connecting to macOS system services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| NSPasteboard type reading | Reading only `string` type and missing `rtf`, `html`, `fileURL`, `tiff`, `png` types | Read all available types on each capture. Store the richest representation. Prioritize: file URLs > images > RTF > HTML > plain string. |
| NSPasteboard `types` array | Assuming the first type is the "best" type | The types array is ordered by the source app's preference, not by richness. A browser might put `html` before `string`. Read multiple types and choose intelligently. |
| Accessibility permission prompt | Calling `AXIsProcessTrusted(options:)` at launch without explanation | Show a custom UI explaining why the permission is needed first, then trigger the system prompt only after the user opts in. |
| Global hotkey registration | Using deprecated `Carbon` hot key APIs (`RegisterEventHotKey`) | Use `CGEvent.tapCreate` for global hotkeys if outside sandbox. For newer approaches, consider `NSEvent.addGlobalMonitorForEvents` (observe only, cannot suppress). For Pastel's needs (outside sandbox), `CGEvent` tap or even `MASShortcut`/`HotKey` Swift libraries. |
| Login Items (launch at startup) | Using the deprecated `LSSharedFileListInsertItemURL` API | Use `SMAppService.register()` (macOS 13+) for modern login item registration via the Service Management framework. Falls back to the Login Items list in System Settings. |
| File system storage location | Writing images to `~/Documents` or `/tmp` | Use `FileManager.default.urls(for: .applicationSupportDirectory)` and create a `Pastel/` subdirectory. This is the correct location for app-managed files that should persist but are not user-facing documents. |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Loading entire clipboard history into memory at launch | Launch time grows, memory usage balloons | Use pagination/lazy loading. Load only the most recent N items (e.g., 50). Load more on scroll. If using SwiftData/Core Data, use `fetchLimit` and `fetchOffset`. | ~500 items with images, ~5000 text-only items |
| Full-text search scanning all records | Search becomes slow, UI freezes while searching | Use SQLite FTS5 (full-text search) or SwiftData with indexed properties. Pre-index searchable text on capture. | ~2000 items |
| Thumbnail generation blocking the UI | Visible stutter when images are copied | Generate thumbnails on a background queue using `CGImageSource` with `kCGImageSourceThumbnailMaxPixelSize`. Dispatch to main thread only for UI updates. | Immediately noticeable with images >2MP |
| Rendering all history items in a SwiftUI List | Scroll performance degrades, high memory usage | Use `LazyVStack` inside a `ScrollView` instead of `List` if you need custom styling. Or use `List` but ensure row views are lightweight and thumbnails use async loading. | ~200 visible items with images |
| Clipboard polling timer running during sleep/idle | Unnecessary wake-ups when the machine is sleeping or the user is idle | Pause the timer when `NSWorkspace.shared.notificationCenter` posts `screensDidSleep` or `sessionDidResignActive`. Resume on wake. | Battery impact on laptops, always |
| Storing clipboard content as attributed strings | Each item stores NSAttributedString with embedded images, fonts, attachments | Store plain text + RTF data separately. Do not let NSAttributedString pull in embedded resources. | ~100 items with rich text from web pages |

## Security Mistakes

Domain-specific security issues beyond general app security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Capturing passwords and sensitive data in clipboard history | Users copy passwords from 1Password, banking sites, etc. Clipboard manager stores them permanently in searchable plain text. | Respect `org.nspasteboard.ConcealedType` (concealed pasteboard type). When this type is present, either skip the item entirely or mark it as "sensitive" and auto-delete after a short period (e.g., 60 seconds). Also check for `transient` type markers from password managers. |
| Not clearing sensitive items from history | Even if you detect sensitive items, they persist in the database and on-disk files indefinitely. | Implement auto-expiry for items detected as sensitive. Provide a "Clear All History" action. Provide per-item delete. |
| Storing clipboard data without encryption | If the Mac is compromised, clipboard history (which may contain passwords, API keys, personal data) is easily accessible in plain text in Application Support. | For v1, this is acceptable given direct distribution. For later: consider encrypting the database at rest with a key derived from the user's login keychain. |
| Logging clipboard content in debug output | During development, `print(clipboardContent)` leaks sensitive data to Console.app and system logs. | Never log clipboard content in release builds. Use `#if DEBUG` guards for clipboard logging. |
| Not excluding clipboard history from Time Machine / Spotlight | Clipboard data appears in Spotlight search results and gets backed up to Time Machine, exposing sensitive data. | Add `.excludedFromBackup` resource value to the storage directory. Add a `.noindex` file to prevent Spotlight indexing. |

## UX Pitfalls

Common user experience mistakes in clipboard managers.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Panel takes >200ms to appear after hotkey | Feels sluggish. Users stop using the hotkey and go back to Cmd+V. The core value proposition fails. | Keep the panel window always allocated in memory (hidden). On hotkey, just toggle visibility (`orderFront`/`orderOut`). Never create the window on-demand. Pre-render the most recent items. Target <50ms appearance time. |
| No visual feedback when item is pasted | User clicks an item, the panel disappears, but they have no confirmation the paste happened. If it failed (secure input), they are confused. | Brief visual flash or highlight on the item before the panel dismisses. After paste, optionally show a small toast/HUD near the cursor: "Pasted." If paste failed, show why. |
| Search requires clicking a search icon or navigating to a search field | Extra click slows down the power-user workflow | Make the panel immediately typeable for search. When the panel appears and the user starts typing, it should filter the list. No need to click a search field first. (This conflicts with the non-activating panel, so you need to activate the panel on first keystroke.) |
| No keyboard navigation in the list | Users must use the mouse to select items. Defeats the "keyboard-driven" promise. | Arrow keys to navigate, Enter to paste, Escape to dismiss, Cmd+1-9 for quick paste of top 9 items. The panel should be fully navigable without touching the mouse. |
| Showing a cluttered list with every pasteboard type as a separate entry | Multiple entries for the same copy operation (one for text, one for RTF, one for HTML). History fills with duplicates of the same conceptual "item." | Treat each clipboard change as ONE item with multiple representations. Display the best visual representation but store all types. The user sees one card per copy operation, not one per pasteboard type. |
| Panel covers the area where the user wants to paste | The panel slides out over the text editor where the user's cursor is. After paste, the content goes behind the panel. | Allow configurable panel position (all four edges). Default to the edge least likely to overlap the user's primary work area. Consider auto-hiding the panel after paste. |
| No indication of which item will paste with Cmd+1, Cmd+2, etc. | Users have to guess which number corresponds to which item. | Show the hotkey number badge on each of the first 9 items in the list. "1" badge on the first item, "2" on the second, etc. |
| Categories/labels are mandatory or in-your-face | Most users just want to scroll and find. Forced organization adds friction. | Labels should be optional, accessible via a chip bar above the list. Default view shows ALL items. Labels are a power-user feature, not a gate. |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Clipboard monitoring:** Often missing handling for file URLs (copied files from Finder), color data (from color pickers), and multi-item pasteboard (Finder copies multiple files as an array of URLs). Verify all types capture correctly.
- [ ] **Image storage:** Often missing cleanup of orphaned image files when database entries are deleted. Verify: delete a history item, confirm the image file is also removed from disk.
- [ ] **Paste-back:** Often missing the "pause monitoring" flag. Verify: paste an item, confirm it does NOT create a duplicate entry in history.
- [ ] **Panel positioning:** Often missing multi-monitor support. Verify: connect an external monitor, open the panel. Does it appear on the correct screen (the one with the frontmost app)?
- [ ] **History retention:** Often missing the actual cleanup job. The setting exists but old items are never actually deleted. Verify: set retention to "1 day," wait, confirm old items are purged.
- [ ] **Search:** Often missing search across image OCR text or URL titles. Verify: copy a URL with a title, search for the page title.
- [ ] **Menu bar icon:** Often missing dark/light menu bar adaptation. Verify: switch macOS appearance, confirm the icon remains visible.
- [ ] **Launch at login:** Often missing. Users expect a menu-bar app to start at login. Verify: enable "Launch at Login," restart the Mac, confirm app is running.
- [ ] **Hotkey registration:** Often missing conflict detection. Verify: assign a hotkey already used by another app. Does Pastel detect the conflict and warn?
- [ ] **Memory after long use:** Often not tested. Verify: leave the app running for 48 hours with normal use, check memory in Activity Monitor. Should be stable, not growing.

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| NSPanel focus stealing (used SwiftUI Window instead) | HIGH | Must replace the entire panel implementation with NSPanel + NSHostingView. Cannot retrofit non-activating behavior onto SwiftUI Window. Budget 2-3 days for rewrite. |
| Images stored in database BLOBs | HIGH | Must write a migration that extracts BLOBs to files, updates references, and cleans up the database. Risk of data loss during migration. Budget 1-2 days plus testing. |
| No paste-monitoring pause (duplicate entries) | LOW | Add a `isPasting` flag and filter duplicates retroactively. Can be patched in a few hours. Existing duplicates can be cleaned with a one-time dedup script. |
| Polling on background thread (random crashes) | MEDIUM | Move all NSPasteboard calls to main thread. Audit all call sites. Budget 1 day. Crashes stop immediately. |
| Missing concealed type handling (passwords in history) | LOW | Add type checking in the capture pipeline. Existing sensitive items remain unless you provide a "purge sensitive" action. Budget a few hours. |
| UserDefaults for storage (data loss at scale) | HIGH | Must migrate to SQLite/SwiftData. Must design the schema, write the migration, handle edge cases. Budget 2-3 days. All data before migration is at risk. |
| Hardcoded single-edge panel | MEDIUM | Refactor panel positioning to use an enum-driven layout. The NSPanel itself is fine; it is the frame calculation and animation that need abstraction. Budget 1-2 days. |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| NSPasteboard polling misconfiguration | Phase 1: Core Monitoring | Timer interval is 0.5s, changeCount checked per tick, content read immediately on change. Battery impact <1% in Activity Monitor during idle. |
| Accessibility permission UX failure | Phase 1: Core + Phase 2: Onboarding | First launch: user sees explanation before system prompt. Paste works after granting permission. Graceful degradation if denied. |
| App Sandbox incompatibility with paste-back | Phase 0: Architecture Decisions | Decision documented: direct distribution, no sandbox. Entitlements file reflects this. |
| NSPanel focus stealing | Phase 1: Panel Infrastructure | Panel appears without changing the menu bar. Text selection in previous app is preserved. Cmd+V from panel pastes into previous app. |
| Image memory/storage OOM | Phase 1: Storage Architecture | Images stored as files. Thumbnails generated on background queue. Memory stable after copying 100 images. |
| CGEvent paste failures in specific apps | Phase 2: Paste-back Polish | Tested with Safari, Chrome, Terminal, VS Code, IntelliJ. Secure input detected and handled gracefully. No duplicate history entries during paste. |
| Sensitive data in clipboard history | Phase 2: Security | Concealed type items are detected. Auto-expiry implemented. "Clear All" action available. |
| Panel appearance latency >200ms | Phase 1: Panel Infrastructure | Panel window pre-allocated. Appearance time measured at <50ms. |
| Missing multi-monitor support | Phase 3: Polish | Panel appears on the screen with the frontmost app. Tested with 2+ monitors. |
| Unbounded history growth | Phase 1: Storage Architecture | Retention settings implemented. Disk budget enforced. Orphaned files cleaned up on item deletion. |
| No keyboard navigation | Phase 2: UX Polish | Arrow keys, Enter, Escape, Cmd+1-9 all functional. Full workflow achievable without mouse. |

## Sources

- Training knowledge of NSPasteboard, NSPanel, Accessibility APIs, and macOS app development patterns (MEDIUM confidence -- these are mature, stable Apple APIs but specific version details should be verified against current Xcode/macOS SDK documentation)
- Architecture patterns observed in open-source macOS clipboard managers: Maccy, Clipy, CopyClip (MEDIUM confidence -- based on training data, not live repository inspection)
- Apple Human Interface Guidelines for macOS menu bar apps and panel windows (MEDIUM confidence -- general patterns are stable, specific HIG wording should be verified)
- NSPasteboard threading model and changeCount semantics are documented in Apple's AppKit release notes and header documentation (HIGH confidence for the core API behavior, which has been stable since macOS 10.0)

**Note on confidence:** WebSearch and WebFetch were unavailable during this research session. All findings are based on training knowledge of well-established macOS APIs and patterns. The core API behaviors (NSPasteboard polling, NSPanel nonactivatingPanel, AXIsProcessTrusted, CGEvent posting) have been stable for many macOS versions and are unlikely to have changed. However, **specific macOS Sequoia (15.x) or macOS 16 changes should be verified** against current release notes before implementation.

---
*Pitfalls research for: macOS native clipboard manager (Pastel)*
*Researched: 2026-02-05*
