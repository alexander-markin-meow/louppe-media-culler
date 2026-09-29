# Louppe Media Culler backlog

This is the live backlog for the macOS app. Product and technical work belong
here because they change with the app and should be visible to everyone working
in this repository. The Obsidian `louppe` note remains the home for research,
positioning, publicity planning, and the CAS record.

The latest published app is 1.9.0 (11). Its delivery and verification are in
[the release record](Docs/RELEASE_1.9.0.md).

## Waiting on Alex or collaborators

- [ ] **AUD-23 — Accept native accessibility on the current 1.10.0 build.**
  Check spoken VoiceOver feedback, Full Keyboard Access, increased contrast,
  and Reduce Motion across review, recovery, persistent Gallery controls, and
  connected-drive actions. Record the settings and outcomes; automated hotkey
  and hosted-control checks do not replace spoken/control-by-control acceptance.
- [ ] **AUD-24 — Accept display and provider edge cases.** Exercise
  Welcome/Scanning/Ready on a small display, after resizing/display changes,
  with long warnings, many mounted drives, and delayed File Provider folder
  drops. Every action and message must remain reachable with visible feedback.
- [ ] Back up and restore-test the private automatic-updater signing key.
- [ ] Test a clean install and real culling workflow with Katerina.
- [ ] Ask Andrey for a code review; decide separately whether co-authorship is
  appropriate.
- [ ] Obtain a final shared brand asset from Masha for the app icon and website.
- [ ] Check XMP handoff in real Bridge, Lightroom Classic, and darktable;
   rerun the separate RAW/JPEG conflict and reload workflow in Capture One.
   Automated packet and resolver tests have passed, but these app workflows
   have not been accepted end to end.

## Implemented in the consolidated 1.10.0 build, awaiting acceptance

- [x] Source-folder hierarchy in Sort, with full relative folder headers.
- [x] Review preferences: advancement after a decision, default sort and group
  dividers, and default Gallery/Grid view.
- [x] Connected external drives and SD cards with capacity information and a
  folder chooser starting on the selected drive.

These changes are included in `/Applications/Louppe.app`, alongside RAW display,
Apple Default / RAW 9 selection, and the early-user feedback prompt. The update
remains unreleased. See [the review record](Docs/REVIEW_BUILD.md) for verification
and remaining hardware acceptance. Configurable shortcuts remain deferred to
preserve the established keyboard-safety rules.

## Product improvements
- [ ] Show the Fuji film simulation preset in photo metadata. Fuji camera previews
  have the simulation baked into their pixels; the implemented RAW display mode
  bypasses it through Apple rendering. Do not add a redundant simulation-removal
  control or modify originals.
- [ ] Extend media-format support where macOS capabilities allow it.

## Technical hardening

- [ ] **Diagnose intermittent disposable scan-fixture failures.** The required
  performance suite has occasionally raised `filesChangedDuringScan` or timed
  out on a four-item rescan; unchanged reruns pass all 75 checks. Capture the
  fixture and per-file identity transitions at failure before changing tests.
  Keep production replacement checks and existing timeouts intact.

- [ ] **RAW 9 compatibility acceptance.** Exercise real older/unsupported Macs,
  unavailable model resources and failed downloads, and Fuji compressed/lossless
  compressed RAFs. Confirm retry/default remedies, no stale pixels after decoder
  changes, and intact originals. Current macOS 27 X-T50 uncompressed decoding and
  regression checks passed; broader hardware/compression acceptance remains open.

- [ ] **AUD-05 — Reproduce the remaining ExFAT path-replacement boundary.**
  Investigate path-based Move fallback and launch recovery on disposable ExFAT
  media before changing compatibility or journal behavior. Standard macOS-volume
  Move, Rename, Organize, and undo already bind parent descriptors; preserve the
  ExFAT no-overwrite probe and its documented durability warning.
- [ ] **AUD-21 — Modernize media probing and AV APIs.** Replace semaphore-based
  probing with structured async work, and assess deprecated macOS 27 reader and
  player-notification APIs. Preserve macOS 14 support, bounded decoder lanes,
  real cancellation/reader-exit behavior, and existing playback regressions.
