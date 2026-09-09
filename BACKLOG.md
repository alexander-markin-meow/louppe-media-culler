# Louppe Media Culler backlog

This is the live backlog for the macOS app. Product and technical work belong
here because they change with the app and should be visible to everyone working
in this repository. The Obsidian `louppe` note remains the home for research,
positioning, publicity planning, and the CAS record.

## Current delivery — 1.8.0

Finish verification and release of the current worktree. It already includes:

- optional Quality Cues with adjustable ISO, shutter-speed, and clipping
  thresholds;
- local exact-duplicate, likely-similar, and capture-burst review groups;
- explicit Copy-only routing to multiple export destinations;
- source-folder organization, command-palette work, and folder drag-and-drop;
- legacy-session migration and smaller review-flow fixes.

These are active delivery work, not new backlog items. Do not advertise them
until the corresponding public GitHub release is live.

## Next — release readiness and trust

- [ ] Test a clean install and real culling workflow with Katerina.
- [ ] Ask Andrey for a code review; decide separately whether co-authorship is
  appropriate.
- [ ] Obtain a final shared brand asset from Masha for the app icon and website.
- [ ] Add Developer ID signing, notarization, and a release-provenance checklist.
- [ ] Back up and restore-test the automatic-updater signing key.

## Product improvements

- [ ] Offer a review/sort view that respects the source-folder hierarchy, not
  merely folder-name ordering.
- [ ] Add focused review preferences: advancement after rating, default sort,
  and default view. Evaluate configurable shortcuts only if they preserve the
  established keyboard-safety rules.
- [ ] Improve long folder-name presentation while retaining access to the full
  path.
- [ ] Show connected external drives and SD cards with useful availability and
  capacity information.
- [ ] Extend media-format support where macOS capabilities allow it.

## Technical hardening

- [ ] Make file operations descriptor-relative to close remaining path-swap
  races.
- [ ] Move costly session-snapshot construction off the main actor; evaluate a
  rating write-ahead log.
- [ ] Replace semaphore-based video/media probing with structured async work.
- [ ] Add filesystem fault injection, broader UI/accessibility coverage, and
  release-mode performance baselines.
- [ ] Complete the VoiceOver and keyboard-navigation audit.

The detailed evidence and acceptance criteria for these items remain in
`Docs/CODEBASE_AUDIT.md` and `Docs/CODEBASE_AUDIT_2026-07-31.md`. Reassess an
item against the current worktree before scheduling it: those audits predate
the in-progress 1.8.0 work.

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

## Decisions already made

- Custom photo backgrounds are not planned: they conflict with Louppe's
  single neutral review background.
- Capture One is not a standalone task. Current XMP export already supports
  Capture One interoperability; further integration needs a separately scoped
  proposal.
