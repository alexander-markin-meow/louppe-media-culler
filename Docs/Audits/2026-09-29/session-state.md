# Louppe audit: session state, scanning, persistence, selection, and review utilities

Date: 2026-09-29. Canonical repository: `/Users/alexander_markin/Documents/code/louppe/app`. Audit of the current working tree, including its uncommitted review-preference, folder-hierarchy, connected-drive, quality-warning and window changes. No canonical source files changed; no commits, pushes, media mutations or Trash tests performed by this agent.

Read app and shared AGENTS.md, DEVELOPMENT_DETAILS.md ownership/persistence/session-state contracts, and PERFORMANCE.md main-actor, filtering, grouped-review, selection, and persistence requirements. Root agent owns the full tests/build/launch results; those results are deliberately not claimed here.

## Confirmed findings

### S1 — [P1] Pair-member Clean Up includes files outside the confirmed selection/filter scope

**Location:** `Sources/Louppe/SessionStore.swift:3067–3073` (`pairComponentCleanUpTargets`), mirrored in menu enablement at `3108–3113`. Confirmation promise: `Sources/Louppe/Views/SessionView.swift:220–223`.

**Trigger:** In the default Separate RAW/JPEG mode, open an unambiguous `SHOT.NEF` + `SHOT.JPG` pair. Hide JPEG using the file-type filter, leave Clean Up scope as Filtered, and choose Move Paired JPEGs to Trash. The same problem occurs with Selected scope when only the RAW is selected. The reverse happens when Paired RAWs is requested from a visible/selected JPEG.

**Cause:** Pair eligibility tests whether *either* member's displayed index occurs in `cleanUpCandidates`. It then constructs the worker snapshot for the chosen member even when that target member's index is hidden/unselected. The comment immediately above says scope membership follows the member being removed, and the confirmation explicitly says only paired JPEG/RAW files shown by the current filter or in the current selection are included.

**Consequence:** Confirming Trash can remove a different, hidden/unselected original from the folder. Trash is undoable, but the target set violates the advertised and chosen scope. A JPEG can contain independent edits or metadata, so companion status does not make crossing the scope harmless.

**Production-code reproduction, without moving media:** `StateAuditRepro.swift` constructs a Separate-mode store, uses the ordinary derived-index boundary, excludes JPEG, then asks `cleanUpCounts(for: .pairedJPEGs)`; it also repeats with RAW as the effective Selected scope. Output:

```text
HIDDEN PAIR CLEANUP: mode=separate, visible=[0], excluded=JPEG, pairedJPEGTargets=1
UNSELECTED PAIR CLEANUP: effectiveSelection=[0], current=SHOT.NEF, pairedJPEGTargets=1
```

Both should be zero. The count and execution paths share `pairComponentCleanUpTargets`, so the wrong count is the exact wrong immutable worker target set, not a display-only discrepancy.

**Minimal fix:** Resolve `itemIndexByFileID[target.id]` first, and require that specific target index to belong to `candidateIndices`. Apply the same rule in `hasCleanUpTargets`. Together mode naturally continues to include both physical members when its one displayed pair index is in scope. Add cases for both target directions × both Separate/Together modes × Filtered/Selected scopes; protect independently rated members.

### S2 — [P1] A post-rename sync failure becomes a discard-safe save even when no fallback was secured

**Location:** `Sources/Louppe/SessionPersistence.swift:783–803`, and analogous backup adoption at `1511–1537`. Relevant I/O ordering: `Sources/Louppe/DurableFileIO.swift:342–373`. Store accepts the result as durable at `SessionStore.swift:5029–5034` / `5139–5145`; Close/Quit follows `SaveResult.canDiscardInMemoryState`.

**Trigger:** Sidecar bytes have been renamed successfully, but the required following directory sync fails with EIO. The backup location is also unavailable/unwritable. A parallel case occurs during a backup-only save after a source-volume disconnect: the backup rename lands, then its required directory sync fails.

**Cause:** The catch path hashes the currently visible destination bytes. If they equal the intended bytes, it updates CAS/generation lineage and returns `.savedToSidecar`; the fallback is only best-effort, and its failure cannot affect this result. `recordCommittedBackupIfObserved` likewise returns success from byte equality alone. There is no retry of the failed directory sync and no distinction between an observed rename and a completed durability barrier.

**What is and is not wrong:** Adopting exactly those observed bytes into CAS lineage is correct and necessary so Retry does not conflict with Louppe's own committed rename. The defect is *also declaring the generation durable/discard-safe*. Readability from the current kernel state does not complete the post-rename flush contract.

