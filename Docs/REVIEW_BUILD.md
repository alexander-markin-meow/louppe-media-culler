# louppe - to review

Historical review and consolidation record, 29 September 2026. The current
unreleased cycle is 1.10.0 (12), following published 1.9.0 (11). Earlier sections
record the separate review builds and their original verification; those copies
are superseded by the consolidated production app.

## Scope

1. **Folder hierarchy:** the existing Sort popover gains a source-tree order.
   Root files precede nested folders, parents precede descendants, and sibling
   folders use natural ordering. Reversing changes sibling order. Browser/Grid
   dividers show full relative paths, and filtering preserves the hierarchy.
2. **Review preferences:** a native Review settings tab controls advancement
   after Yes/No commands and defaults for new folders: view, sort, direction,
   and group dividers. Existing review and same-folder rescans keep their
   layout. Tile controls, stars, and color labels retain their existing behavior.
3. **Connected drives:** a compact start-screen section lists physical external
   drives/cards with available and total capacity. A drive opens the normal
   folder chooser at its root. Mount changes invalidate stale entries and
   opening revalidates the selected device. Five recent folders and every
   connected drive appear in aligned columns, with additional drive columns
   when needed. The page does not scroll, and the window cannot shrink below
   the size its content needs. No automatic whole-drive scan.

The existing toolbar structure, neutral background, and purple accent remain.

## Separate app

`Scripts/build_review.sh` produces **louppe - to review.app** and a matching ZIP.
Its identifier is `com.alexandermarkin.louppe.review2`; the production identifier
remains `com.alexandermarkin.louppe`. Preferences, recents, and window state are
separate. Automatic update startup and the update settings/command are disabled.

Folder sessions retain the normal `.louppe_session.json` format and the existing
shared persistence/file-operation safety boundaries. Opening the same media in
both apps therefore shares folder decisions; the review copy is not a separate
photo library. UI verification uses disposable copies of existing demo photos.

## Verification

- Complete XCTest run: 450 tests, zero failures, one explicit skip. All 34
  HotkeyTests passed, including real installed-monitor/window events. The
  skipped hosted-drive test encounters an empty SwiftUI accessibility tree
  inside XCTest; the production drive view was instead inspected in a native
  fixture app through computer use.
- Focused feature tests: 11 hierarchy, 13 preference, and 8 drive logic/race
  tests passed. The 10,000-item hierarchy test took about 0.10 seconds.
- Required performance and file-safety script: 75/75 passed against current
  source, including real Trash/restore. A first restore assertion failed once;
  an identity-instrumented isolated run and two complete reruns passed. No
  cleanup implementation was changed; the initial cause remains unproven.
- Full-Xcode release packaging, code signatures, independently extracted ZIP,
  and complete app/archive content comparison passed. Installed app:
  `/Applications/louppe - to review.app`. Review ZIP:
  `dist/louppe - to review.zip`.
- Stable `/Applications/Louppe.app`: all 104 recorded file/symlink entries and
  the stable preference file remained identical to the pre-work baseline.
- All 13 copied media files remained byte-identical. Session saving and undo
  were checked through the UI and the disposable `.louppe_session.json`.

Computer-use checks in the installed app confirmed persisted Grid/hierarchy
starting defaults, natural folder order, reverse sibling order with parents
first, full-path Browser/Grid headings, Gallery/Grid switching, advancement
off/on, batch-independent undo, and advancement under the Undecided filter
without skipping the next item. Review defaults were restored after testing.
Gallery, Grid, and Settings were also inspected in screenshots.

The standalone drive fixture rendered the exact production drive view with
known and unavailable capacity states. Its native folder chooser opened at the
selected fixture drive. Automated confirmation in the native folder chooser
did not complete reliably, so media loading used the documented `-openFolder`
launch flag. This leaves native chooser confirmation for manual acceptance
with a physical card.

## Welcome-layout follow-up — 29 September 2026

- Recent folders and connected drives now use matching rows in aligned
  columns. The first five recent folders are shown; connected drives have no
  count cap. More drive columns appear as useful space is available.
- Removed the welcome ScrollView. Intrinsic content and warning banners set
  the native minimum, with native toolbar space included. Content growth
  expands the window; removing content lowers the minimum without shrinking
  it unexpectedly. Screen changes and display-configuration changes reflow
  columns and fit the window after measurement.
