# Louppe Media Culler backlog

This is the live backlog for the macOS app. Product and technical work belong
here because they change with the app and should be visible to everyone working
in this repository. The Obsidian `louppe` note remains the home for research,
positioning, publicity planning, and the CAS record.

The latest published app is 1.9.0 (11). Its delivery and verification are in
[the release record](Docs/RELEASE_1.9.0.md).

## Waiting on Alex or collaborators

- [ ] Listen through the 1.9.1 workflow with VoiceOver, increased contrast,
  and Reduce Motion on Alex's Mac. Live accessibility-tree and keyboard checks
  passed; spoken feedback and those display settings still need acceptance.
- [ ] Back up and restore-test the private automatic-updater signing key.
- [ ] Test a clean install and real culling workflow with Katerina.
- [ ] Ask Andrey for a code review; decide separately whether co-authorship is
  appropriate.
- [ ] Obtain a final shared brand asset from Masha for the app icon and website.
- [ ] Check XMP handoff in real Bridge, Lightroom Classic, and darktable;
   rerun the separate RAW/JPEG conflict and reload workflow in Capture One.
   Automated packet and resolver tests have passed, but these app workflows
   have not been accepted end to end.

## Product improvements

- [ ] Offer a review/sort view that respects the source-folder hierarchy, not
  merely folder-name ordering.
- [ ] Add focused review preferences: advancement after rating, default sort,
  and default view. Evaluate configurable shortcuts only if they preserve the
  established keyboard-safety rules.
- [ ] Show connected external drives and SD cards with useful availability and
  capacity information.
- [ ] Extend media-format support where macOS capabilities allow it.

## Technical hardening

- [ ] Investigate the remaining path-based ExFAT Move fallback and launch
  recovery with a reproducible failure case before changing their compatibility
  or journal behavior. Standard macOS-volume Move, Rename, Organize, and undo
  now bind opened parent directories.
- [ ] Replace semaphore-based video/media probing with structured async work.
- [ ] Extend existing filesystem fault injection and UI/accessibility tests;
  add release-mode performance baselines.

This backlog is the current source of truth for future work. Check each
proposal against the current code and reproduce the issue before starting.

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