**Deterministic production-code reproduction:** The harness uses `SessionPersistence(afterSidecarReplaceForTesting:)` to throw `DurableFileIO.IOError.system(operation: "fsync", code: EIO)` at the existing fault-injection boundary. `DurableFileIO.atomicWrite` invokes that boundary **before** calling `syncDirectory`; thus this reproduction definitely has no completed post-rename directory flush. It supplies a backup directory path occupied by a regular file, so no backup can be written. Output:

```text
POST-RENAME SYNC FAILURE + BLOCKED BACKUP: result=savedToSidecar, canDiscard=true
BACKUP IS REGULAR FILE: true
```

**Consequence:** The UI can authorize Close/Quit and forget the only in-memory ratings after neither location completed its required durable publication. Loss after a subsequent power interruption is an inference from the missing flush, not a power-loss event reproduced here. It is a concrete error-handling contradiction with the repository's durable-write guarantee.

**Existing tests:** `testOfflineBackupAdoptsACommittedRenameAfterTrailingError` explicitly expects success after the backup test hook throws. That test proves CAS continuity, not durability. `testReconnectedSidecarAdoptsTheExactBackupOwnedCommit` correctly covers reconnect lineage when a fallback can succeed. Preserve that behavior while adding a case where post-rename flush and fallback both fail.

**Minimal fix:** Adopt the exact observed revision for future CAS, then reattempt the matching parent-directory sync or secure a successfully synced backup before marking the live generation durable. If both fail, retain a retryable failure and in-memory state. Avoid falsely returning `.sidecarChanged` on retry against those same Louppe-owned bytes. Explicitly model observed publication separately from completed durability if needed.

**External reference:** Apple's [fsync manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html) documents sync as the transition from in-core state to storage, describes buffered-write ordering/power-loss risks, and identifies EIO as an I/O failure. The source's own explicit write → file sync → rename → directory sync sequence establishes which boundary is missing here.

### S3 — [P2] Filtering a disjoint selection leaves Gallery current outside the surviving selection

**Location:** `Sources/Louppe/SessionStore.swift:1136–1149` (`applyFilter`), with selection authority in `SelectionState.retainVisible`.

**Trigger:** Items A, B, C are visible in order. Current is A; Command-select C, creating selection A+C. Apply a camera/type/search/other filter that removes A while B+C remain visible.

**Cause:** `retainVisible` correctly removes A from explicit selection, leaving C. The separate current-item fallback then picks the first visible absolute index >= old current, which is B. It does not choose from the surviving explicit selection. Rescan's `restoreSelection` does enforce current membership; this filtering path does not.

**Consequence:** Gallery displays B while F/D, stars, colors, Selected-scope operations and selection aggregate controls address C. With advancement disabled, F leaves B on screen while marking C Yes. This is a persistent misleading state, not just a transient publication.

**Production-code reproduction:** The harness uses the ordinary state APIs and a non-search filter assignment, so no debounce timing is involved:

```text
FILTER SELECTION: visible=[1, 2], selected=[2], current=1, displayed=B.jpg
RATE AFTER FILTER: displayed=B.jpg, ratings=["undecided", "undecided", "yes"]
```

**Minimal fix:** After intersecting explicit selection with visibility, if the surviving selection is nonempty and does not contain current, move current to an appropriate surviving selected index in displayed order. Otherwise retain the normal visible fallback. Do this before prefetch/publication-dependent actions. Add a disjoint selection regression; the existing `testRangeSelectionDropsMembersHiddenByFilter` happens to leave the nearest visible item inside its contiguous range and misses the problem.

### S4 — [P3] Typed POSIX persistence failures lose their reason at the UI boundary

**Location:** `Sources/Louppe/SessionPersistence.swift:1732–1765` (`failureReason(for:)`).

**Trigger:** The source folder is readable but not writable, or `DurableFileIO` returns ENOSPC/EROFS/EACCES/ENODEV from its descriptor-level routines.

**Cause:** `DurableFileIO.IOError.system` is handled only for the special lock timeout. Other instances are bridged to NSError, but the Swift error type's domain is `Louppe.DurableFileIO.IOError`, not `NSPOSIXErrorDomain`, and its NSError code is the enum case number rather than the stored errno. The existing POSIX switch is therefore bypassed.

**Production-code reproduction:** The harness makes a disposable photo directory mode 0500 after capturing access, leaves backup writable, and saves through the real descriptor-level writer. It restores permissions afterward. Output:

