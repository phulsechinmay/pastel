# perf-regression-fix — discussion plan (draft, no code changes yet)

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