- [ ] **AUD-18 — Expand real-volume and interruption verification.** Extend
  filesystem fault injection and run disposable cases on case-sensitive APFS,
  ExFAT, removable/network volumes, disconnect/remount, and lid-close or simulated
  power-loss boundaries. Verify no overwrite, truthful durability, retained
  recovery evidence, and safe undo/retry. Record which actual volume/interruption
  cases were run; keep native UI acceptance under AUD-23/AUD-24 and release-mode
  performance baselines under AUD-06/AUD-19.

This backlog is the current source of truth for future work. Check each
proposal against the current code and reproduce the issue before starting.

## Audit follow-ups

Transferred from the [retired 29 September audit](Docs/Audits/2026-09-29/README.md).
All 17 confirmed findings are implemented; [the implementation record](Docs/Audits/2026-09-29/implementation.md)
retains tests and evidence. These are additional investigations, optimizations,
and verification tasks, not reopened confirmed bugs. IDs remain stable when a
completed item moves. Reproduce suspected failures and measure performance
before choosing an implementation; preserve originals, identity, CAS, and journal
contracts. Website publication belongs to its own `BACKLOG.md` (WEB-AUD-01).

### Correctness investigations — start here

- [ ] **AUD-01 — Match session write/read size limits.** The reader caps snapshots
  at 512 MiB, while encoding currently has no matching guard. Reproduce with an
  injectable small limit, then refuse an oversized write before either destination
  changes. Prior sidecar/backup bytes must survive; report a retryable failure
  and keep dirty Close/Quit unsafe. No huge allocation is needed for the test.
- [ ] **AUD-02 — Verify lazy JPEG enrichment after replacement.** Replace a
  lightweight JPEG partner before Separate/Split and during EXIF loading. Confirm
  whether new metadata can attach to the old scanned identity/ratings; if so,
  add before/after identity validation and a Rescan remedy. Preserve file metadata
  and prove unrelated replacement bytes are untouched.
- [ ] **AUD-03 — Verify sandboxed recents and routing retry access.** Use a signed,
  actually sandboxed App Store build: cold-launch bookmarks outside the container,
  refresh stale bookmarks, reconnect a card, and repeat routing Review → Back →
  Review → Copy after cancellation/failure. Reproduce before changing balanced
  access-token ownership. Valid recents and chosen destinations must remain usable
  for their intended lifetime; compile-only checks cannot close this task.
- [ ] **AUD-04 — Cancel the final scan identity pass.** Bridge the existing cancel
  flag into the second `validateScannedIdentities` pass after persistence read,
  and check cancellation before entering it. A controlled cancellation must stop
  further identity probes and prevent late scan results without weakening checks.

### Performance — measure before changing

- [ ] **AUD-06 — Reduce large-session structural and save-capture work.** Record
  Release main-actor time and memory at 1k/10k/100k physical files for index rebuild,
  metadata sort, filter/group, and save capture. Reuse unchanged ID/file maps for
  sort-only changes; optimize other capture/rebuild costs where profiling justifies
  it. Preserve prepared ordering, exact selection, shared metadata, and O(1) rating.
- [ ] **AUD-07 — Make Capture Bursts metadata-only.** Present date groups without
  waiting for duplicate hashes or visual decoding. Prove a burst-only request
  performs no content hashing/decode; exact/similar review must still request its
  own evidence, with the existing generation and cancellation guards.
- [ ] **AUD-08 — Move expensive group construction off-main.** Measure initial
  and sensitivity-change grouping at large counts, then background costly hash
  bucket/union-find/date work. Only the current mode/sensitivity/generation may
  publish; rapid changes must cancel or supersede obsolete work and retain caches.
- [ ] **AUD-09 — Maintain the disk thumbnail budget during a long visit.** Add
  coalesced utility-queue accounting/maintenance after enough writes or elapsed
  time. Exercise a small injected size/age budget, including same-day launch;
  pruning must reach its target without a directory walk on every thumbnail,
  blocking scrolling, or compromising trustworthy cached pixels.
- [ ] **AUD-10 — Bound abandoned Info metadata reads.** Measure cold removable
  or network reads after the current dwell. If material, share a bounded/coalesced
  worker keyed by content revision and cancel requests that lose interest.
  Rapid navigation must not accumulate readers or publish/cache stale metadata;
  retain the implemented source-identity checks.
