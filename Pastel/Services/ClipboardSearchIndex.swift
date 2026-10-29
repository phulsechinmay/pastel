import Foundation
import OSLog
import SQLite3
import SwiftData

/// A disposable, local read index. SwiftData remains the source of truth; the index
/// never syncs and can be rebuilt after an interrupted or incompatible migration.
@ModelActor
actor ClipboardSearchIndex {
    private var database: OpaquePointer?
    private var ready = false
    private var isRebuilding = false
    private var databaseURLOverride: URL?
    private let smallClipLimit = 64 * 1024
    private let logger = Logger(subsystem: "app.pastel.Pastel", category: "SearchIndex")

    private func open() throws {
        if database != nil { return }
        let url: URL
        if let databaseURLOverride {
            url = databaseURLOverride
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Pastel", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appendingPathComponent("clipboard-search.sqlite")
        }
        let path = url.path
        guard sqlite3_open(path, &database) == SQLITE_OK else { throw IndexError.database }
        try execute("PRAGMA journal_mode=WAL")
        // The index is disposable and checked against SwiftData on startup.
        // Avoid an fsync for each resumable backfill transaction.
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA busy_timeout=3000")
        if try schemaVersion() < 6 {
            try execute("DROP TABLE IF EXISTS clips")
            try execute("DROP TABLE IF EXISTS clip_keys")
            try execute("DROP TABLE IF EXISTS clip_labels")
            try execute("DROP TABLE IF EXISTS build_state")
            try execute("PRAGMA user_version=6")
        }
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS clips USING fts5(id UNINDEXED, body, title, app, timestamp UNINDEXED, pinRank UNINDEXED, tokenize='trigram')")
        try execute("CREATE TABLE IF NOT EXISTS clip_keys (id TEXT PRIMARY KEY, timestamp REAL NOT NULL, pinRank REAL NOT NULL, pinned INTEGER NOT NULL, contentType TEXT NOT NULL, sourceAppBundleID TEXT NOT NULL, originDeviceID TEXT NOT NULL, fingerprint TEXT NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS clip_keys_by_time ON clip_keys(timestamp DESC, id DESC)")
        try execute("CREATE INDEX IF NOT EXISTS clip_keys_by_pin ON clip_keys(pinned DESC, pinRank DESC, timestamp DESC, id DESC)")
        try execute("CREATE TABLE IF NOT EXISTS clip_labels (clipRowID INTEGER NOT NULL, labelStableID TEXT NOT NULL, PRIMARY KEY(clipRowID, labelStableID))")
        try execute("CREATE INDEX IF NOT EXISTS clip_labels_by_label ON clip_labels(labelStableID, clipRowID)")
        try execute("CREATE TABLE IF NOT EXISTS build_state (phase TEXT NOT NULL, next_offset INTEGER NOT NULL)")
        try execute("INSERT INTO build_state(phase, next_offset) SELECT 'small', 0 WHERE NOT EXISTS (SELECT 1 FROM build_state)")
        // v3 cursor state (perf-regression-fix). Additive tables only: they are
        // created with IF NOT EXISTS and user_version is NOT bumped through the
        // drop path above, so an existing complete index is not destroyed.
        // The old build_state offset format is not reused (see rebuild() seeding).
        try execute("CREATE TABLE IF NOT EXISTS rebuild_state (pass TEXT PRIMARY KEY, cursorTimestamp REAL, tieOffset INTEGER NOT NULL, completed INTEGER NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS externalize_state (id INTEGER PRIMARY KEY, cursorTimestamp REAL, tieOffset INTEGER NOT NULL, completed INTEGER NOT NULL)")
        try execute("INSERT INTO externalize_state(id, cursorTimestamp, tieOffset, completed) SELECT 1, NULL, 0, 0 WHERE NOT EXISTS (SELECT 1 FROM externalize_state)")
    }

    /// Allows the standalone synthetic fixture to keep its index in a temp folder.
    func useDatabase(at url: URL) {
        precondition(database == nil)
        databaseURLOverride = url
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw IndexError.database }
    }

    private func schemaVersion() throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw IndexError.database }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// Rebuild with keyset pagination (perf-regression-fix, v3).
    ///
    /// The old offset pagination re-scanned and re-sorted up to `fetchOffset`
    /// on every batch, with no index on timestamp, and forced every image
    /// through a 2-item batch. The new cursor is (cursorTimestamp, tieOffset)
    /// per pass: predicate `timestamp <= cursorTimestamp`, sorted timestamp
    /// DESC, with fetchOffset used ONLY to skip already-processed items
    /// inside one equal-timestamp group (bounded by that group's size, never
    /// by history size). After a batch, if its minimum timestamp is below
    /// the old cursor, the cursor moves to that minimum and tieOffset becomes
    /// the count at that minimum; if it equals the old cursor, tieOffset
    /// grows by the batch size, so an all-tie batch still advances.
    /// Items inserted with a newer timestamp during a pass, and items whose
    /// byteCount crosses passes on edit, are covered by the final ID
    /// reconciliation, not by the cursor.
    ///
    /// Passes: small (128/batch), large-text (16/batch — FTS tokenisation
    /// of large texts is the memory/CPU risk), large-metadata (128/batch —
    /// images/files/colours/URLs carry no large text to tokenise; their
    /// clips row is still inserted with title/app and empty body so
    /// title/app search does not regress).
    func rebuild() async throws {
        let started = ContinuousClock.now
        try open()
        // Seed the new cursor state from a legacy complete index, so the
        // first launch after this fix does NOT rebuild an index that was
        // already complete. Only a mid-rebuild legacy index pays a fresh
        // (now fast) rebuild, because its old offset format is not reused.
        if try rebuildStateIsEmpty() {
            let legacy = try buildState()
            if legacy.phase == "complete" && (try countsMatch()) {
                try markAllPassesComplete()
                ready = true
                UserDefaults.standard.set(0, forKey: Self.indexMismatchLaunchesKey)
                logger.info("Search index already complete; seeded new cursor state")
                return
            }
        }
        ready = false
        isRebuilding = true
        defer { isRebuilding = false }
        try await runRebuildPasses()
        if Task.isCancelled { return }
        // Delta reconciliation replaces the old exact-count reset gate.
        if try countsMatch() {
            UserDefaults.standard.set(0, forKey: Self.indexMismatchLaunchesKey)
        } else {
            let expected = try swiftDataItemCount()
            let indexed = try indexedItemCount()
            logger.info("Search index count mismatch: expected=\(expected, privacy: .public) indexed=\(indexed, privacy: .public)")
            let diffSize = try reconcileIndexCounts()
            logger.info("Search index reconciliation applied: diffSize=\(diffSize, privacy: .public)")
            if try countsMatch() {
                UserDefaults.standard.set(0, forKey: Self.indexMismatchLaunchesKey)
            } else {
                // Persistent mismatch: escalate to one fast full rebuild only
                // if this is the second consecutive mismatched launch AND
                // the diff is large. Small persistent diffs are logged and
                // retried next launch, never reset-looped.
                let previousMismatches = UserDefaults.standard.integer(forKey: Self.indexMismatchLaunchesKey)
                UserDefaults.standard.set(previousMismatches + 1, forKey: Self.indexMismatchLaunchesKey)
                if previousMismatches >= 1 && diffSize > 1000 {
                    logger.info("Search index mismatch persisted with large diff; running one fast full rebuild")
                    try resetTables()
                    UserDefaults.standard.set(0, forKey: Self.indexMismatchLaunchesKey)
                    try await runRebuildPasses()
                    if Task.isCancelled { return }
                    _ = try reconcileIndexCounts()
                }
            }
        }
        ready = true
        let elapsed = started.duration(to: .now)
        logger.info("Search index ready after \(String(describing: elapsed))")
    }

    private static let indexMismatchLaunchesKey = "pastelSearchIndexMismatchLaunches"

    private func runRebuildPasses() async throws {
        // Pass definitions, in order. Content-type raw values are the
        // ContentType case names (text, richText, code, url, image, file,
        // color). Large-text is tokenised; large-metadata is not.
        let passes: [(name: String, batchSize: Int, isLargeText: Bool, isLargeMetadata: Bool)] = [
            ("small", 128, false, false),
            ("largeText", 16, true, false),
            ("largeMetadata", 128, false, true),
        ]
        for pass in passes {
            if Task.isCancelled { return }
            try await runRebuildPass(name: pass.name, batchSize: pass.batchSize, isLargeText: pass.isLargeText, isLargeMetadata: pass.isLargeMetadata)
        }
    }

    private func runRebuildPass(name: String, batchSize: Int, isLargeText: Bool, isLargeMetadata: Bool) async throws {
        let limit = smallClipLimit
        var cursor = try rebuildCursor(pass: name)
        if cursor.completed { return }
        var indexedInPass = 0
        while !Task.isCancelled {
            let batchStarted = ContinuousClock.now
            let predicate: Predicate<ClipboardItem>
            if let cursorTimestamp = cursor.timestamp {
                let cursorDate = Date(timeIntervalSince1970: cursorTimestamp)
                if name == "small" {
                    predicate = #Predicate<ClipboardItem> { $0.byteCount <= limit && !$0.isConcealed && $0.timestamp <= cursorDate }
                } else if isLargeText {
                    predicate = #Predicate<ClipboardItem> { $0.byteCount > limit && !$0.isConcealed && ($0.contentType == "text" || $0.contentType == "richText" || $0.contentType == "code") && $0.timestamp <= cursorDate }
                } else {
                    predicate = #Predicate<ClipboardItem> { $0.byteCount > limit && !$0.isConcealed && $0.contentType != "text" && $0.contentType != "richText" && $0.contentType != "code" && $0.timestamp <= cursorDate }
                }
            } else {
                if name == "small" {
                    predicate = #Predicate<ClipboardItem> { $0.byteCount <= limit && !$0.isConcealed }
                } else if isLargeText {
                    predicate = #Predicate<ClipboardItem> { $0.byteCount > limit && !$0.isConcealed && ($0.contentType == "text" || $0.contentType == "richText" || $0.contentType == "code") }
                } else {
                    predicate = #Predicate<ClipboardItem> { $0.byteCount > limit && !$0.isConcealed && $0.contentType != "text" && $0.contentType != "richText" && $0.contentType != "code" }
                }
            }
            var descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = cursor.tieOffset
            let processed = try autoreleasepool { () throws -> (count: Int, minTimestamp: Double?) in
                let batchContext = ModelContext(modelContainer)
                let batch = try batchContext.fetch(descriptor)
                if batch.isEmpty { return (0, nil) }
                let minTimestamp = batch.map(\.timestamp.timeIntervalSince1970).min()
                let tieCount = minTimestamp.map { min in batch.filter { $0.timestamp.timeIntervalSince1970 == min }.count } ?? 0
                try execute("BEGIN IMMEDIATE")
                do {
                    for item in batch { try upsert(item) }
                    // Advance the cursor inside the same transaction as the
                    // upserts, so a kill mid-pass resumes exactly here.
                    if let minTimestamp {
                        if let oldTimestamp = cursor.timestamp, minTimestamp == oldTimestamp {
                            try execute("INSERT INTO rebuild_state(pass, cursorTimestamp, tieOffset, completed) VALUES ('\(name)', \(oldTimestamp), \(cursor.tieOffset + batch.count), 0) ON CONFLICT(pass) DO UPDATE SET cursorTimestamp=excluded.cursorTimestamp, tieOffset=excluded.tieOffset, completed=0")
                        } else {
                            try execute("INSERT INTO rebuild_state(pass, cursorTimestamp, tieOffset, completed) VALUES ('\(name)', \(minTimestamp), \(tieCount), 0) ON CONFLICT(pass) DO UPDATE SET cursorTimestamp=excluded.cursorTimestamp, tieOffset=excluded.tieOffset, completed=0")
                        }
                    }
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
                return (batch.count, minTimestamp)
            }
            if processed.count == 0 {
                try execute("INSERT INTO rebuild_state(pass, cursorTimestamp, tieOffset, completed) VALUES ('\(name)', NULL, 0, 1) ON CONFLICT(pass) DO UPDATE SET cursorTimestamp=NULL, tieOffset=0, completed=1")
                break
            }
            indexedInPass += processed.count
            // Update the in-memory cursor to match what was just committed.
            if let minTimestamp = processed.minTimestamp {
                if let oldTimestamp = cursor.timestamp, minTimestamp == oldTimestamp {
                    cursor = (timestamp: oldTimestamp, tieOffset: cursor.tieOffset + processed.count, completed: false)
                } else {
                    // Tie count for the new minimum must be recomputed from
                    // the committed state, not from the batch alone, if the
                    // batch straddled the minimum — re-reading is cheap and
                    // avoids an off-by-tie error.
                    cursor = try rebuildCursor(pass: name)
                }
            }
            logSlowBatchIfNeeded(pass: name, started: batchStarted, batchSize: processed.count)
            await Task.yield()
        }
        // Phase-completion aggregate only (no per-batch type/size breakdown).
        logger.info("Search index pass completed: pass=\(name, privacy: .public) indexedInPass=\(indexedInPass, privacy: .public)")
    }

    private var slowBatchLogCount = 0
    private func logSlowBatchIfNeeded(pass: String, started: ContinuousClock.Instant, batchSize: Int) {
        let elapsedMs = Int(started.duration(to: .now).components.seconds * 1000 + started.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
        // Slow batches log elapsed + batch size ONLY — never composition
        // (a 2/16-item composition would be effectively per-item data).
        // Rate-limited so a slow disk cannot flood the log.
        if elapsedMs > 50 && slowBatchLogCount < 20 {
            slowBatchLogCount += 1
            logger.info("Search index slow batch: pass=\(pass, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public) batchSize=\(batchSize, privacy: .public)")
        }
    }

    private func rebuildStateIsEmpty() throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM rebuild_state", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw IndexError.database }
        return sqlite3_column_int(statement, 0) == 0
    }

    private func markAllPassesComplete() throws {
        for name in ["small", "largeText", "largeMetadata"] {
            try execute("INSERT INTO rebuild_state(pass, cursorTimestamp, tieOffset, completed) VALUES ('\(name)', NULL, 0, 1) ON CONFLICT(pass) DO UPDATE SET cursorTimestamp=NULL, tieOffset=0, completed=1")
        }
    }

    private func rebuildCursor(pass: String) throws -> (timestamp: Double?, tieOffset: Int, completed: Bool) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT cursorTimestamp, tieOffset, completed FROM rebuild_state WHERE pass = ?", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        bind(pass, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return (nil, 0, false)
        }
        let timestamp: Double? = sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 0)
        return (timestamp, Int(sqlite3_column_int(statement, 1)), sqlite3_column_int(statement, 2) != 0)
    }

    private func swiftDataItemCount() throws -> Int {
        let context = ModelContext(modelContainer)
        return try context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { !$0.isConcealed }
        ))
    }

    private func indexedItemCount() throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM clip_keys", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw IndexError.database }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// Bounded ID-only reconciliation. Fetches SwiftData IDs in keyset
    /// batches (not full models for every row), compares to clip_keys IDs,
    /// upserts missing IDs and removes stale IDs. Returns the diff size.
    /// Full models are fetched only for IDs that actually differ.
    private func reconcileIndexCounts() throws -> Int {
        var indexedIDs = Set<String>()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT id FROM clip_keys", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 0) {
                indexedIDs.insert(String(cString: pointer))
            }
        }
        sqlite3_finalize(statement)
        // SwiftData IDs in timestamp-keyset batches. We fetch models here
        // only to obtain their transfer strings; the batch size keeps
        // memory bounded, and this path runs only on a count mismatch.
        var swiftDataIDs = Set<String>()
        var cursorTimestamp: Double? = nil
        var tieOffset = 0
        while true {
            var descriptor: FetchDescriptor<ClipboardItem>
            if let cursorTimestamp {
                let cursorDate = Date(timeIntervalSince1970: cursorTimestamp)
                descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate<ClipboardItem> { !$0.isConcealed && $0.timestamp <= cursorDate })
            } else {
                descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate<ClipboardItem> { !$0.isConcealed })
            }
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchLimit = 500
            descriptor.fetchOffset = tieOffset
            let context = ModelContext(modelContainer)
            let batch = try context.fetch(descriptor)
            if batch.isEmpty { break }
            for item in batch {
                if let id = item.persistentModelID.asTransferString {
                    swiftDataIDs.insert(id)
                }
            }
            guard let minTimestamp = batch.map(\.timestamp.timeIntervalSince1970).min() else { break }
            if let old = cursorTimestamp, minTimestamp == old {
                tieOffset += batch.count
            } else {
                cursorTimestamp = minTimestamp
                tieOffset = batch.filter { $0.timestamp.timeIntervalSince1970 == minTimestamp }.count
            }
            if batch.count < 500 { break }
        }
        let missing = swiftDataIDs.subtracting(indexedIDs)
        let stale = indexedIDs.subtracting(swiftDataIDs)
        let diffSize = missing.count + stale.count
        if diffSize == 0 { return 0 }
        let changeContext = ModelContext(modelContainer)
        try execute("BEGIN IMMEDIATE")
        do {
            for idString in stale {
                if let id = PersistentIdentifier.fromTransferString(idString) {
                    try remove(id)
                }
            }
            for idString in missing {
                // Resolve by transfer string via a fresh context fetch is
                // not directly possible; missing IDs are upserted through
                // applyChanges-style resolution below in a second pass.
                _ = idString
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        // Second pass for missing IDs: fetch them by scanning in keyset
        // batches again and upserting only the missing ones. This avoids
        // holding all models in memory at once.
        if !missing.isEmpty {
            var remaining = missing
            var cursor2: Double? = nil
            var tie2 = 0
            while !remaining.isEmpty {
                var descriptor: FetchDescriptor<ClipboardItem>
                if let cursor2 {
                    let cursorDate = Date(timeIntervalSince1970: cursor2)
                    descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate<ClipboardItem> { !$0.isConcealed && $0.timestamp <= cursorDate })
                } else {
                    descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate<ClipboardItem> { !$0.isConcealed })
                }
                descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
                descriptor.fetchLimit = 500
                descriptor.fetchOffset = tie2
                let context = ModelContext(modelContainer)
                let batch = try context.fetch(descriptor)
                if batch.isEmpty { break }
                try execute("BEGIN IMMEDIATE")
                do {
                    for item in batch {
                        if let idString = item.persistentModelID.asTransferString, remaining.contains(idString) {
                            try upsert(item)
                            remaining.remove(idString)
                        }
                    }
                    try execute("COMMIT")
                } catch {
                    try? execute("ROLLBACK")
                    throw error
                }
                guard let minTimestamp = batch.map(\.timestamp.timeIntervalSince1970).min() else { break }
                if let old = cursor2, minTimestamp == old {
                    tie2 += batch.count
                } else {
                    cursor2 = minTimestamp
                    tie2 = batch.filter { $0.timestamp.timeIntervalSince1970 == minTimestamp }.count
                }
                if batch.count < 500 { break }
            }
        }
        return diffSize
    }

    func resetAndRebuild() async throws {
        try open()
        ready = false
        try resetTables()
        try await rebuild()
    }

    private func resetTables() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM clips")
            try execute("DELETE FROM clip_keys")
            try execute("DELETE FROM clip_labels")
            try execute("DELETE FROM rebuild_state")
            try execute("UPDATE build_state SET phase='small', next_offset=0")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func countsMatch() throws -> Bool {
        let context = ModelContext(modelContainer)
        let expected = try context.fetchCount(FetchDescriptor<ClipboardItem>(
            predicate: #Predicate<ClipboardItem> { !$0.isConcealed }
        ))
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM clip_keys", -1, &statement, nil) == SQLITE_OK else {
            throw IndexError.database
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw IndexError.database }
        return expected == Int(sqlite3_column_int64(statement, 0))
    }

    /// One-time, checkpointed migration of older inline text (v3).
    ///
    /// Previously this walked ALL byteCount/characterCount > 64 KiB rows
    /// in 2-item offset batches on EVERY launch, with no checkpoint and
    /// no completion flag — images were re-walked forever to do nothing,
    /// because byteCount is never cleared when text is externalised.
    /// Now: keyset cursor (timestamp, tieOffset) persisted in
    /// externalize_state after each batch, batch size 32 (image/file
    /// models fault cheaply — only their payload fields are checked),
    /// and a completed flag. Once a full walk finishes, later launches
    /// skip it entirely. Candidates are defined by PAYLOAD, not type:
    /// (externalisable type AND text > limit) OR html > limit OR rtf >
    /// limit, regardless of type, so imported image/file items carrying
    /// large HTML/RTF are not dropped.
    func externalizeLegacyLargeClips() async throws {
        try open()
        // Check completion flag.
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT cursorTimestamp, tieOffset, completed FROM externalize_state WHERE id = 1", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        var cursorTimestamp: Double? = nil
        var tieOffset = 0
        var completed = false
        if sqlite3_step(statement) == SQLITE_ROW {
            cursorTimestamp = sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 0)
            tieOffset = Int(sqlite3_column_int(statement, 1))
            completed = sqlite3_column_int(statement, 2) != 0
        }
        sqlite3_finalize(statement)
        if completed {
            logger.info("Legacy large-clip externalisation already complete; skipping")
            return
        }
        logger.info("Legacy large-clip externalisation starting")
        let limit = ClipboardItem.inlineTextLimit
        var walked = 0
        var changedTotal = 0
        let started = ContinuousClock.now
        while !Task.isCancelled {
            let batchStarted = ContinuousClock.now
            let predicate: Predicate<ClipboardItem>
            if let cursorTimestamp {
                let cursorDate = Date(timeIntervalSince1970: cursorTimestamp)
                predicate = #Predicate<ClipboardItem> { ($0.byteCount > limit || $0.characterCount > limit) && $0.timestamp <= cursorDate }
            } else {
                predicate = #Predicate<ClipboardItem> { $0.byteCount > limit || $0.characterCount > limit }
            }
            var descriptor = FetchDescriptor<ClipboardItem>(predicate: predicate)
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchLimit = 32
            descriptor.fetchOffset = tieOffset
            let batchContext = ModelContext(modelContainer)
            let batch = try batchContext.fetch(descriptor)
            if batch.isEmpty {
                try execute("UPDATE externalize_state SET cursorTimestamp=NULL, tieOffset=0, completed=1 WHERE id = 1")
                break
            }
            var changed = false
            for item in batch {
                if item.largeTextData == nil, let text = item.textContent,
                   [.text, .richText, .code].contains(item.type),
                   text.utf8.count > limit {
                    item.setStoredText(text)
                    changed = true
                }
                if let html = item.htmlContent, html.utf8.count > limit {
                    item.setStoredHTML(html)
                    changed = true
                }
                if let rtf = item.rtfData, rtf.count > limit {
                    item.setStoredRTF(rtf)
                    changed = true
                }
            }
            if changed {
                try batchContext.save()
                changedTotal += batch.count
            }
            walked += batch.count
            // Advance the keyset cursor and persist it, even when nothing
            // changed, so a kill resumes here instead of restarting.
            guard let minTimestamp = batch.map(\.timestamp.timeIntervalSince1970).min() else { break }
            if let old = cursorTimestamp, minTimestamp == old {
                tieOffset += batch.count
            } else {
                cursorTimestamp = minTimestamp
                tieOffset = batch.filter { $0.timestamp.timeIntervalSince1970 == minTimestamp }.count
            }
            if let cursorTimestamp {
                try execute("UPDATE externalize_state SET cursorTimestamp=\(cursorTimestamp), tieOffset=\(tieOffset), completed=0 WHERE id = 1")
            }
            logSlowBatchIfNeeded(pass: "externalize", started: batchStarted, batchSize: batch.count)
            await Task.yield()
        }
        let elapsedMs = Int(started.duration(to: .now).components.seconds * 1000 + started.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
        logger.info("Legacy large-clip externalisation finished: walked=\(walked, privacy: .public) changedBatches=\(changedTotal, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)")
    }

    private func buildState() throws -> (phase: String, offset: Int) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT phase, next_offset FROM build_state LIMIT 1", -1,
                                 &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let phase = sqlite3_column_text(statement, 0) else { throw IndexError.database }
        return (String(cString: phase), Int(sqlite3_column_int(statement, 1)))
    }

    /// Apply local SwiftData saves without another whole-history pass.
    /// Per-ID errors are isolated (v3): one bad ID no longer flips
    /// `ready = false` for the whole index. Only a database-level failure
    /// (begin/commit) throws. Failure count is logged, never IDs.
    func applyChanges(upserted: [PersistentIdentifier], deleted: [PersistentIdentifier]) throws {
        try open()
        var failedCount = 0
        try execute("BEGIN IMMEDIATE")
        do {
            let changeContext = ModelContext(modelContainer)
            for id in deleted {
                do { try remove(id) } catch { failedCount += 1 }
            }
            for id in upserted {
                do {
                    guard let item = changeContext.model(for: id) as? ClipboardItem else { continue }
                    if item.isConcealed { try remove(id) } else { try upsert(item) }
                } catch { failedCount += 1 }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        if failedCount > 0 {
            logger.info("Search index applyChanges completed with failures: failedCount=\(failedCount, privacy: .public) upsertedCount=\(upserted.count, privacy: .public) deletedCount=\(deleted.count, privacy: .public)")
        }
    }

    func matchingIDs(_ search: String, offset: Int, limit: Int, pinsFirst: Bool) throws -> [PersistentIdentifier]? {
        let normalized = Self.normalize(search)
        // During backfill, return the indexed subset immediately. The UI marks
        // results as incomplete and refreshes when the rebuild finishes. A short
        // query on a completed index scans SQLite text rather than faulting every
        // SwiftData model and large external payload into the worker context.
        guard ready || isRebuilding, !normalized.isEmpty else { return nil }
        try open()
        // The short-query scan can visit many rows. Allow a superseded search
        // task to stop it instead of holding the index actor for the full scan.
        sqlite3_progress_handler(database, 2_000, { _ in
            Task<Never, Never>.isCancelled ? 1 : 0
        }, nil)
        defer { sqlite3_progress_handler(database, 0, nil, nil) }
        var statement: OpaquePointer?
        let order = pinsFirst
            ? "clip_keys.pinned DESC, clip_keys.pinRank DESC, clip_keys.timestamp DESC, clip_keys.id DESC"
            : "clip_keys.timestamp DESC, clip_keys.id DESC"
        let isShortQuery = normalized.unicodeScalars.count < 3
        let matchCondition = isShortQuery
            ? "(instr(clips.body, ?) > 0 OR instr(clips.title, ?) > 0 OR instr(clips.app, ?) > 0)"
            : "clips MATCH ?"
        // A single character is usually common: stop after its first ordered
        // page. A two-character query is often sparse, so scan the FTS content
        // sequentially instead of doing a random row lookup for every clip.
        let source = normalized.unicodeScalars.count == 1
            ? "clip_keys INDEXED BY \(pinsFirst ? "clip_keys_by_pin" : "clip_keys_by_time") CROSS JOIN clips ON clips.rowid = clip_keys.rowid"
            : "clips JOIN clip_keys ON clips.rowid = clip_keys.rowid"
        let sql = "SELECT clip_keys.id FROM \(source) WHERE \(matchCondition) ORDER BY \(order) LIMIT ? OFFSET ?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        if isShortQuery {
            for position in 1...3 { bind(normalized, at: Int32(position), in: statement) }
        } else {
            let phrase = "\"" + normalized.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            bind(phrase, at: 1, in: statement)
        }
        let limitPosition: Int32 = isShortQuery ? 4 : 2
        sqlite3_bind_int(statement, limitPosition, Int32(limit))
        sqlite3_bind_int(statement, limitPosition + 1, Int32(offset))
        var ids: [PersistentIdentifier] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 0),
               let id = PersistentIdentifier.fromTransferString(String(cString: pointer)) {
                ids.append(id)
            }
            step = sqlite3_step(statement)
        }
        if step == SQLITE_INTERRUPT { throw CancellationError() }
        guard step == SQLITE_DONE else { throw IndexError.database }
        return ids
    }

    /// Metadata-only browse path. Labels use a dedicated membership table, so
    /// switching a chip never scans or faults every ClipboardItem model.
    func browsingIDs(
        offset: Int, limit: Int, pinsFirst: Bool,
        selectedLabelStableIDs: [String]?, filters: SearchFilters,
        localDeviceID: String
    ) throws -> [PersistentIdentifier]? {
        // Partial browsing while rebuilding (v3): search already served a
        // partial index; browsing must too, or the default panel falls
        // back to a full SwiftData scan for the whole rebuild. Callers
        // must show an incomplete marker while isRebuilding (see panel
        // and History browser), and must invalidate cursors on the ready
        // transition (see HistoryPageWorker / reload gating).
        guard ready || isRebuilding else { return nil }
        try open()
        sqlite3_progress_handler(database, 2_000, { _ in
            Task<Never, Never>.isCancelled ? 1 : 0
        }, nil)
        defer { sqlite3_progress_handler(database, 0, nil, nil) }
        var clauses = [
            "(originDeviceID = ? OR originDeviceID = '' OR contentType NOT IN ('image','file'))"
        ]
        var arguments = [localDeviceID]
        if let selectedLabelStableIDs {
            guard !selectedLabelStableIDs.isEmpty else { return nil }
            clauses.append("EXISTS (SELECT 1 FROM clip_labels WHERE clipRowID = clip_keys.rowid AND labelStableID IN (\(placeholders(selectedLabelStableIDs.count))))")
            arguments += selectedLabelStableIDs
        }
        if !filters.types.isEmpty {
            let types = filters.types.map(\.rawValue).sorted()
            clauses.append("contentType IN (\(placeholders(types.count)))")
            arguments += types
        }
        if !filters.appBundleIDs.isEmpty {
            let apps = filters.appBundleIDs.sorted()
            clauses.append("sourceAppBundleID IN (\(placeholders(apps.count)))")
            arguments += apps
        }
        if let cutoff = filters.dateRange?.cutoff() {
            clauses.append("timestamp >= ?")
            arguments.append(String(cutoff.timeIntervalSince1970))
        }
        let order = pinsFirst
            ? "pinned DESC, pinRank DESC, timestamp DESC, id DESC"
            : "timestamp DESC, id DESC"
        let sql = "SELECT id FROM clip_keys WHERE \(clauses.joined(separator: " AND ")) ORDER BY \(order) LIMIT ? OFFSET ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        for (index, argument) in arguments.enumerated() { bind(argument, at: Int32(index + 1), in: statement) }
        sqlite3_bind_int(statement, Int32(arguments.count + 1), Int32(limit))
        sqlite3_bind_int(statement, Int32(arguments.count + 2), Int32(offset))
        var ids: [PersistentIdentifier] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 0),
               let id = PersistentIdentifier.fromTransferString(String(cString: pointer)) {
                ids.append(id)
            }
            step = sqlite3_step(statement)
        }
        if step == SQLITE_INTERRUPT { throw CancellationError() }
        guard step == SQLITE_DONE else { throw IndexError.database }
        return ids
    }

    private func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    private func upsert(_ item: ClipboardItem) throws {
        guard let id = item.persistentModelID.asTransferString else { return }
        let labelIDs = Set(item.safeLabels.map(\.stableID)).filter { !$0.isEmpty }.sorted()
        let fingerprint = try indexFingerprint(item, labelIDs: labelIDs)
        let previousFingerprint = try existingFingerprint(for: id)
        if previousFingerprint == fingerprint { return }
        if let previousFingerprint,
           let previous = try? JSONDecoder().decode(IndexFingerprint.self, from: Data(previousFingerprint.utf8)),
           previous.contentHash == item.contentHash,
           previous.title == item.title,
           previous.app == item.sourceAppName {
            // Pin, label, time and source metadata do not change FTS tokens.
            // Avoid reading/re-tokenizing a large full-text payload for them.
            try updateMetadata(item, id: id, fingerprint: fingerprint, labelIDs: labelIDs)
            return
        }
        try remove(item.persistentModelID)
        var keyStatement: OpaquePointer?
        let keySQL = "INSERT INTO clip_keys(id, timestamp, pinRank, pinned, contentType, sourceAppBundleID, originDeviceID, fingerprint) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(database, keySQL, -1,
                                 &keyStatement, nil) == SQLITE_OK else { throw IndexError.database }
        bind(id, at: 1, in: keyStatement)
        sqlite3_bind_double(keyStatement, 2, item.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(keyStatement, 3, item.isPinned ? (item.pinnedAt ?? item.timestamp).timeIntervalSince1970 : 0)
        sqlite3_bind_int(keyStatement, 4, item.isPinned ? 1 : 0)
        bind(item.contentType, at: 5, in: keyStatement)
        bind(item.sourceAppBundleID ?? "", at: 6, in: keyStatement)
        bind(item.originDeviceID, at: 7, in: keyStatement)
        bind(fingerprint, at: 8, in: keyStatement)
        let keyResult = sqlite3_step(keyStatement)
        sqlite3_finalize(keyStatement)
        guard keyResult == SQLITE_DONE else { throw IndexError.database }
        let rowID = sqlite3_last_insert_rowid(database)
        try insertLabels(labelIDs, rowID: rowID)
        var statement: OpaquePointer?
        let sql = "INSERT INTO clips(rowid, id, body, title, app, timestamp, pinRank) VALUES (?, ?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, rowID)
        bind(id, at: 2, in: statement)
        bind(Self.normalize(item.fullTextContent ?? ""), at: 3, in: statement)
        bind(Self.normalize(item.title ?? ""), at: 4, in: statement)
        bind(Self.normalize(item.sourceAppName ?? ""), at: 5, in: statement)
        bind(String(item.timestamp.timeIntervalSince1970), at: 6, in: statement)
        bind(String(item.isPinned ? (item.pinnedAt ?? item.timestamp).timeIntervalSince1970 : 0), at: 7, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw IndexError.database }
    }

    private func updateMetadata(_ item: ClipboardItem, id: String, fingerprint: String,
                                labelIDs: [String]) throws {
        var statement: OpaquePointer?
        let sql = "UPDATE clip_keys SET timestamp=?, pinRank=?, pinned=?, contentType=?, sourceAppBundleID=?, originDeviceID=?, fingerprint=? WHERE id=?"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        sqlite3_bind_double(statement, 1, item.timestamp.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, item.isPinned ? (item.pinnedAt ?? item.timestamp).timeIntervalSince1970 : 0)
        sqlite3_bind_int(statement, 3, item.isPinned ? 1 : 0)
        bind(item.contentType, at: 4, in: statement)
        bind(item.sourceAppBundleID ?? "", at: 5, in: statement)
        bind(item.originDeviceID, at: 6, in: statement)
        bind(fingerprint, at: 7, in: statement)
        bind(id, at: 8, in: statement)
        let result = sqlite3_step(statement)
        sqlite3_finalize(statement)
        guard result == SQLITE_DONE else { throw IndexError.database }
        var rowStatement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT rowid FROM clip_keys WHERE id=?", -1, &rowStatement, nil) == SQLITE_OK else { throw IndexError.database }
        bind(id, at: 1, in: rowStatement)
        let rowResult = sqlite3_step(rowStatement)
        let rowID = sqlite3_column_int64(rowStatement, 0)
        sqlite3_finalize(rowStatement)
        guard rowResult == SQLITE_ROW else { throw IndexError.database }
        try execute("DELETE FROM clip_labels WHERE clipRowID=\(rowID)")
        try insertLabels(labelIDs, rowID: rowID)
    }

    private func insertLabels(_ labelIDs: [String], rowID: Int64) throws {
        for stableID in labelIDs {
            var labelStatement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "INSERT INTO clip_labels(clipRowID, labelStableID) VALUES (?, ?)", -1,
                                     &labelStatement, nil) == SQLITE_OK else { throw IndexError.database }
            sqlite3_bind_int64(labelStatement, 1, rowID)
            bind(stableID, at: 2, in: labelStatement)
            let labelResult = sqlite3_step(labelStatement)
            sqlite3_finalize(labelStatement)
            guard labelResult == SQLITE_DONE else { throw IndexError.database }
        }
    }

    private struct IndexFingerprint: Codable {
        let contentHash: String
        let title: String?
        let app: String?
        let timestamp: Double
        let pinRank: Double
        let pinned: Bool
        let contentType: String
        let bundleID: String?
        let originDeviceID: String
        let labelIDs: [String]
    }

    private func indexFingerprint(_ item: ClipboardItem, labelIDs: [String]) throws -> String {
        let value = IndexFingerprint(
            contentHash: item.contentHash, title: item.title, app: item.sourceAppName,
            timestamp: item.timestamp.timeIntervalSince1970,
            pinRank: item.isPinned ? (item.pinnedAt ?? item.timestamp).timeIntervalSince1970 : 0,
            pinned: item.isPinned, contentType: item.contentType,
            bundleID: item.sourceAppBundleID, originDeviceID: item.originDeviceID,
            labelIDs: labelIDs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(data: try encoder.encode(value), encoding: .utf8) ?? ""
    }

    private func existingFingerprint(for id: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT fingerprint FROM clip_keys WHERE id = ?", -1,
                                 &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let pointer = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: pointer)
    }

    private func remove(_ id: PersistentIdentifier) throws {
        guard let key = id.asTransferString else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT rowid FROM clip_keys WHERE id = ?", -1, &statement, nil) == SQLITE_OK else { throw IndexError.database }
        defer { sqlite3_finalize(statement) }
        bind(key, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return }
        let rowID = sqlite3_column_int64(statement, 0)
        try execute("DELETE FROM clips WHERE rowid = \(rowID)")
        try execute("DELETE FROM clip_labels WHERE clipRowID = \(rowID)")
        try execute("DELETE FROM clip_keys WHERE rowid = \(rowID)")
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer?) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private enum IndexError: Error { case database, outOfSync }
}
