# App work completion — 27 September 2026

Scope: the macOS app repository only. The website was not changed.

Later the same day, Alex requested publication. Signing, notarization,
Gatekeeper, and an actual 1.8-to-1.9 update were completed successfully;
see [the 1.9 release record](RELEASE_1.9.0.md). The unpublished/deferred status
below records the earlier completion review, before that release request.

## Reviewed work

Reviewed the current diff, recent app chats, Git history and remote status,
stashes, worktrees, open issues/PRs, release history, backlog, and audit handoffs.
The repository has one worktree and one branch, `main`, no stashes, and no open
GitHub issues or PRs. The latest public release remains 1.8.0; the existing
unpublished cycle is 1.9.0 (11), so no second version bump was made.

The security/XMP/Copy repairs, text preview feature, zoom/review refinements,
and product screenshots are already in `d789443` or its ancestors. The remaining
uncommitted app changes were the compact welcome window, full-content folder
drop target, shorter saving label and regression assertion, and location docs.
Those changes were reviewed together and retained.

## Completion changes

- Repaired `run_video_checks.sh` by including the exact filesystem-path type
  that `DurableFileIO` now uses. This was the actual failing step in GitHub
  quality run 36272158244; the XCTest suite in that run had passed.
- Pinned the official checkout v6 revision and disabled persisted credentials.
- Added a checksum-pinned Gitleaks 8.30.1 script that scans repository history
  plus staged and unstaged tracked changes locally with fully redacted output.
  CI checks out full history and runs it before building.
- Added weekly GitHub Actions dependency update checks and focused ignore
  patterns for local credentials/signing exports. Sparkle's binary and Expat's
  vendored source still require manual upstream review; Dependabot's Actions
  entry does not claim to monitor them.
- Updated the existing 1.9 changelog and stale backlog/audit handoff statements;
  corrected the build instructions to use the installed full Xcode 27 explicitly.

## Verification

- Focused saving-status tests: 3/3.
- Full XCTest suite: 415/415, including all 34 HotkeyTests.
- Strict Swift concurrency/warnings build: passed with full current Xcode.
- Performance/filesystem checks: 74/74, including real disposable Trash/restore.
- Native scrollbar checks: 10/10.
- Native photo/video/audio checks: passed.
- Standalone XMPCore proof: five valid editing-app fixtures passed; malformed
  XML was rejected.
- Redacted history and tracked-edit credential scans: no leaks found.
- Release package: loose app and ZIP preflight passed for 1.9.0 (11).
- Installed `/Applications/Louppe.app`: deep/strict signature verification passed.
- Real `-openFolder` launch: visible session scanned four disposable PNG,
  Markdown, TXT and XML files and wrote a valid four-entry session sidecar.
  Accessibility inspection confirmed the Markdown preview and clickable link;
  a sample Yes decision appeared in the UI with `Session: Saved` and was
  confirmed in the schema-6 sidecar.

Logs are retained under `/private/tmp/louppe-finish-*.log`. The previous installed
app was preserved in `/private/tmp/louppe-finish-install-backup-0i1a66sy/`.
The moved build caches retained obsolete absolute paths; standalone caches were
preserved outside the repository and rebuilt. XCTest ran with a temporary
scratch directory to avoid File Provider metadata invalidating bundle signing.
These were generated-build issues, not source or session-data loss.

The installed package is an ad-hoc-signed development build. No release,
notarized archive, update feed or App Store submission was published. Alex approved committing and pushing the reviewed app work to `main`.
The GitHub quality workflow verifies that final commit after the push; its
result is reported separately from these local checks.

## Explicitly deferred work

These are release acceptance, owner/external tasks, or new product proposals;
they are not incomplete implementations of the reviewed changes:

- Developer ID signing/notarization and a previous-public-version updater
  round trip when Alex decides to release 1.9.
- Real Bridge/Lightroom/darktable acceptance (apps unavailable here), and the
  later Capture One RAW/JPEG resolver/reload acceptance matrix. Synthetic XMP
  and resolver tests pass; this does not claim a new real-app matrix pass.
- Clean-install feedback from Katerina, Andrey's review, Masha's final brand
  asset, and encrypted backup/restore testing of the private updater key.
- Optional branch protection and the remaining future product/technical
  improvements recorded in `BACKLOG.md`.
- App Store screenshot distribution/submission remains a separate owner choice;
  the materials are already preserved in the consolidated media library.
