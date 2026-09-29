# File safety audit implementation — 2026-09-29

Canonical checkout: `/Users/alexander_markin/Documents/code/louppe/app`. This subtask implements FS-1, FS-2, FS-3, FS-4, FS-5, and FS-PERF-1 from `Docs/Audits/2026-09-29/file-safety.md`. No commits, branches, pushes, installation, or source edits in the compatibility folder. Existing unrelated edits were preserved. Root owns SessionStore, Models, documentation/changelog, standalone XMP changes, packaging, and app integration verification.

## Files changed by this subtask

- `Sources/Louppe/ExportWorker.swift`: planner rejection/cancellation and suffix reservation optimization; Copy planning cancellation result.
- `Sources/Louppe/SourceOrganization.swift`: scanner-visible container validation, generated folder sanitization, existing folder flag checks.
- `Sources/Louppe/SourceOrganizationWorker.swift`: folder name and actual hidden/package flag checks during directory preparation, including raced EEXIST directories.
- `Sources/Louppe/FileOperationJournal.swift`: generated-partial rollback, retired-XMP cleanup recovery, journal-specific regular-file checks, nonblocking exact comparison opener.
- `Sources/Louppe/DurableFileIO.swift`: only added `O_NONBLOCK` to `syncFile` opener. This file was then released to root for the standalone XMP BoundDirectory extension. Its other current changes belong to root.
- `Tests/LouppeTests/FileSafetyAuditRegressionTests.swift`: eleven focused XCTest methods with real disposable I/O and explicit recorded/unrecorded/replaced-file variants. No timing assertions.

## Implemented behavior and preserved contracts

### FS-1 — internally conflicting media/XMP family filenames

`ExportWorker.makePlan` builds the complete initial filename family and immediately rejects internally equivalent normalized names. Adding the same numeric suffix cannot separate those names. The original PHOTO.JPG/PHOTO.jpg case-sensitive family is still grouped by XMPSidecarResolver but now returns an actionable localized planning error before any destination entry probe, journal activation, or media I/O. No family is silently split or partially exported.

The planner also checks Task cancellation and its explicit cancellation closure during input grouping, family processing, and every suffix retry. Copy passes its CancelFlag closure through planning; planning cancellation returns a cancelled result with its reason, zero failed photos, and no recovery/journal failure. Numeric suffix increments reject overflow rather than trapping.

Regression methods: `testEquivalentNamesWithinXMPFamilyFailBeforeDestinationProbes`, `testCancellationDuringCollisionSearchStopsCopyBeforeJournalActivation`.

### FS-PERF-1 — repeated basename planning

The next suffix is cached by the entire sorted normalized unsuffixed family filename set. A JPEG-only family can still use its unsuffixed filename when a prior RAW+JPEG family was suffixed solely because the RAW target was already occupied. Reserved batch names are checked before constructing exact URLs or probing the filesystem. External occupancy remains checked, and every publish continues to use existing exclusive/no-overwrite workers and identity-bound destination checks.

Regression methods: `testRepeatedBasenamesNeedOneDestinationProbePerFile` (800 files, exactly 800 entry probes), `testSuffixCachePreservesWholeFamilyAndAlreadySuffixedNames` (RAW-only external collision, differing family composition, existing numeric suffixes, final target uniqueness, existing bytes unchanged).

The cache addresses repeated identical families. Very large numbers of independently existing suffixed files or highly overlapping nonidentical family sets still require collision search. Search is cancellable. This is an intentional limit, not a machine-sensitive timing claim.

### FS-2 — organized originals excluded by scanner traversal

User container names beginning with `.` or recognized macOS package/bundle extensions are rejected with a visible-folder error. Directory-constrained UTType lookup is required: unrestricted `.app` extension lookup resolves a different regular-file application type on this system. Generated camera/lens/origin/etc folder components retain their metadata text but gain a leading underscore for hidden names or a trailing underscore for package names.

Planning rejects existing hidden/package directories. The worker rechecks every component's name and actual resource flags before moving original files, including a directory which appears during mkdir's EEXIST race. This prevents a stale preview from moving files into a Finder-hidden existing container. Source root semantics and exact path construction remain unchanged.

