# Session state and persistence fixes — 2026-09-29

Canonical repository: `/Users/alexander_markin/Documents/code/louppe/app`.
Implemented the four confirmed findings S1–S4 from `Docs/Audits/2026-09-29/session-state.md` in the existing dirty tree. Existing changes were preserved. No Models.swift, DurableFileIO.swift, documentation, changelog, installation, Git branch, commit, or push changes were made by this agent.

## S1 — pair-component Clean Up honors the target member’s scope

`Sources/Louppe/SessionStore.swift:3067` now resolves the physical target’s displayed index and requires that exact index in the chosen All/Filtered/Selected scope. `hasCleanUpTargets` at line 3101 uses the same rule. It no longer qualifies a JPEG because its RAW partner is selected/visible, or vice versa.

Together projection still maps both physical IDs to one displayed pair, so selecting/showing that pair authorizes either component. Counts and confirmation use the same exact worker snapshots. The existing counterpart identity validation remains intact.

Two new tests in `Tests/LouppeTests/PairComponentCleanUpScopeTests.swift:7` and line 40 cover both removal directions, Separate and Together projections, Selected/Filtered/All scopes, positive and excluded target cases, file/byte counts, menu enablement, unchanged source bytes, Mixed pairs, and independent decisions/stars/colors. These planning tests do not move originals to Trash; the existing CleanUpWorkerSafetyTests own real Trash/undo coverage.

## S2 — observed rename lineage and durable save success are separate

`Sources/Louppe/SessionPersistence.swift:794` adopts only exact desired sidecar bytes into the access’s CAS revision and assigned snapshot generation. `recordObservedSave` at line 1598 does not advance the successfully persisted sequence. A failed request therefore remains retryable with the same sequence and does not collide with its own visible rename.

`retryDirectorySync` at line 1611 attempts the missing full parent-directory flush under the existing cross-process transaction lock. It validates before and after the flush. Sidecar recovery requires the captured folder identity and exact desired sidecar revision. Backup recovery at line 1626 also rechecks the source-folder authority, allowed sidecar lineage, and exact backup bytes. Changed folders or externally edited destinations fail closed.

Only a successful recovery flush or a fully synced backup reaches `recordSuccessfulSave` and a discard-safe SaveResult. If sidecar flush recovery and backup both fail, the result remains `.failed`; SessionStore’s existing generation accounting consequently keeps the dirty live session open and refuses unsafe Quit. A durable fallback reports `.savedToBackup`, including when the source happens to reconnect before backup validation: visible sidecar bytes alone do not justify claiming sidecar durability.

An interrupted sidecar’s exact possible revision is retained even when backup publication fails. A later reconnect or an offline retry that reconnects during validation may adopt only that per-access revision. Ordinary older-backup rollback and unmarked external changes remain conflicts. Observed generations advance monotonically; successfully persisted sequence ordering is unchanged.

Added a dedicated injected `beforeDirectorySyncRetryForTesting` boundary inside SessionPersistence; DurableFileIO’s flush/rename contracts and production implementation are unchanged.

New regression cases in `Tests/LouppeTests/SessionDurabilityTests.swift`:

- Line 3004: sidecar rename visible, directory flush recovery and backup fail; discard unsafe; same-sequence Retry succeeds without CAS conflict; only durable completion supersedes the request.
- Line 3046: injected trailing sidecar error, actual directory flush recovery succeeds, and a regular-file backup root cannot host a fallback; success is justified by the real recovered flush.
- Line 3070: failed sidecar flush recovery with a real durable backup reports backup success and is discard safe.
- Line 3094: offline backup rename visible but both initial/recovery flushes fail; discard unsafe; same-access/same-sequence Retry advances the backup generation without recreating source.
- Line 3132: sidecar rename followed by disconnection and backup failure; original reconnect allows exact owned-sidecar adoption and retry.
- Line 3167: real SessionStore dirty final-save/Quit flow refuses discard, retains rating/ready state/warning/Retry, and becomes safe after the injected failures are cleared.
- Line 3268: replacing the source folder at the recovery-flush boundary returns sourceFolderChanged and preserves replacement bytes.
- Line 3296: external backup edit at that boundary returns sidecarChanged and preserves the external bytes.
- Line 3323: a failed request retried offline reconnects during backup validation; only the marked sidecar is adopted, backup success remains truthful, generations are monotonic, and later sidecar repair succeeds.

