# Performance upgrade plan

Branch: `codex/perf-upgrade`  
Baseline: in an isolated 10,000-item SwiftData fixture, fetching/filtering the full set took 2.7 seconds and peaked at 337 MiB of process RSS; a bounded 50-item fetch took 100 ms and 28 MiB. The current code heuristic took 3.25 seconds on a 10 MiB synthetic text clip. These are component measurements, not live panel timings.

The goal is to make panel latency and memory depend on a small visible working set, while keeping full clipboard content available for paste, export, sync and complete history search. Large clips may appear in search later than small clips. Search must indicate when indexing or result loading is still in progress.

## 0. Stabilize large clips first

- Bound card preview generation by bytes and lines. Never hand a multi-megabyte string to `Text` or HighlightSwift to draw a four-line card. Preserve original content without truncation.
- Run the synchronous code heuristic on a bounded sample; cap language detection input and expensive detection jobs. Preserve the `code` classification for obvious code and allow later enrichment.
- Give highlighted previews and decoded thumbnails byte-aware cache budgets. Separate full-size image viewing from the card thumbnail cache; coalesce repeated decode requests.
- Resolve selected labels and their index tokens once per filter pass, rather than once per history item.
- Add duration and size logging for capture, heuristic, highlight, thumbnail decode, panel open and search. Log lengths/IDs, never copied content.
- Cover large unbroken lines, multi-line code, Unicode, edits and repeated scroll/filter cycles with a synthetic fixture.

**Exit condition:** A 10 MiB text copy cannot drive multi-second synchronous classification or whole-document card highlighting. The full text still pastes and exports. Stress testing does not retain large rendered strings after cards disappear.

## 1. Bound panel and History browser results

- Add an explicit result service that returns pages of stable IDs. Keep a bounded number of pages resident; release distant pages and work when the panel is hidden.
- Move visibility, type, app and date restrictions into fetches. Fetch pinned and normal results in stable order with a tie-breaker. For labels, use a queryable membership index or scan only bounded metadata batches in a worker until a full page of matching results is found; never filter a limited page and silently miss older matches.
- Preserve selection, hotkey order, anchor and visible scroll position through capture, recopy, relabel, deletion/undo, filtering and search updates. Use an explicit result generation so property mutations invalidate cached membership.
- Keep full clipboard payloads out of summary fetches. Introduce small preview/metadata records and defer large plain/HTML/RTF reads until requested. Verify generated SQL and retained models on supported macOS versions; projection alone is insufficient.
- Apply the same result service to the Settings History browser. Keep bulk selection by IDs, fetching selected payloads in bounded batches at action time.

**Exit condition:** Initial and filter page cost stays close to flat from 10,000 to 100,000 items; only a few pages and capped caches remain live. Old labeled/pinned results stay reachable.

## 2. Index search with gradual backfill

- Prototype a separate, owned SQLite FTS5 index over item IDs, plain text, title and app name. Compare word and trigram tokenization against the product's literal substring behavior, including 1–2 character queries, code punctuation, URLs and Unicode.
- Return the newest matching page first. Cancel stale searches; publish only the latest query. Process large-item indexing asynchronously with a byte and job budget. Show progress or an explicit incomplete-results state while backfill catches up.
- Use immutable item identity and durable change tracking for insert, edit, recopy, delete/undo, import, retention and CloudKit updates. Checkpoint only after index commits; rebuild after loss or corruption. Never index concealed items.
- Keep the existing full-body search until the new index is fully populated and verified. Move large payloads to external storage only after search can still find text beyond the preview.

**Exit condition:** Rare/deep and no-result queries remain responsive at 100,000 items; common terms, short queries and older large matches preserve correct ordering and reachability. An interrupted backfill resumes without duplicate or missing results.

## Measurement and rollout

Measure release builds at 1,000, 10,000, 50,000 and 100,000 items with small text, 64 KiB/1 MiB/10 MiB clips, rich text, images, many labels, pins and sync imports. Record p50/p95 first visible panel frame, filter switch, search first results, scroll hitches, main-thread stalls, steady/peak RSS and index size. Use Time Profiler, Hangs, SwiftUI Instruments, Allocations and SQL logging on synthetic data. Proposed targets: warm first useful panel/filter result under 100 ms at p95; ordinary search first page under 100 ms after debounce; no sustained memory climb after search/scroll/hide cycles. Adjust thresholds against actual device measurements.

