# perf-regression-fix — discussion plan (draft, no code changes yet)

## Revised plan v2 — new click evidence + safe logging (2026-10-28)

### New evidence that changes the ranking

The user reports the freeze is **not paste-specific**. The same
beachball happens on:

- clicks on panel items,
- the settings button in the panel — the Settings window *opens*
  but then freezes,
- the Pastel menu-bar icon — the dropdown *never opens* and freezes.

Checked code, and this matters:

- `StatusPopoverView` (the menu-bar dropdown) does **no store fetch
  at all** — it is buttons bound to `AppState` / `ClipboardMonitor`
  state. A dropdown that never opens therefore means the **main
  thread / main runloop is already blocked globally**, not that the
  menu-bar code itself is slow.
- The Settings window is created synchronously
  (`SettingsWindowController.showSettings`, `@MainActor`), and its
  History tab goes through the same `HistoryPageLoader` /
  `HistoryPageCursor` machinery as the panel (first page 12, then
  100, up to 300 resident), with the same main-context model
  resolution. So Settings freezing after opening is consistent with
  the same shared-store / main-actor block, not a separate Settings
  bug.
- Consequence: **paste-image TIFF on the main actor is demoted
  from "top suspect" to "one of several main-thread suspects".**
  It can still beachball a paste click, but it cannot explain a
  menu-bar dropdown that never opens. The fix must therefore
  address main-actor work globally, not just the paste path.

### Revised P0, in order

