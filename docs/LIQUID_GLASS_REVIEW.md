# Liquid Glass panel investigation

Reviewed 2026-10-12 on macOS 26.3 with Xcode 26.2. The reported symptom is that the panel's glass becomes darker after clicking it or switching apps; it can look clearer while Pastel Settings is active.

## Confirmed construction

On macOS 26, `PanelController` embeds the SwiftUI panel in `NSGlassEffectView.contentView`. The panel window and hosting view have clear backgrounds. The older `NSVisualEffectView` branch runs only before macOS 26. The glass view defaults to the regular style in the tested runtime. This native glass setup was already present in the committed code before this investigation.

The panel is a key-capable, nonactivating `NSPanel` that does not become the app's main window. Settings is an activating `NSWindow` with a SwiftUI `NavigationSplitView`, sidebar, and native controls. Opening Settings therefore changes application and window focus as well as what appears behind the panel.

A debug build confirmed native glass, transparent inspected layers, Dark Aqua appearance, and disabled Reduce Transparency and Increase Contrast settings. It logged changes in application, key-window, and main-window state. The code has no panel-wide tint or opacity change tied to clicks. This evidence does not establish why the observed contrast change is so large.

## Experiments and decision

An opaque window background concealed the glass and was removed. Making the panel a main window succeeded while Pastel was active, but main status ended after switching apps and no visual improvement was confirmed, so that trial was removed. A standalone panel probe did not reproduce the production contrast change and was removed. The final product change from this work contains no glass rendering adjustment.

Apple describes different appearances for key and inactive windows, and regular Liquid Glass adapts the brightness of its backdrop for text legibility. `NSGlassEffectView` has no documented control to hold an active brightness independent of window focus. A focus-dependent system response is plausible, but the exact cause and a fix for Pastel remain unverified. [Apple: Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)

A future fix needs a controlled comparison of the live panel before and after click, with Settings open and closed, and after switching apps, while holding the desktop backdrop constant. Check legibility across light and dark backdrops before choosing the more translucent clear glass style. Keep the nonactivating paste workflow intact.
