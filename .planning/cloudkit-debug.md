# CloudKit Sync Debugging — DMG/Developer ID Builds

## Problem
iCloud sync works when building the Sparkle variant from Xcode, but does NOT work when installing the app from a GitHub Releases DMG (built via `build-release.sh`).

## Environment Difference
| Build | Signing | CloudKit Environment |
|---|---|---|
| Xcode (Debug-Sparkle / Release-Sparkle) | `Apple Development` | **Development** |
| DMG (`build-release.sh`) | `Developer ID Application` | **Production** |

Development and Production are **completely separate databases** — records in one don't exist in the other.

## What Was Fixed
1. **Deployed CloudKit schema to Production** via CloudKit Dashboard (manual step, permanent/append-only)
2. **Changed `aps-environment` to `production`** in `Pastel/Resources/Pastel-Sparkle.entitlements` (was `development`)
3. **Verified entitlements** in the exported DMG app via `codesign -d --entitlements -`:
   - `aps-environment`: `production`
   - `icloud-container-environment`: `Production`
   - `icloud-container-identifiers`: `iCloud.app.pastel.Pastel`
   - `icloud-services`: `CloudKit`
   - All correct.

## Current Symptom (after fixes)
- DMG app shows **"Fully up to date"** in sync settings
- But **zero records appear in CloudKit Production** dashboard
- **No export events fire** — new clipboard items are captured locally but never trigger `NSPersistentCloudKitContainer.eventChangedNotification` export events
- The "Fully up to date" state comes from `SyncMonitor.checkAccountStatus()` which queries `CKContainer` directly (account IS available), NOT from actual sync events completing

## Key Evidence from `log stream`
Ran: `log stream --predicate 'process == "Pastel" OR (process == "cloudd" AND composedMessage CONTAINS "pastel")'`

- Clipboard monitoring works: `Captured <private> item from <private> (2617 bytes)`
- Pasteboard reads/writes all working normally
- **ZERO CloudKit, CoreData sync, or NSPersistentCloudKitContainer log entries**
- No setup events, no import events, no export events
- No errors logged either

## Root Cause Hypothesis
**SwiftData is silently falling back to a local-only `NSPersistentContainer`** instead of creating an `NSPersistentCloudKitContainer`, despite `ModelConfiguration(cloudKitDatabase: .private("iCloud.app.pastel.Pastel"))` being specified.

Evidence:
- No `eventChangedNotification` fires at all (not even setup/import on first launch)
- The Xcode build (same code, same config, same `syncEnabled` flag) DOES fire events
- The only difference is signing identity: `Apple Development` vs `Developer ID Application`

## Previous Symptom (before clearing local store)
When the DMG app had a local store with data from a previous Xcode-built run:
- Sync was **"forever stuck as Syncing"**
- This was likely because the store had sync metadata from the Development CloudKit environment, causing a mismatch when connecting to Production

After deleting `~/Library/Application Support/Pastel/*.store*` and relaunching:
- Sync shows "Fully up to date" (but no actual sync happening)

## Next Debugging Steps

### 1. Broader log filter for CoreData subsystem
```bash
log stream --predicate 'process == "Pastel" AND (subsystem CONTAINS "coredata" OR subsystem CONTAINS "cloudkit" OR eventMessage CONTAINS "CloudKit" OR eventMessage CONTAINS "CKError" OR eventMessage CONTAINS "persistent")' --level debug 2>&1 | head -50
```
This might capture CoreData framework messages about WHY the container isn't using CloudKit.

### 2. Add startup diagnostic logging in PastelApp.init()
After `ModelContainer` creation (~line 77 of PastelApp.swift), add:
```swift
// Diagnostic: verify CloudKit container type
let stores = container.mainContext.container  // check underlying container
logger.info("ModelContainer created, syncEnabled=\(syncEnabled)")
logger.info("Store URL: \(config.url)")
```
Also check if the underlying `NSPersistentStoreCoordinator` has `NSPersistentCloudKitContainerOptions` on its store descriptions.

### 3. Verify with manual CKRecord write
Test if the app CAN write to CloudKit Production at all, independent of SwiftData:
```swift
let ckContainer = CKContainer(identifier: "iCloud.app.pastel.Pastel")
let db = ckContainer.privateCloudDatabase
let record = CKRecord(recordType: "TestRecord")
record["testField"] = "hello" as CKRecordValue
try await db.save(record)
```
If this fails, it's a CloudKit Production access issue. If it succeeds, it's a SwiftData/NSPersistentCloudKitContainer issue.

### 4. Check if Developer ID + CloudKit Production requires specific provisioning
Research whether `NSPersistentCloudKitContainer` has known limitations with Developer ID signing on macOS. Apple's documentation primarily covers App Store distribution.

### 5. Try `com.apple.developer.icloud-container-environment` entitlement
The DMG app's codesign output showed `icloud-container-environment: Production` was injected automatically during export. But what if explicitly setting it in the entitlements file helps SwiftData recognize the environment?

Add to `Pastel-Sparkle.entitlements`:
```xml
<key>com.apple.developer.icloud-container-environment</key>
<string>Production</string>
```

## Files Involved
- `Pastel/PastelApp.swift` — ModelContainer creation (lines 55-77), sync service init (lines 96-107)
- `Pastel/Services/SyncMonitor.swift` — sync event monitoring
- `Pastel/Resources/Pastel-Sparkle.entitlements` — Sparkle build entitlements (aps-environment now `production`)
- `Pastel/Resources/Pastel.entitlements` — AppStore build entitlements (aps-environment still `development`)
- `build-release.sh` — DMG build script (archives with Developer ID, notarizes)
- `project.yml` — XcodeGen config, build settings

## CDMR Record Type
`CDMR` = "Core Data Mirrored Relationship". Internal record type created by `NSPersistentCloudKitContainer` to represent many-to-many relationships (e.g., `ClipboardItem ↔ Label`) in CloudKit, which doesn't natively support them. Each CDMR record = one link in the relationship.

## CloudKit Schema Notes
- Schema deployed to Production is **append-only** (can add fields/record types, cannot delete/rename/change types)
- Record types in Production: `CD_ClipboardItem`, `CD_Label`, `CD_CDMR`
- Development and Production share schema structure but have completely separate data stores