```text
READ-ONLY SIDECAR ERROR CLASSIFICATION: savedToBackup(sidecarFailure: ...FailureReason.other)
DURABLE ERROR NSError DOMAIN: ...DurableFileIO.IOError, code=0, expected POSIX domain=NSPOSIXErrorDomain
```

**Consequence:** Read-only/card-full/unavailable failures produce generic Retry warnings instead of the existing actionable permission/space/reconnect messages. Ratings may still be safe in the backup, but users lack the actual remedy. ENOSPC and ENODEV branches share the same provable type-mapping defect; only EACCES was triggered with real I/O here.

**Minimal fix:** Extract the stored errno from every `DurableFileIO.IOError.system` first and map it through the same reason function used for NSPOSIXErrorDomain; preserve the special busy operation classification. Cover real read-only I/O plus injected ENOSPC/ENODEV.

## Optimization opportunities

1. **Do not make Capture Bursts wait for file hashing and image decoding.** `enterGroupedReview(.captureBursts)` invokes the same complete analysis as exact/similar review. `DuplicateBurstAnalysis.analyze` hashes every repeated-size file candidate before gathering already-cached dates, then generates visual fingerprints for all supported photo inputs. A metadata-only burst request therefore reads full files and decodes previews before presenting information already in memory. Split evidence passes or immediately publish date-based groups while the explicitly requested remaining analyses run. No benchmark here; the unnecessary dependency is direct source evidence.

2. **Move initial/sensitivity group membership construction off the main actor for very large sessions.** `SessionStore.swift:1202` calls `result.groups` synchronously. Likely-similar grouping sorts hashes, builds bucket maps, checks up to 50,000 pairs and performs union-find; bursts sort all dates each interval change. PERFORMANCE.md already acknowledges this improvement. Retain the existing generation/sensitivity cache and cancellation model; measure main-actor intervals before implementation.

3. **Reduce repeated structural work when changing only sort.** `rebuildSortedIndices` reconstructs the physical-file index and item-ID map despite items being unchanged, then sorts. These maps can remain structural-only caches. Default scan order reuse and snapshotting metadata before metadata sort are already good optimizations and should remain.

4. **Reduce snapshot byte volume after correctness fixes.** JSON pretty-printing increases every sidecar+backup write and every CAS reread. The generated one-entry **on-disk sidecar** was 917 bytes; compact JSON with identical parsed values was 631 bytes (31.2% lower; Python compact serializer used for this illustrative comparison). These sizes are recorded in `state-json-size-measurement.json`. The harness log's 889-byte figure separately measures its **in-memory SessionFile before SessionPersistence adds `snapshotGeneration`**; the actor-added field accounts for the 28-byte difference. Assess exact Foundation encoder byte counts on 1k/10k/100k fixtures; remove `.prettyPrinted` only if human-editability is not a requirement. Sorted keys can remain for reproducibility. Prefer this simple measured reduction before a new WAL/persistence architecture.

5. **Pass cancellation into the second final identity-validation loop.** `SessionStore.swift:1999` invokes `validateScannedIdentities(scanned)` with its default always-false cancellation closure after awaiting persistence read. Cancellation is checked only after the complete second O(N) stat pass. An already-canceled scan can therefore continue removable-volume I/O even though generation guards prevent its result from becoming visible. Pass the existing bridged flag and check task cancellation before beginning this pass. Source-confirmed inefficiency; no timing reproduction performed.

6. **Consider byte-based undo budgeting for repeated bulk changes.** The cap is 500 steps, while each bulk step can retain one full metadata snapshot per physical file. For very large sessions, repeated Select All decisions/undoable Clear All can retain substantially more memory than normal per-photo culling. This is an unmeasured scaling opportunity, not an observed leak.

## Additional concerns / verification gaps, not promoted to confirmed findings