The existing reconciliation tests `testOfflineBackupAdoptsACommittedRenameAfterTrailingError` and `testReconnectedSidecarAdoptsTheExactBackupOwnedCommit` are included in the focused suite. Their exact-byte adoption remains valid; recovery now adds a real flush before declaring the reconciled destination durable.

## S3 — filtered explicit selection owns the displayed current photo

`SelectionState.replacementCurrentIndex` at `Sources/Louppe/SelectionState.swift:84` selects the first surviving explicit selection member in prepared display order when the former current is outside the selection. Structural restore and `SessionStore.applyFilter` at line 1145 share it. The nearest visible-item fallback remains for implicit/empty selection.

The new test at `Tests/LouppeTests/SelectionStateTests.swift:101` removes the current photo from a disjoint selection while leaving an unselected intervening photo visible. It covers ascending/descending display order and advancement disabled. The displayed current remains inside the surviving selected decision/stars/color targets; the intervening unselected photo stays unchanged.

## S4 — descriptor errors retain actionable errno categories

`SessionPersistence.failureReason` at line 1868 extracts every `DurableFileIO.IOError.system` errno directly. Descriptor and NSError POSIX errors use the same mapping at line 1892. The finite-lock-wait operation retains `.busy`; Cocoa error mapping remains intact.

The new real-I/O test at `Tests/LouppeTests/SessionDurabilityTests.swift:3223` makes the source directory read-only after access capture, verifies `.savedToBackup(sidecarFailure: .permissionDenied)`, and restores permissions. The injected production write boundary at line 3240 verifies ENOSPC, ENODEV, EACCES, EPERM, EROFS, and ENOENT while a real read-only sidecar write fails. Existing contention tests cover `.busy`.

## Coordinated XMP boundary

At the root agent’s explicit request, the `prepareXMPPublication` input call at `Sources/Louppe/SessionStore.swift:4203` now passes `sourceFolder` and `persistenceAccess?.folderIdentity`, in the coordinated initializer order. Root owns the input type, publication validation, and XMP tests.

## Verification

Focused command (full installed Xcode, unique scratch directory):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/louppe-fixes-2026-09-29/session-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/louppe-fixes-2026-09-29/session-module-cache \
swift test --disable-keychain \
  --scratch-path /private/tmp/louppe-fixes-2026-09-29/session-build \
  --filter 'SessionDurabilityTests|SelectionStateTests|PairComponentCleanUpScopeTests'
```

Result: **80 tests passed, zero failures**, exit 0. PairComponentCleanUpScopeTests: 2; SelectionStateTests: 18; SessionDurabilityTests: 60. The suite includes all 14 newly added regression methods and the existing reconciliation, CAS/contention, migration, generation-ordering, disconnect/reconnect, autosave/coalescing, folder-transition, and termination coverage. Test execution took 6.9 seconds after compilation. Log: `/private/tmp/louppe-fixes-2026-09-29/session-tests.log`.

`git diff --check` passed for this agent’s six changed files. Initial attempts exposed and coordinated concurrent Audio/XMP compile errors owned by other agents. No full-suite/performance/native/install checks were duplicated; root owns integration and actual launch verification.

Fault tests prove unsafe/discard-safe classification, exact lineage, retries, and real flush recovery on this host. They do not simulate an actual power cut or physical removable-volume disconnect. No additional optimization was implemented. The audit’s compact JSON opportunity remains separately documented and is not mixed into the correctness fixes.


## Final integration test observation correction

The integrated run exposed two nondeterministic UI observations in the new dirty Quit regression: `saveSessionForTermination` returns the worker SaveResult and applies durability before its separate MainActor completion observer necessarily decrements `activePersistenceSaveCount`. `sessionSaveStatus` reports Saving while that count is nonzero, and `canRetryPersistence` likewise waits for it to reach zero.

The regression now uses the existing `waitForPersistenceIdleForTesting` barrier before those UI assertions after both failed and successful final saves. Its exact failed/successful SaveResults, discard safety, retained ready session/rating, and saved sidecar rating assertions remain intact. No production source change was needed.

Final affected-suite recheck: **60 SessionDurabilityTests passed, zero failures, exit 0**, 5.6 seconds. Log: `/private/tmp/louppe-fixes-2026-09-29/session-durability-final-tests.log`. The formerly timing-sensitive dirty Quit test additionally passed **five consecutive isolated repetitions**, exit 0, in `/private/tmp/louppe-fixes-2026-09-29/quit-observer-repeat-tests.log`.