- [ ] **AUD-11 — Avoid unnecessary RAW fit-source work.** Measure cold RAW rapid
  navigation and scale measurement. Use scan-cached oriented dimensions or a dwell
  for uncached recipes when useful, and cancel uninterested source waiters.
  Preserve persistent 100% inspection, the two-operation tile lane, and 128 MiB
  decoded-tile limit; do not replace lazy/tiled work with whole-image bitmaps.
- [ ] **AUD-12 — Make routing confirmation lazy per file.** Flatten route and
  unmatched file rows into individually lazy elements. Verify a tens-of-thousands
  fixture creates only the needed viewport rows while every exact filename/path
  remains available; never truncate the safety-critical preview.
- [ ] **AUD-13 — Measure and remove redundant Copy flushes.** Profile small-file
  batches on local/removable destinations. Consolidate only flushes demonstrably
  duplicated by the held-descriptor copier/publisher and worker. Preserve
  write → sync → stage → publish → directory-sync/checkpoint order, injected copier
  behavior, and post-side-effect recovery before accepting a speedup.
- [ ] **AUD-14 — Move export destination preflight off-main.** Measure per-source
  volume queries on large/remote selections, then freeze inputs and validate on a
  worker. Keep chosen-folder access alive, expose progress/cancellation, and pass
  the exact validated binding into the worker; no early journal/media mutation.
- [ ] **AUD-15 — Improve feedback/cancellation inside large copies.** Investigate
  `fcopyfile` callbacks or bounded chunks for a single large video. Show actual
  byte progress and reach a safe cancel boundary without waiting for the whole
  file. Retain only identity-proven owned partials and existing rollback/remount
  rules; demonstrate the behavior on disposable files before changing the copier.
- [ ] **AUD-16 — Measure compact session JSON.** Compare actual Foundation encoder
  bytes and save/CAS costs at 1k/10k/100k entries. Confirm whether human-editable
  formatting is needed before dropping pretty printing. Preserve sorted-key
  reproducibility, schema/lineage compatibility, and exact byte-CAS semantics.
- [ ] **AUD-17 — Budget bulk undo by retained bytes.** Measure repeated Select All
  decisions/Clear All at large counts. If the 500-step cap retains excessive
  snapshots, add a byte-based limit with clear eviction. Normal per-photo undo,
  independent ratings, and journaled file-operation undo must remain correct.

### Further verification

- [ ] **AUD-19 — Establish a camera/color and GPU-memory baseline.** Build a small,
  licensed real RAW/JPEG/color-profile corpus with orientation/transparency cases.
  Compare previews, RAW/histogram/clipping, and 100% tiles against known reference
  renders; measure Release GPU/RSS during rapid navigation and zoom. Record actual
  coverage and verify memory/decoder bounds. Synthetic replacement tests already
  pass; they do not substitute for real camera-decoder/color acceptance.
- [ ] **AUD-20 — Inventory dependency/security coverage.** Record exact pinned
  Sparkle, Expat, Adobe XMP, and relevant website dependency versions, vendor patches,
  licenses, and current official advisories. Investigate applicable exposures and
  extend bounded hostile-XMP tests as needed. Keep the original vendor-review scope
  limits explicit; inventory/parser tests do not prove every vendored line safe.

ExFAT/interruption testing, AV migration, native accessibility, and display/provider
acceptance are carried by AUD-05/AUD-18, AUD-21, and AUD-23/AUD-24 above.

## Later / research

- [ ] SD-card ingest with naming templates and review while copying.
- [ ] Preview-first EXIF rule routing or auto-culling. It must never silently
  move originals.
- [ ] Focus peaking and detail/edge inspection modes.
- [ ] Side-by-side comparison with synchronized zoom.
- [ ] Scenes / chronological-story review.
- [ ] iPad Grid companion.
- [ ] Optional embedded metadata in exported JPEG copies only, with a separate
  safety design; never alter originals.

- [ ] **AUD-22 — Define capture-date provenance for bursts.** Decide whether
  filesystem creation/import dates should count as capture evidence when EXIF is
  missing. Test mixed EXIF/fallback fixtures and retain provenance or adjust copy
  if needed; do not describe inferred groups as certain capture sequences.

## Decisions already made

- Custom photo backgrounds are not planned: they conflict with Louppe's
  single neutral review background.
- Capture One is not a standalone task. Current XMP export already supports
  Capture One interoperability; further integration needs a separately scoped
  proposal.