- Final focused run: 51 tests executed, 50 passed, one existing hosted SwiftUI
  accessibility skip, zero failures. Includes all 34 HotkeyTests, nine drive
  logic/race tests (including twelve distinct drives), and seven native window
  tests. Performance/file-safety script passed 75/75.
- A native fixture using the production welcome view and window bridge
  verified five recents with zero, one, seven, and thirteen connected drives.
  All rendered content fit at the native minimum, with no scroll view.
  Seven drives fit at 961 × 618 points; thirteen at 1257 × 618 on the larger
  display. Tests also covered reflow between the two attached displays.
- Installed the verified ZIP as `/Applications/louppe - to review.app`.
  Code signature verified, and all 104 stable app entries plus the stable
  preference file remained identical to the pre-update baseline.
- Computer use confirmed the installed app launches, renders the two aligned
  sections, has no accessibility scroll area, and shows the actual connected
  WORK_FAST_A drive with its reported capacity. Its welcome page was inspected
  in a screenshot. After clicking the drive, macOS screen capture returned
  error -3812, preventing further inspection of the native chooser or a manual
  resize gesture. Native minimum-size behavior passed the window tests and
  rendered fixture checks above.

## Acceptance

The actual external drive listing and capacity have been observed. Physical
insertion/removal and chooser confirmation remain manual acceptance checks;
eligibility, stale snapshots, and replacement identities have controlled tests.

## Minimal UI follow-up — 29 September 2026

The start page begins with Choose Media Folder, uses a 20-point top inset,
and stays top-aligned when enlarged. Its measured minimum still fits five
recent folders and every connected drive without scrolling.

Quality Cues has inline numeric fields and an independent checkbox for High
ISO, Slow shutter, and Clipping. The master switch remains available. Turning
a cue off retains its threshold. Valid values commit on Return or focus loss;
invalid input reverts to the last saved value, Escape discards the draft, and
Restore Defaults also discards a still-focused edit. Shutter values accept
fractions or decimal seconds; locale decimals are supported. Exact custom
thresholds appear in Info as well as Settings.

The final focused test run passed 58/58: 17 cue tests, all 34 HotkeyTests,
and seven native window tests. Performance/file-safety rerun passed 75/75.
The first performance run timed out waiting five seconds for a four-item
rescan; the unchanged binary passed on rerun. The original failure did not
retain enough state to identify its cause, and no timeout was weakened.

The alignment follow-up gives all three numeric controls the same 76-point
width and 24-point height, aligned on both edges. Units and explanations start
in a separate shared column. A native render of the production settings view
confirmed identical control frames and untruncated labels. The final focused
regression run again passed 58/58, including all 34 required keyboard tests.

## Review fixes and local consolidation — 29 September 2026

The review found one actionable layout issue: many connected drives or long
warning text could push the welcome window beyond the available display
height. Welcome content now uses native vertical scrolling only when it
exceeds usable screen height. The minimum and window frame account for the
title bar and toolbar; ordinary welcome layouts retain their intrinsic size.
The view's lifecycle remains stable when scrolling becomes necessary.

Verification passed:

- Focused run: all 34 HotkeyTests and 11 native window/layout tests (45/45).
  Coverage includes overflow, usable height changing at constant screen
  width, and scrolling the production welcome view with thirteen drives.
- Full XCTest run: 471 executed, one existing hosted-accessibility skip,
  zero failures. The hosted overflow test passed independently of that skip.
- Performance and file-safety checks: 75/75, including real Trash/restore.
  A legacy recovery fixture now standardizes its root path to match the
  historical v1 writer when running under `/private/tmp`; recovery validation
  itself is unchanged. Session-wait failures now include state diagnostics.
- The earlier four-item rescan timeout did not recur in 100 isolated repeats
  or the final full script. Its original cause remains unproven.
- Developer ID signing, loose app and extracted ZIP verification, and full
  app/archive content comparison passed for Louppe 1.9.1 (12).

The current source, including the review features, is installed as
`/Applications/Louppe.app` with the production bundle identifier. It opened
three disposable items and saved a three-entry session; the test originals
remained byte-identical. It was then closed normally, its merged preferences
restored, and reopened normally. The final check confirmed one running
production instance and preserved review/cue settings plus seven recent
folders. No user media was opened for this installation check.