Implement each stage behind separately reviewable changes. Use additive/resumable schema migration and never block launch on a whole-history rewrite. Check the actual minimum macOS policy before using SwiftData `#Index` (macOS 15+); the current project declares macOS 14 while the README says 15+.

## Progress on this branch

All three implementation stages are now represented on this branch:

- **Large clips:** card and code previews are bounded to 4 KiB/10 lines, classification input to 8 KiB/160 lines, and highlighted/decoded thumbnail caches have explicit cost limits. Thumbnail decodes coalesce. New plain, HTML, and RTF payloads over 64 KiB use external storage; older large clips migrate in two-item background batches. Paste, export, drag, edit, and search read the full payload when needed. Capture logs duration and size, never copied content. In a component check, the bounded code heuristic processed a 12 MB synthetic input in a 2.8 ms median over five runs.
- **Bounded history:** the panel and Settings History use an actor-owned page worker, with 50/100-result pages and 150/300-result resident windows. SQLite metadata indexes handle label, type, app, date, pin and time browsing after backfill. Until then, bounded background scans preserve old pinned and sparse-label matches. Older windows are reachable through explicit controls; Cmd+A in Settings selects only loaded items and the action bar says so. Retention and CloudKit duplicate maintenance now scan and delete in batches rather than fetching the whole history on the UI thread.
- **Search:** a disposable SQLite FTS5 trigram index stores literal-search text and ordering metadata. It builds small clips first and large clips later in resumable transactions. Queries of 3+ characters use FTS; 1–2 character queries scan normalized index text rather than faulting full SwiftData payloads. While backfill runs, queries can return an indexed subset and the UI warns that more matches may appear. If the index fails, a full-payload scan runs off the UI actor. Saves update changed IDs, and pin/label changes update only metadata without retokenizing large text; sync imports trigger a rebuild. A dirty marker and count check prompt rebuild after interrupted updates.

The disk-backed smoke fixture covers old pins, sparse labels, chronological paging without duplicates, full-content matches before and after indexing, Unicode folding, app filtering, large payload externalization and legacy migration, edit/delete updates, and reopening a completed index. It passed with 400, 10,000 and 50,000 ordinary clips. With 10,000 items, a full sparse-label fallback walk took 1.63 seconds off the UI actor and initial indexing took 3.80 seconds. With 50,000 items, an indexed sparse-label page loaded in 70 ms and initial indexing took 33.6 seconds after the small-clip batch-size increase (214 seconds before). That 50,000-item process peaked at 635 MB RSS, but includes construction and retention of all 50,000 SwiftData models by the synthetic test; it is not an app steady-state measurement or a claim that paging itself uses that memory. The App Store Debug and Sparkle Release schemes built successfully, with pre-existing warnings elsewhere in the project.

The final disk-backed smoke fixture passed with 400 and 10,000 ordinary clips, including short Unicode queries into externally stored large text. The standalone release-mode benchmark covered 1,000, 10,000, 50,000 and 100,000 ordinary clips, each with 64 KiB, 1 MiB, and 10 MiB clips; full methods and results are in [PERFORMANCE_ROLLOUT_RESULTS.md](PERFORMANCE_ROLLOUT_RESULTS.md). At 100,000 items, first-page p95 was 13 ms, sparse-label p95 52 ms, deep-search p95 1.3 ms, and two-character-search p95 457 ms. Repeated page sweeps showed no sustained RSS climb, but the 100,000-item process peaked at 588 MB during fixture creation/index construction. These are component timings, not UI frame timings, and the measurements will vary by machine and library.

Remaining rollout work is release-device UI profiling with Instruments, especially scrolling, repeated filter switches, live CloudKit imports, and app RSS after panel hide/reopen. The synthetic fixture cannot establish p95 frame times or verify CloudKit external-storage behavior on an account. Export of the *entire* library and certain user-requested bulk actions still materialize more data than the paged browser and can be optimized separately if profiling finds a spike. During initial backfill, indexed search can return incomplete results until the index finishes; that state is explicitly announced in the panel and History browser.
