# Independent review of X1 — 2026-09-29

Reviewed the final canonical implementations in:

- `Sources/Louppe/XMP/XMPPublication.swift`
- `Sources/Louppe/XMP/XMPMetadataStore.swift`
- `Sources/Louppe/DurableFileIO.swift`
- `Tests/LouppeTests/XMPPublicationIdentityTests.swift`

Read-only XMP review; no edits to the reviewed canonical source/test files by this reviewer. Relevant app/shared AGENTS, session identity, file-operation, and performance rules were applied. Root owns the final integration suite and application launch.

## Outcome

**No confirmed remaining X1 correctness issues after the final temporary-ownership guard.** One concrete publication gap was independently reproduced during review, communicated to root, repaired by root, and reverified against the final production helper.

## Confirmed gap found and resolved

The first descriptor-bound `atomicWrite` implementation checked owned temporary identity only for cleanup. It could still rename a different file that another writer placed at the generated temporary name during final validation. Packet target CAS could remain valid throughout: the original target was unchanged, but the unowned temporary replaced it. Later XMP readback could detect wrong bytes only after the old target had already been lost.

The standalone reproduction compiles the actual canonical `DurableFileIO.swift` and `XMPExactFileSystemPath.swift`. Its only stub provides the existing exact-path byte helper; publication, descriptor opening, writing, flushing, renaming, and cleanup use production code. It checks the old target bytes, atomically substitutes the temporary during `validateBeforePublish`, and inspects the target afterward.

Before the guard (`temp-ownership-repro.log`, compile/run exit 0):

```text
bound atomicWrite returned success: true
target original preserved: false
target intended bytes: false
target substituted bytes: true
```

The final helper captures immutable temporary stat after its real file flush, then uses descriptor-relative `fstatat(..., AT_SYMLINK_NOFOLLOW)` immediately before rename. Regular type, device, inode, birth time, size, mtime, and ctime must still match. This covers both different-inode atomic substitution and same-inode content edits without comparing against an obsolete pre-write size/timestamp.

After recompiling against the final helper (`temp-ownership-repro-final.log`, compile/run exit 0):

```text
bound atomicWrite rejected substitution: DestinationChanged()
bound atomicWrite returned success: false
target original preserved: true
target intended bytes: false
target substituted bytes: false
```

Root also added `testTemporarySubstitutionAndInPlaceEditCannotReplaceOriginalPacket`: it covers both edit forms through the real XMP store and final-validation hook, preserves the old packet, preserves a foreign replacement temporary, and cleans up only the owned inode after an in-place edit.

## Reviewed contracts

- **Source authority:** production `SessionStore` supplies scan-time source folder identity. Supplying a folder without its identity fails closed. Preflight freezes each physical member's scan identity, including unselected siblings in the shared stem family. Missing identity, regular-file replacement, deletion, symlink/FIFO/directory replacement, and whole-folder replacement become external-modification conflicts rather than publishing old review metadata.
- **Repeated validation:** source checks surround preflight packet preparation, run again during worker preparation, and run at the final flushed-temporary boundary. The already-current path also validates source identity before claiming success. Source-folder and physical-file checks use stable identity and exact path authority, not mutable folder timestamps or display filenames.
- **Descriptor-bound mutation:** source-validation publication holds the original sidecar parent directory. Temporary creation, final rename, directory flush, and cleanup are relative to that held descriptor. A replaced pathname cannot redirect publication or cleanup into the replacement folder. Parent binding is rechecked before publication and after flushing.
- **Owned cleanup:** descriptor-relative cleanup checks regular type/device/inode before unlinking. An unowned replacement at the temporary name is retained; the original target remains intact on validation failure. The final added guard closes the formerly missing ownership check for the rename source itself.
- **Packet CAS:** updates retain both exact packet bytes and the full XMP revision. Creates remain exclusive and reject a newly appearing destination. Worker preparation must still match the frozen preflight fingerprint. External edits at the final validation hook remain visible conflicts and their bytes are preserved. Committed packets are reread and parsed before success.
- **Legacy API:** the optional validation argument preserves existing direct XMP store callers that do not carry a standalone source-validation plan. Those callers retain their original packet CAS, exclusive create, flush, and readback behavior. The production standalone worker always passes its immutable validation; a publishable plan lacking it fails closed. Other journaled operation paths retain their separate identity ownership.
- **Cancellation/bounds:** worker fan-out remains three long-lived workers, with cancellation before final mutation and the existing 64 MiB regular-file packet read bound. FIFOs are rejected without blocking because packet reads use O_NONBLOCK plus regular-type validation.

## Evidence and limits

- Harness: `/private/tmp/louppe-fixes-2026-09-29/BoundWriteTempRepro.swift`
- Initial failure: `/private/tmp/louppe-fixes-2026-09-29/temp-ownership-repro.log`
- Final verification: `/private/tmp/louppe-fixes-2026-09-29/temp-ownership-repro-final.log`
- Final compiler log: `/private/tmp/louppe-fixes-2026-09-29/temp-ownership-build-final.log`
- `git diff --check` passed for the reviewed files.

This independent run specifically verifies the concrete temporary-substitution correction. Root is running the full XMP/integration tests, including the new same-inode case. No power-cut, physical removable-volume, or alternate filesystem test was performed by this reviewer. Path validation still has the ordinary narrow interval between a check and its syscall; descriptor-relative mutation keeps that interval from redirecting writes into a replacement parent.