Regression methods: `testOrganizationRejectsHiddenAndPackageContainers` (.Hidden, Photos.app, .bundle, .photoslibrary, .framework), `testGeneratedOrganizationFoldersRemainScannableAndUndoable` (.Camera, Photos.app, Photos.photoslibrary; actual organize, scan count, undo, original bytes), `testOrganizationRefusesFinderHiddenFolderBeforeAndAfterPreview` (UF_HIDDEN flag in a normally named container).

### FS-3 — owned generated partial blocks Move rollback

Rollback accepts a `.started` generated artifact only when its current stable identity matches the durable checkpointed inode. Such a partial is removed through existing exclusive two-path quarantine cleanup without requiring the digest of the not-yet-complete intended packet. `.staged`/`.completed` still require the sealed complete digest. Missing ownership, replacement inode, multiple candidates, or invalid staged content stays unresolved and preserved.

Recovery restores the original media location before cleaning the generated artifact. Repeated recovery after success discovers no active operation. Crash after cleanup's exclusive transfer to the alternate reserved name is also recoverable using the same checkpointed identity. A crash before any identity checkpoint cannot safely infer ownership and deliberately remains unresolved.

Regression method: `testGeneratedMovePartialRecoveryRemovesOnlyRecordedInode`, with recorded incomplete, recorded complete, cleanup-quarantined, staged complete, malformed staged partial, unrecorded, and replaced inode variants. Original media bytes/location and unrelated replacement bytes are asserted.

### FS-4 — retired XMP cleanup interrupted at quarantine name

Completed XMP family recovery accepts the single owned retired packet at either the retirement target or its journal-planned quarantine path. It verifies stable recorded identity and the expected original packet digest, then reuses exclusive two-path cleanup. A source and another candidate together, two candidates, or replacement inode remains unresolved. A completed cleanup with neither candidate returns success. Completed media and merged destination XMP stay intact.

Regression method: `testCompletedXMPRetirementRecoversEveryCleanupLocation`, with target, quarantine, already unlinked, replacement, and dual-candidate variants; successful recovery retry is idempotent.

### FS-5 — FIFO journal/read boundary can block indefinitely

Journal creation and identity-bearing checkpoints require regular media files. Existing entries in journal plan validation likewise require S_IFREG, so malformed FIFO, directory, or symlink media cannot enter a recovery read/mutation path. The exact byte-comparison opener and DurableFileIO.syncFile use O_NONBLOCK before fstat's regular-file validation, closing the open-before-type-check FIFO blocking window.

Public `FileOperationJournal.captureIdentity` and private generic identity capture preserve directory semantics. `SessionPersistence.SourceFolderIdentity.capture` and bound-directory callers continue to work. The regular-file constraint applies to journal media and recovery entries, not global filesystem identity.

Regression methods: `testJournalRejectsNonregularMediaWithoutChangingFolderIdentityCapture` (directory API remains valid; FIFO/directory/symlink starts rejected; comparison false and sync throws promptly), `testMalformedFIFOJournalReturnsUnresolvedWithoutReadingTheFIFO` (forged durable plan with FIFO source; generated copy preserved, destination unpublished).

## Original audit probes rerun against updated actual Debug module

Linker script: `/private/tmp/louppe-fixes-2026-09-29/compile-file-safety.py`.
Probe source: `/private/tmp/louppe-fixes-2026-09-29/file-safety-harness.swift`, adapted from the original audit harness only to catch newly expected errors, clean disposable fixtures, and count real lstat destination probes. Each process is bounded with a 30-second subprocess timeout.

- Collision: one two-member `publish` XMP family; planner returns equivalent-destination-name error promptly instead of looping.
- Generated partial: unresolved operations/files 0; removed partial copies 1; owned partial absent.
- Retired packet quarantine: unresolved operations/files 0; quarantine absent.
- FIFO: rejected before operation starts; no hang.
- Hidden `.Hidden` and package `Photos.app`: rejected before organization.
- Scaling: successful complete plans at every count below, with exactly one destination probe per file.

| Files | Original Debug seconds | Updated Debug seconds | Updated filesystem probes |
| ---: | ---: | ---: | ---: |
| 100 | 0.127 | 0.004662 | 100 |
| 200 | 0.508 | 0.008400 | 200 |
| 400 | 2.131 | 0.017405 | 400 |
| 800 | 8.725 | 0.035293 | 800 |