Thirteen prior app bundles and both preference domains were archived under
`dist/local-backups/2026-09-29-consolidation`; every app file and symlink was
checked against its archive. Twelve redundant bundles were removed after
launch verification, including the separate installed review app. The old
`dist/Louppe.app` had already been replaced by the verified current build.
Only `Louppe.app` remains installed in `/Applications`, and `dist/` retains
one current app and release ZIP. Older output ZIPs are in the backup folder.

Screen capture failed with ScreenCaptureKit error -3811 during this final
installation check. Native layout tests and actual folder loading/saving
passed; final visual inspection and physical-drive insertion/removal remain
manual acceptance checks. No commit, push, or public release was performed.

## Promotion to 1.10 — 29 September 2026

At the owner's request, the existing unreleased update was promoted from
1.9.1 to 1.10.0. Build 12 remains the same release-cycle build; the latest
published release is still 1.9.0 (11). `VERSION` and the current changelog
heading now agree on 1.10.0 (12).

All 34 HotkeyTests and 75 performance/file-safety checks passed again before
installation. The Developer ID build, loose bundle, independently extracted
ZIP, and complete archive contents passed release verification. The signed
app replaced `/Applications/Louppe.app`, opened a disposable image, and saved
its one-entry session without changing the image. After restoring the fresh
pre-install preference snapshot, normal relaunch confirmed one running
1.10.0 app with settings and recent folders preserved. The previous 1.9.1
bundle is archived with a verified content manifest in the consolidation
backup folder. No source behavior changed, and no public release was made.


## Session wrap-up — 29 September 2026

Reviewed every remaining Louppe development chat: RAW representation, Fuji
research, selectable RAW 9, feedback copy, and settings explanations. Their
requested changes are complete in the shared source. Fuji metadata, broader RAW 9
hardware/resource/compression acceptance, and the intermittent disposable scan
fixture remain in `BACKLOG.md`; the existing audit acceptance tasks remain open.

Verification of the integrated source passed:

- Full XCTest: 537 tests, zero failures, three explicit skips (optional Fuji
  benchmark, optional real RAW fixture, and hosted-drive accessibility).
  All 35 mandatory HotkeyTests passed. A further real Fuji preview run removed
  the RAW-fixture skip: 10 focused tests, zero failures, one optional benchmark skip.
- Strict Swift 6 concurrency build with warnings as errors passed.
- Performance/file-safety checks: 75/75, including real Trash/restore. The first
  run raised `filesChangedDuringScan`; the unchanged binary passed on rerun.
  Diagnosis is recorded in the backlog; no identity checks/timeouts were weakened.
- Scrollbar checks: 10/10. Native media checks passed.
- Redacted credential checks passed. Two malformed duplicate Git references
  (`main 2`) were preserved outside `.git/refs`; normal fetch and Git integrity
  checks then succeeded. An empty duplicate vendor directory was removed.
- Developer ID packaging, loose/independently extracted ZIP signatures, and
  complete app/archive comparison passed for 1.10.0 (12).

All five running copies accepted normal Quit. The integrated build replaced
`/Applications/Louppe.app`, opened a disposable JPEG, and saved its session without
changing the JPEG. Native accessibility inspection confirmed the review window
and Saved status, then the ordinary welcome window after relaunch.

Thirty-five former bundles were archived and verified file-by-file (including
symlink targets and file modes). Thirty-four obsolete bundles were removed from
`dist/` and temporary launch locations; the previous installed bundle was replaced.
Older output ZIPs and preference snapshots are preserved under
`dist/local-backups/2026-09-29-wrap-up`. Launch Services entries for obsolete copies
were removed; the installed production app was registered. One production instance
runs from `/Applications`, and `dist/` retains its matching app and ZIP.

Reconciled cached and on-disk production preferences, preserving the latest
29-key snapshot and seven preexisting recent folders. Removed only this wrap-up's
smoke-test recent entry. Fixture-only decoder/feedback domains were not imported.
The final production signature and launch checks passed.

The website's twelve regressions passed; its consent fix was committed and pushed,
GitHub Pages deployment succeeded, and the live script matched source. Two-tab
browser acceptance remains in the website backlog. The app update remains
unreleased; no public 1.10 release or updater-feed promotion was performed.

The first remote quality run selected Xcode 26.6 and could not compile the
macOS 27 RAW-resource API. The quality workflow now uses GitHub’s `xcode-27`
runner, matching the local SDK requirement; application source is unchanged.