1. **Move startup work off the main actor, and stagger it.**
   - `RetentionService` is `@MainActor` and runs an immediate purge
     on the main context at startup. Move the purge to a background
     `ModelContext` (own container context, batched saves), and
     defer the first purge until the index reports `ready` (or at
     least until the panel's first page is shown). A purge must
     never compete with first paint.
   - `backfillLabelIndex` runs synchronously on the main actor in
     `setup()` (bounded to 200 + 200, so not the whole hang, but
     still main-thread store work at launch). Move it to a
     background context, or run it after first paint.
   - Do not auto-open the panel 0.5 s after launch into a rebuild
     storm; either delay auto-open until the first page can be
     served from a ready/partial index, or open it with the stale
     / partial page and an "indexing…" state (see browsing fix
     below).
2. **Let browsing use the partial index (was P1-adjacent, now P0).**
   `browsingIDs()` returns `nil` unless `ready`, while
   `matchingIDs()` already serves a partial index while rebuilding.
   Change browsing to serve the indexed subset while rebuilding,
   marked incomplete in the UI, instead of falling back to a full
   SwiftData offset scan for the default panel — and for the
   Settings History tab, which uses the same loader.
3. **Keyset pagination + type-split large pass + checkpointed
   externalise** (unchanged from v1: see P0 items 1–3 below).
   This reduces the shared-store contention that is blocking the
   main thread, rather than just making the rebuild faster in
   isolation.
4. **Kill the reset loop + second sync rebuild** (unchanged from
   v1: delta reconciliation, narrow dirty flag, incremental sync
   refresh).
5. **Panel / Settings reload storm** (unchanged from v1, now
   extended to `HistoryGridView`): gate `searchIndexRevision`
   reloads while building, never empty the visible list or disable
   hit-testing during a replace, cap restore size — in both
   `FilteredCardListView` and `HistoryGridView`.
6. **Main-context page resolution: bound it.**
   `HistoryPageLoader.nextPage` is `@MainActor` and resolves IDs
   on the main context, yielding only every 8 items. Cap the
   synchronous resolution work per runloop turn, use
   `propertiesToFetch`-style lightweight resolution where the UI
   only needs identity/sort keys for the first paint, and never
   fault a large external payload on the main thread to decide
   whether a row matches (that faulting belongs in the worker).
   If a page cannot be resolved promptly, show the previous page
   rather than blocking the runloop.
7. **Paste-image decode off the main actor** (still in scope, now
   P1, not P0): move `Data(contentsOf:)` + `NSImage` + TIFF
   conversion in `PasteService.representations()` to a background
   task; the pasteboard write itself stays on the main actor.
   Same treatment for per-card app-icon TIFF conversion in
   `AppIconColorService` / `AppIconCache` where it still runs
   synchronously on the main actor.

### Logging design — diagnostics without clip content (P0, ships with the fix)

Goal: the next hang must be diagnosable from `log stream`
alone, without ever logging anything a user copied.

**Hard rules (non-negotiable, enforced in review):**

- NEVER log: clip text, HTML, RTF, URLs, file paths, image data
  or filenames, titles, source app names, bundle IDs, label
  names/IDs, search text, content hashes, or persistent IDs.
  These are all either clip content or content-derived identifiers.
- ONLY log: phase names, counts, durations in ms, batch sizes,
  offsets/cursors (as numbers), content-type *counts aggregated
  by type* (e.g. `image: 412, text: 9031` — never per-item), size
  buckets (e.g. `<=64KiB`, `64KiB-1MiB`, `>1MiB` counts), boolean
  flags (`ready`, `dirty`, `rebuilding`), trigger names
  (`searchIndexRevision`, `itemCount`, `filter`, `settingsOpen`
  — never the filter value or search string), and error *kinds*
  (e.g. `outOfSync`, `database`) without payloads.
- All `Logger` interpolations for numbers/durations use
  `privacy: .public` explicitly; no string interpolation of any
  item field is allowed in a log call. A grep-based check for
  forbidden interpolations in logging calls is part of the
  test/CI story for this branch (see Tests below).
- Log volume must not itself become the hang: log per phase
  transition, per 1,000 indexed items, per batch *only if that
  batch took > 50 ms*, and a summary at completion/failure.
  No per-item logging, ever.

**Breadcrumb log points (start + end, so a hang leaves a last
line pointing at the blocker):**

- `AppState.setup`: start, `wasDirty` (bool), index phase at
  start, retention days (integer setting only), monitor started.
- `ClipboardSearchIndex.rebuild`: phase transitions
  (`small` → `large` → `complete`), per-1,000 cumulative indexed
  count + elapsed, slow-batch warnings (> 50 ms) with batch size
  and size-bucket counts only, final `ready` + total elapsed,
  and on failure the error kind + indexed-vs-expected counts
  (numbers only) for a count mismatch.
- `externalizeLegacyLargeClips`: start/end, per-batch changed
  count and skipped count (numbers only), final walked/changed
  totals. This is how we will prove whether it still walks the
  whole large set on every launch after the fix.
- `applyChanges` (didSave path): upserted/deleted *counts*,
  elapsed, failure kind. This shows whether save-time index
  updates are queueing behind the rebuild.
- Panel + Settings first page: trigger name, index mode vs
  fallback mode (bool), page size, cursor offset, elapsed,
  first-page-ready. Never the search string, label, or app filter
  value. A reload that starts but never logs "ready" is the
  smoking gun for the reload storm.
- Retention purge: batch elapsed, purged/kept counts, cutoff
  days. Proves whether the purge is still running during first
  paint.
- Paste: content type only, size bucket, elapsed for decode vs
  write separately. Proves whether a paste click is the beachball
  or an innocent bystander.
- Thumbnail decode: cache hit/miss counts and slow-decode
  warnings (> 100 ms) with size bucket only, no filename.
- Settings / menu-bar: `showSettings` start with tab name
  (enum name only, e.g. `general`/`history` — not user content),
  Settings first-page-ready, menu-bar popover appear. If the
  dropdown never logs "appear", the main thread was already
  blocked before it — which is itself the diagnosis.
- Use `OSLog` signposts (`os_signpost`) around rebuild batches
  and panel page loads in addition to log lines, so Instruments
  can show the same timeline without any content.

**What logging must NOT do:** it must not change behaviour
(no logging-gated logic), must not write clip-derived data to
disk beyond the existing OSLog stream, and must not be
configurable to a "verbose" mode that logs content — there is
no such mode in this branch, by design.

### Tests added by v2

- A source-grep test asserting no logging call interpolates a
  forbidden item field (text, title, URL, path, hash, bundle ID,
  label, search text).
- A 100k-item, image-heavy fixture (as in v1 P2) asserting:
  rebuild + externalise time, resume-after-interrupt, no reset
  on count drift, externalise skips images, panel/Settings first
  page while rebuilding serves the partial index, and a
  `searchIndexRevision` bump does not empty the visible list
  in either surface.
- A main-thread regression check where feasible in the harness:
  no known main-actor operation (purge batch, page resolution,
  paste decode) is allowed to run synchronously for > 50 ms on
  the fixture without yielding or moving off-main — measured
  via the breadcrumb logs, not by asserting exact timings.

### What v2 deliberately does NOT change

- No change to what is stored, synced, or retained; no new
  required model field in this slice (the keyset cursor uses
  timestamp + overlap first; a sequence column remains a
  follow-up only if overlap handling proves fiddly).
- No "verbose logging" toggle, no content-bearing diagnostics,
  no telemetry upload — logs stay in the local OSLog stream
  the user can already view with `log stream`.


## Problem, in one paragraph

v1.0.19 (v1.0.18 → v1.0.19, performance merge `ae4718b`) can hang on
startup on a large, pre-existing store — panel appears, a click or two
works, then the app stops responding. The prime suspect is not a schema
rejection and not URL fetching on startup. It is a first-launch,
whole-history search-index rebuild plus a legacy-large-clip migration,
both using offset pagination over an unindexed sort, with every image
forced through a 2-item-at-a-time pass — and a reset loop that can
discard progress on the next launch. This document is the fix proposal
to discuss before any of it is implemented. Nothing here is merged.

## Evidence (all from v1.0.19 code, no crash log available)

- `Pastel/Services/ClipboardSearchIndex.swift` `rebuild()`:
  `fetchLimit = large ? 2 : 128`, `fetchOffset = offset`, sorted
  `timestamp DESC`, no keyset cursor, no SwiftData index on
  `timestamp`/`byteCount` in `ClipboardItem`.
- An image's `byteCount` is its raw PNG/TIFF size
  (`ClipboardMonitor.processImageContent`), so essentially every image
  is `> 64 KiB` and lands in the 2-at-a-time large pass.
  20,000 images = 10,000 sequential, increasingly expensive fetches.
- `externalizeLegacyLargeClips()` repeats the pattern: `fetchLimit = 2`,
  `fetchOffset`, no persisted checkpoint, no type filter — images are
  re-walked just to do nothing.
- `Pastel/App/AppState.swift` `setup()`: any `ModelContext` save sets
  `pastelSearchIndexDirty`; a force-quit mid-save makes the next launch
  call `resetAndRebuild()`, wiping the `build_state` phase/offset
  checkpoint. `rebuild()` also throws `outOfSync` unless the indexed
  count exactly equals the live SwiftData count, even though the
  monitor, retention purge, and sync mutate the store concurrently
  and shift the offset cursor.
- `Pastel/PastelApp.swift`: the panel auto-opens 0.5 s after launch,
  while the rebuild is still running. While the index is not `ready`,
  `browsingIDs()` returns `nil`, so the panel falls back to a
  SwiftData offset scan. The first page (12 items) is cheap — hence
  "a click or two" — then every save bumps `searchIndexRevision`
  (150 ms debounce) and `FilteredCardListView.onChange` runs
  `reload(scanAll: true)`, restoring up to 150 items, emptying
  `visibleItems` and disabling hit-testing while replacing.
- The project's own `docs/PERFORMANCE_UPGRADE_PLAN.md` benchmark:
  50,000 ordinary clips took 33.6 s to index, peaking at 635 MB RSS
  in a synthetic harness. 100k+ with many images extrapolates to
  minutes, not seconds.

## Recommended fixes, ranked

### P0 — stop the rebuild from being quadratic and image-bound

1. **Keyset pagination for `rebuild()` and `externalizeLegacyLargeClips()`.**
   Replace `fetchOffset` with a cursor: next batch is
   `timestamp < lastTimestamp` (with an overlap window for equal
   timestamps, made safe because `upsert()` is already
   fingerprint-idempotent), or, cleaner long-term, a monotonic
   sequence column on `ClipboardItem` backfilled once by timestamp
   order. Add a SwiftData index on the sort key so even the remaining
   scans are index scans, not full sorts. This is the single biggest
   win and should land first, alone if needed, so its effect is
   measurable.
2. **Split the large pass by type, and raise its batch size.**
   The 2-item batch exists to avoid materialising giant text payloads.
   It should apply only to types that can actually hold giant text:
   text / richText / code, plus large HTML/RTF. Images, files, colours
   and URLs should go through a metadata-only path (title/app/labels,
   empty FTS body) at the 128-item batch size. For images this also
   means: do not FTS-tokenise a body that is always empty.
   Same split for `externalizeLegacyLargeClips()`: only items with a
   large `textContent`/`htmlContent`/`rtfData` (and an externalisable
   type, per `ClipboardItem.canExternalize`) are candidates — images
   are excluded by construction, not by accident.
3. **Checkpoint the externalise pass.**
   Persist its cursor in `build_state` (new phase, e.g. `externalize`,
   plus last timestamp) and commit it per batch, exactly as `rebuild()`
   already does for its own phases. A kill mid-pass must resume, not
   restart from zero.

### P0 — stop the reset loop (make a slow launch converge, not repeat)

4. **Replace the exact-count reset with delta reconciliation.**
   Snapshot the expected count at rebuild start and compare against
   that, not the live count. On a mismatch, do not `resetTables()`:
   keep the index `ready`, log the delta, and reconcile it in the
   background (missing IDs upserted, stale IDs removed — the
   `applyChanges` machinery already exists for this). Reserve a full
   reset for genuinely corrupt/missing index tables or a schema
   version change.
5. **Narrow the dirty flag.**
   `pastelSearchIndexDirty` should mean "there are unapplied saves",
   not "rebuild from scratch". On launch, a dirty index should get a
   bounded delta pass, not `resetAndRebuild()`. The `didSave` observer
   already applies changes incrementally; the flag should only force
   a reset if that incremental path has failed repeatedly or the
   index file is unusable.
6. **Do not run a second full rebuild after a sync import.**
   `AppState.refreshSearchIndexAfterSync()` currently queues
   `resetAndRebuild()` (via `pendingSyncIndexRefresh`) after the
   initial rebuild. Change it to an incremental `applyChanges` pass
   for the imported IDs, or at most a delta reconciliation as in (4).
7. **Pause competing mutations during the rebuild — or snapshot it.**
   Either defer the first retention purge until the index reports
   `ready` (retention is hourly anyway; one launch's delay is
   harmless), or run the rebuild against a frozen snapshot of IDs
   taken at start and reconcile the delta afterwards. Both remove
   the "insert shifts the offset cursor, row skipped, count
   mismatches, reset" failure mode. Deferring the purge is the
   smaller change; snapshotting is the more correct one. Pick one
   in discussion.

### P0 — stop the panel reload storm

8. **Gate `searchIndexRevision` reloads.**
   Do not run `reload(scanAll: true)` on every revision bump while
   `searchIndexBuilding` is true. Reload on the transition to
   `ready`, and otherwise coalesce background saves into the existing
   150 ms debounce without resetting the cursor or growing the
   resident set to 150. A background index completion must not evict
   the page the user is looking at.
9. **Never empty the visible list during a replace.**
   Keep showing the stale page (with a subtle "updating" indicator)
   while a replacement loads, and keep hit-testing enabled for it.
   The current `visibleItems = []` + `allowsHitTesting(false)` during
   `isReplacingResults` is what turns "slow" into "dead after a
   click or two".
10. **Cap the restore size.**
    `scanAll` restoring to the 150-item maximum on every revision
    bump is disproportionate. Restore only to the selected index
    plus one page, not the maximum, unless the user actually scrolled
    there.

### P1 — per-click stalls and un-cancellable work

11. **Make thumbnail decodes cancellable and paste decoding
    off the main actor.**
    `AsyncThumbnailView.onDisappear` currently does not cancel the
    underlying decode, and the thumbnail queue is capped at 2
    concurrent decodes with a 100-item / 48 MB cache — fast scrolling
    through image history queues decodes that complete after the
    card is gone. Cancel on disappear (propagate `Task` cancellation
    into `ThumbnailLoader`), and move `PasteService` image
    materialisation (`Data(contentsOf:)` + TIFF conversion) off
    `@MainActor`. These are per-click seconds, not the permanent
    hang, but they are the most direct "click → freeze" path left
    after P0.
12. **Fix the SQLite progress-handler cancellation.**
    `matchingIDs()` / `browsingIDs()` install a progress handler that
    checks `Task.isCancelled` of whatever task happens to be running
    on the index actor — it cannot see the caller's cancellation.
    Pass an explicit cancellation token/flag per query so a
    superseded search actually interrupts its FTS scan instead of
    queueing behind it.

### P1 — make the next hang diagnosable

13. **Log index progress, not just completion/failure.**
    Phase, indexed/total, elapsed time, and the reason for any reset
    (dirty flag, count mismatch with both counts, schema version)
    to Console on a throttled cadence. Without this, the next report
    of "it hangs" is again indistinguishable between "rebuild still
    running", "reset loop", and "panel reload storm".

### P2 — tests and rollout

14. **Regression fixtures at real scale.**
    Extend `Tests/PerformanceRolloutBenchmark.swift` /
    `PerformanceUpgradeSmoke.swift` with a 100k-item fixture that
    is image-heavy (e.g. 20k images, 50k URLs, large texts) and assert:
    rebuild time and peak RSS, resume-after-interrupt (stop the
    rebuild mid-pass, restart, assert it does not restart from
    zero), count drift during rebuild does not trigger a reset,
    externalise skips images, and a `searchIndexRevision` bump does
    not empty the visible panel list.
15. **Rollout note — one last rebuild may be unavoidable.**
    If the `build_state` format changes (new cursor columns), bump
    the schema version carefully: migrate `build_state` in place and
    preserve a `complete` index, rather than dropping the tables as
    `open()` does for `< 6`. If a drop is unavoidable, it should be
    a one-time cost paid with the new fast path, and the release
    notes should say so. Ship as 1.0.20, not as a silent patch to
    1.0.19, so the laptop's behaviour change is attributable.

## Alternatives considered, not recommended as the fix

- **Just raising the large batch from 2 to 128.** Helps round trips
  but does not fix offset-quadratic scans, the reset loop, or the
  panel storm. Worth doing as part of (2), not instead of it.
- **Just deferring the panel auto-open.** Hides the symptom for
  0.5 s; the rebuild still runs, still loops, and the first manual
  panel open hits the same fallback + reload storm.
- **Deleting the index on every launch / disabling the index.**
  Throws away the v1.0.19 search/paging win entirely and returns
  the panel to a full-history scan. The index is the right idea;
  its rebuild and lifecycle are the bug.
- **Telling large-store users to reduce history / retention.**
  A workaround for one laptop, not a fix for a shipped regression
  at the exact scale the performance upgrade was meant to serve.

## Update 2026-10-28 — beachball confirmed on the laptop

The user reports a genuine spinning beachball after the first two
clicks, not just unresponsive clicks. That narrows the field: the
main thread is not returning to the runloop, not merely starved by
background work. The reload storm alone (empty `visibleItems` +
hit-testing off) explains unresponsive clicks, but not a beachball.

Main-thread suspects, in order, pending a spindump to confirm which
one is actually on the stack:

1. **Paste of an image card** (`PasteService`, `@MainActor`):
   `representations()` does `Data(contentsOf:)` +
   `NSImage(data:)` + `tiffRepresentation` synchronously on the main
   actor. For a large screenshot this is a full decode plus an
   uncompressed TIFF expansion on the UI thread — a direct
   click → beachball path, and it fits "after a click or two" if
   the clicks are card activations.
2. **Main-context store waits during page resolution**
   (`HistoryPageLoader.nextPage`, `@MainActor`): after the worker
   returns IDs, each model is resolved on the main context, yielding
   only every 8 items. If the rebuild / retention purge /
   externalise save is holding the SwiftData store, those
   resolutions can block the main thread.
3. **Retention purge on the main actor** (`RetentionService`,
   `@MainActor`): runs immediately at startup, fetching and saving
   on the main context in 25-item batches. With store contention
   from the rebuild, a purge batch can stall the main thread while
   the user is clicking.
4. **Per-card app-icon work on the main actor**
   (`ClipboardCardView.task` → `AppIconCache.icon` +
   `AppIconColorService.dominantColor` TIFF conversion, before the
   detached colour extraction): first appearance of many distinct
   app icons does Launch Services lookups and TIFF conversion on
   the main thread, multiplied across a 150-item reload.

What is *not* a beachball suspect on its own: `ThumbnailLoader`
decodes on a background queue with `ShouldCacheImmediately`, and
the index rebuild itself runs as a `.utility` task off the main
actor. If the spindump shows the main thread in neither (1)–(4),
the next suspect is a main-thread wait on a SwiftData store lock
held by a background context — which the sample's lock/wait frames
would show.

Diagnostic that settles it: a process sample / spindump captured
while the beachball is showing (Activity Monitor → Pastel →
Sample Process, or `sample Pastel 5` from Terminal), plus what the
two clicks were (card paste? filter/label chip? search? scroll?).

## Open questions for discussion

1. Keyset cursor: timestamp + overlap window (minimal, no model
   migration) vs. a new monotonic sequence column (cleaner, but a
   model migration + one backfill)? My recommendation: timestamp
   cursor first, sequence column only if the overlap handling
   proves fiddly in review.
2. Rebuild mutations: defer the first retention purge (small) vs.
   snapshot IDs at rebuild start (correct)? 
3. Should the fix land as one PR or as stacked P0 slices
   (pagination → reset loop → panel storm), each measurable
   separately? My recommendation: stacked slices, in that order.
4. What is the acceptance bar: a named fixture size/time (e.g.
   100k items, 20k images, rebuild under X s on the laptop's class
   of machine) before this leaves draft?
