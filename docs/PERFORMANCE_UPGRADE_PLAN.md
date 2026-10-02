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

- Add an explicit result service that returns pages of small Sendable summaries. Keep a bounded number of pages resident; release distant pages and work when the panel is hidden.
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

The first code slice now bounds plain and code card text to 4 KiB/10 lines, code classification and language-detection input to 8 KiB/160 lines, skips full-text color parsing for large clips, and limits highlighted preview and decoded-thumbnail cache costs. Full-size viewer images are no longer retained by the card cache. Both panel and History browser now resolve selected label metadata once per filter pass. Original clipboard text remains unchanged.

The app builds with the App Store scheme. Standalone smoke checks cover large and Unicode previews, plus positive/negative/stale label membership. On the same machine as the baseline, the bounded code heuristic processed a 12 MB synthetic input in a 2.8 ms median over five runs. This is a component measurement, not an end-to-end capture or UI result.

The next work item is result-service design and a representative UI/Instruments baseline. The current `@Query` still loads the full history; this first slice does not yet meet the flat-memory or fast-filter exit conditions. Image decode request coalescing and richer capture instrumentation also remain in stage 0.
