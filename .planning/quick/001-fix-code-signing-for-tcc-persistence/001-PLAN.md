---
phase: quick
plan: 001
type: execute
wave: 1
depends_on: []
files_modified:
  - project.yml
autonomous: true

must_haves:
  truths:
    - "Xcode builds Pastel with Apple Development certificate (not ad-hoc)"
    - "Binary CDHash is stable across rebuilds when source is unchanged"
    - "macOS TCC remembers Accessibility permission across Xcode rebuilds"
  artifacts:
    - path: "project.yml"
      provides: "Automatic signing configuration"
      contains: "CODE_SIGN_STYLE: Automatic"
  key_links:
    - from: "project.yml"
      to: "Pastel.xcodeproj/project.pbxproj"
      via: "xcodegen generate"
      pattern: "CODE_SIGN_STYLE.*Automatic"
---

<objective>
Fix code signing so macOS TCC persists Accessibility permission across Xcode rebuilds.

Purpose: Currently project.yml uses `CODE_SIGN_IDENTITY: "-"` (ad-hoc signing), which produces a different CDHash on every rebuild. macOS TCC uses CDHash to track which apps have Accessibility permission, so the permission is lost after every build. Switching to automatic signing with the user's Apple Development certificate produces a stable identity that TCC can track.

Output: Updated project.yml with automatic signing, regenerated Xcode project, verified build succeeds with certificate signing.
</objective>

<execution_context>
@/Users/phulsechinmay/.claude/get-shit-done/workflows/execute-plan.md
@/Users/phulsechinmay/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@project.yml
@Pastel/Resources/Pastel.entitlements
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update project.yml signing configuration and regenerate Xcode project</name>
  <files>project.yml</files>
  <action>
In project.yml, replace the ad-hoc signing line and add automatic signing settings. Make these exact changes in the `targets.Pastel.settings.base` section:

1. Remove: `CODE_SIGN_IDENTITY: "-"`
2. Add the following three settings (order does not matter, but place them where CODE_SIGN_IDENTITY was):
   - `CODE_SIGN_STYLE: Automatic`
   - `DEVELOPMENT_TEAM: QLSJ39DRSH`
   - `CODE_SIGN_IDENTITY: "Apple Development"`

The result should look like:
```yaml
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: QLSJ39DRSH
        CODE_SIGN_IDENTITY: "Apple Development"
```

Do NOT add App Sandbox entitlements -- the entitlements file must remain an empty dict. Pastel is distributed directly (not via App Store) and needs unsandboxed access for paste-back via CGEvent.

After editing project.yml, regenerate the Xcode project:
```bash
cd /Users/phulsechinmay/Desktop/Projects/pastel && xcodegen generate
```

This will overwrite Pastel.xcodeproj/project.pbxproj with the new signing settings.
  </action>
  <verify>
1. Confirm project.yml contains `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: QLSJ39DRSH`, and `CODE_SIGN_IDENTITY: "Apple Development"` (and does NOT contain `CODE_SIGN_IDENTITY: "-"`)
2. Confirm xcodegen exited 0
3. Run: `xcodebuild -project Pastel.xcodeproj -scheme Pastel -configuration Debug build CODE_SIGN_ALLOW_PROVISIONING_UPDATES=YES 2>&1 | tail -5` -- should show BUILD SUCCEEDED
4. Run: `codesign -dv Pastel.xcodeproj/../build/Build/Products/Debug/Pastel.app 2>&1 | grep -E "Authority|TeamIdentifier"` -- should show Apple Development authority and team QLSJ39DRSH (if build output location is accessible; may need `xcodebuild -showBuildSettings | grep BUILD_DIR` to find the path)
  </verify>
  <done>
project.yml uses automatic signing with team QLSJ39DRSH. Xcode project regenerated. Build succeeds with Apple Development certificate. The binary is signed with a stable identity that macOS TCC can track across rebuilds.
  </done>
</task>

</tasks>

<verification>
- project.yml no longer contains `CODE_SIGN_IDENTITY: "-"`
- project.yml contains `CODE_SIGN_STYLE: Automatic` and `DEVELOPMENT_TEAM: QLSJ39DRSH`
- `xcodegen generate` succeeds
- `xcodebuild build` succeeds with certificate signing
- Pastel.entitlements remains an empty dict (no sandbox)
</verification>

<success_criteria>
Pastel builds with Apple Development certificate signing. The binary identity is stable across rebuilds, allowing macOS TCC to persist Accessibility permission without re-prompting.
</success_criteria>

<output>
After completion, create `.planning/quick/001-fix-code-signing-for-tcc-persistence/001-SUMMARY.md`
</output>