These are local diagnostic measurements, not test thresholds. The original empty-destination one-file family algorithm performs n(n+1)/2 probes by code inspection (320,400 at n=800); the updated n count was instrumented and measured. The 800-file time improved approximately 247× on this run.

Evidence: `/private/tmp/louppe-fixes-2026-09-29/file-safety-probe-collision.log`, `file-safety-probe-recovery.log`, `file-safety-probe-retirement.log`, `file-safety-probe-fifo.log`, `file-safety-probe-hidden-.Hidden.log`, `file-safety-probe-hidden-Photos.app.log`, `file-safety-probe-scaling.log`.

## Test execution status

Passed using full Xcode (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`) and the unique isolated scratch `/private/tmp/louppe-fixes-2026-09-29/file-safety-build`:

1. `swift test --disable-keychain --scratch-path /private/tmp/louppe-fixes-2026-09-29/file-safety-build --filter FileSafetyAuditRegressionTests`: **11 tests, 0 failures**, 1.077 seconds. Log: `/private/tmp/louppe-fixes-2026-09-29/file-safety-focused-tests.log`.
2. `swift test --disable-keychain --scratch-path /private/tmp/louppe-fixes-2026-09-29/file-safety-build --filter 'ExportWorkerSafetyTests|FileOperationJournalTests|SourceOrganizationTests|XMPPhase7Tests|DurableFileIOTests|MultiDestinationExportTests|CleanUpWorkerSafetyTests|RecoveryGatingTests|FolderScannerFilenamePolicyTests'`: **141 tests, 0 failures**, 4.070 seconds. Log: `/private/tmp/louppe-fixes-2026-09-29/file-safety-adjacent-tests.log`.
3. Relinked original probes after both passing test runs, then reran all modes against that final current app module. Every process exited 0 promptly and behaved as recorded above; compile log `/private/tmp/louppe-fixes-2026-09-29/file-safety-probe-compile.log`.
4. `git diff --check` passed for this subtask's source/test files.

Total focused validation: **152 passing tests** plus the original seven probe executions. No machine-sensitive latency threshold was added to tests.

## Review entry points

Current one-based lines in the canonical app checkout:

| Finding | Source entry point | Focused regression entry |
| --- | --- | --- |
| FS-1 | `Sources/Louppe/ExportWorker.swift:274` (PlanningError), `:292` (planner), `:533` (Copy cancellation result) | `Tests/LouppeTests/FileSafetyAuditRegressionTests.swift:8`, `:90` |
| FS-PERF-1 | `Sources/Louppe/ExportWorker.swift:310` (whole-family next suffix), `:387` (cache start), `:399` (reserved-name shortcut) | `Tests/LouppeTests/FileSafetyAuditRegressionTests.swift:48`, `:67` |
| FS-2 | `Sources/Louppe/SourceOrganization.swift:1080` (visibility), `:1168` (generated names), `:1250` (existing folder flags); `Sources/Louppe/SourceOrganizationWorker.swift:207`, `:247` | `Tests/LouppeTests/FileSafetyAuditRegressionTests.swift:125`, `:143`, `:184` |
| FS-3 | `Sources/Louppe/FileOperationJournal.swift:1047` (rollback) | `Tests/LouppeTests/FileSafetyAuditRegressionTests.swift:213` |
| FS-4 | `Sources/Louppe/FileOperationJournal.swift:1302` (owned retirement candidate) | `Tests/LouppeTests/FileSafetyAuditRegressionTests.swift:266` |
| FS-5 | `Sources/Louppe/FileOperationJournal.swift:329`, `:533`, `:2132`, `:2549`, `:2765`; `Sources/Louppe/DurableFileIO.swift:532` | `Tests/LouppeTests/FileSafetyAuditRegressionTests.swift:325`, `:349` |

## Remaining verification limits

Root owns source-tree-wide strict concurrency/full-suite checks and packaged app integration/launch. This subtask did not operate the GUI or install the app. Recovery regressions create authentic durable journal states and exact filesystem boundaries rather than killing a live user-media process or forcing a real disk-full condition. Newly created but never identity-checkpointed generated files remain preserved/unresolved by design; filenames and incomplete bytes cannot prove ownership. Tests cover those refusals as well as successful cleanup. Package recognition depends on macOS type registration during preview; actual created/existing directory resource flags are rechecked in the worker before media moves. No source-side identity API or exact filesystem path helper contract was broadened or weakened.