- **Writer/read maximum disagreement:** Reads are bounded to 512 MiB (`SessionPersistence.swift:30`), but encoded writes at `573–581` do not check that cap. A sufficiently large valid snapshot can be written successfully and become unreadable to the same reader. Representative encoded per-file overhead suggests the threshold is on the order of hundreds of thousands of physical files, depending on paths/origin metadata. No 512 MiB allocation/large disk test performed; add an encoded-size guard or a lower-limit injected contract test. Do not treat it as a demonstrated normal-folder failure.
- **Security-scoped recents:** `SecurityScopedFolderBookmarks.load` calls `fileExists` on a resolved security-scoped URL before any balanced `startAccessingSecurityScopedResource`. A cold App Store launch may drop valid recents outside the sandbox. Needs a signed, actually sandboxed cold-launch test; non-sandbox harnesses cannot prove this. Also test stale-bookmark refresh and disconnected-card recents.
- **Lazy JPEG EXIF enrichment:** `FolderScanner.enrichMetadata` opens a formerly lightweight partner by pathname and retains its old scanned identity without a pre/post verification. External JPEG replacement before Split can combine new EXIF with old review metadata; source mutations later have separate identity guards. Reproduce an actual replacement and determine the media pipeline's displayed failure behavior before escalating.
- **Burst provenance:** Scanner capture dates can fall back to filesystem creation time, so images lacking capture EXIF may form apparent bursts by import/creation times. This is an accuracy/product concern, not evidence of data modification. Consider retaining date provenance if the wording promises capture evidence.
- No power-cut, physical removable-volume reconnect, denied macOS security scope, APFS case-sensitive/exFAT normalization-sensitive volume or signed App Store test was performed by this agent.

## Coverage / areas with no new actionable finding

- Read all of SessionPersistence: folder identity/path ancestry, UUID remount fallback, identity-keyed backup/lock ownership, bounded lock waits, sequence supersession, monotonic snapshot generation, raw-byte CAS, unavailable backup lineage, supported schemas, canonical percent-encoding, relocation authorization, backup-only disconnect/reconnect, retained retry contexts.
- Read core SessionStore lifecycle and mutation paths: opening/replacing/closing/rescanning, generations and detached result gating, paired projection, selection APIs, decision advancement, independent stars/colors, dimension-specific undo, aggregate counters, derived filter ranges, structural replacement, Clean Up apply/undo, source rename/organization apply/undo, export completion, XMP lifecycle gates, trailing/maximum-delay/coalesced saves, final-save/termination barriers.
- Read Models physical metadata/identity storage, content revision, item projections, stable folder hierarchy, sort comparators/group IDs, prepared filters, migration/identity-based rating lookup. No additional confirmed rating identity-transfer or Mixed-state loss found.
- Read FolderScanner enumeration, cancellation bridge, symlink/package/deep-tree policy, deterministic exact/ASCII-case pair rules, parallel metadata chunk ownership, hidden JPEG metadata reuse, final identity checks and default comparator sharing. No additional confirmed missing-file scan acceptance found.
- Read PreparedSessionIndex and SelectionState fully. Stable IDs and visibility locations are consistently rebuilt after ordinary structural changes; pure restore selection correctly chooses an in-selection current. The identified filter path is the exception.
- Read ReviewPreferences, ConnectedDrives and SecurityScopedAccess fully; reviewed relevant test coverage. Connected-drive request sequence/topology/opening-request guards correctly suppress late refresh/click results across stop/restart and same-mount-path replacement. No new confirmed drive race found.
- Read CameraQualityWarnings fully and reviewed threshold/UI contract. Finite/range validation, fraction/locale input, independent switches, photo-only warning eligibility and explicit rendered-vs-RAW source labels are consistent. No new confirmed warning threshold or metadata mutation issue found.
- Read DuplicateBurstAnalysis fully: size buckets, 1 MiB streaming hashes, source identity before/after, bounded thumbnail/hash comparisons, union-find/group de-duplication, capture gap, generation cache integration. No new confirmed destructive action or duplicate membership found. Case/collation suspicion was tested and discarded: the comparison kept `camera` and `Camera` in separate contiguous groups with unique IDs.
- Read LouppeApp commands/service/pending-open and asynchronous Quit paths. File operations/recovery are refused before Quit; XMP cancellation is awaited, and the termination barrier blocks ordinary mutations. The durability-success classification identified above is the relevant remaining boundary.

## Reproduction artifacts and execution

- Harness: `/private/tmp/louppe-audit-2026-09-29/StateAuditRepro.swift`
- Re-run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 /private/tmp/louppe-audit-2026-09-29/run-state-repro.py`
- Output: `/private/tmp/louppe-audit-2026-09-29/state-repro.log`
- Compiler output: `/private/tmp/louppe-audit-2026-09-29/state-repro-build.log`
- JSON-size measurement: `/private/tmp/louppe-audit-2026-09-29/state-json-size-measurement.json`

The compile helper uses the same canonical production Swift sources and existing XMP-only stubs as `Tests/run_performance_checks.sh`, with `DEBUG` for the existing test setup boundary. It emits its executable/module cache exclusively under the audit directory. Compile and run both exited 0. The compiler reported existing macOS 27 AVPlayer notification deprecations, unrelated to these reproductions. Disposable folder permissions were restored after the read-only check.
