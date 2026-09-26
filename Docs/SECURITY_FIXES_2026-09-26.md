# Security fixes — 26 September 2026

The updated local app is installed at `/Applications/Louppe.app`. It launched,
scanned a disposable PNG and wrote a valid `.louppe_session.json`. Changes remain
uncommitted on `main`; no GitHub release, update feed or website was published.
Version remains 1.9.0 (11), the existing unpublished release cycle.

## Changes

- Sparkle updated from 2.9.4 to 2.10.0, using the official archive's SHA-256 pin.
  The installed app's embedded framework reports 2.10.0.
- Expat updated from 2.5.0 to 2.8.5 in both vendored locations; copies match
  byte-for-byte. Source provenance, license and the required macOS randomness
  implementation were updated. Adobe's upstream revision is still current.
- XMPCore now limits nesting, allocated nodes, attributes, namespace declarations
  and decoded text before growing its tree. The reproduced deep-nesting input
  returns an ordinary error instead of crashing. Entity/DOCTYPE rejection and
  strict malformed-packet handling remain in place. UTF-8 and both UTF-16 byte
  orders are covered; no new UTF-32 compatibility claim is made.
- Copy captures the selected directory's identity before asynchronous preparation,
  including XMP and multi-destination flows. Actual media and generated-XMP writes
  use a held directory descriptor; final publication also stays within that
  descriptor. Replacing the directory or an ancestor path cannot redirect those
  writes. Exact Unicode path bytes and no-overwrite publication are preserved.
  Move gains a pre-start destination-identity check; its existing rename/recovery
  implementation otherwise remains unchanged.
- The obsolete Clean Up wording assertion was corrected, restoring a green test
  baseline without changing Trash behavior.

## Simple recovery choices

A folder replacement detected before work begins creates no pending recovery
record: choose the folder again and retry. If files already exist when a folder
changes, Louppe preserves the evidence instead of guessing. The existing
**Keep Files As They Are** action clears the pending record without touching
photos and permits a new operation. A new regression test proves that path.
Reviewing, rating, folder access, saving and Quit remain available while recovery
awaits a decision; existing recovery-gating tests cover this behavior.

An unusually complex XMP packet is skipped with an explanation; its original
bytes remain unchanged and media can still export without that XMP. There is no
unsafe-parser override or added recurring confirmation dialog.

## Local screenshot editor

The separate editor under the Louppe notes now resolves Next.js 15.5.26,
sharp 0.35.4, PostCSS 8.5.28 and React/React DOM 19.3.0. Compatible dependency
updates are recorded in `package-lock.json`; overrides eliminate the vulnerable
nested copies. The obsolete Bun lock was backed up outside the editor and
removed so it cannot reinstall the old dependency graph.

Startup is explicitly loopback-only. Project/upload routes check the browser's
Host and Origin, require JSON, and bound the request stream before buffering.
Uploads also check PNG/JPEG signatures. No login or password was introduced.
The saved screenshot project was not modified. The updated editor is running
at `http://127.0.0.1:3410`.

The installed tree (183 package instances) was compared locally against the
same 7,470 reviewed public npm advisories used for the audit: **zero remaining
version matches**. No dependency inventory was uploaded. This is a check of
known advisories, not a guarantee against unknown vulnerabilities.

## Verification

- Full app suite: **408/408 passed**.
- Final export/hotkey suite after the additional recovery regression and final
  error-path adjustment: **50/50 passed**, including all 34 HotkeyTests.
- Filesystem/performance checks, including disposable Trash/restore: **74/74**.
- Standalone XMPCore proof: all **five editing-app fixtures** passed; malformed
  XML was rejected. Existing XMP merge, publication, foreign-field preservation
  and recovery suites passed.
- Editor production build/type checks passed; **13 security/live-server
  scenarios** passed without changing the saved project.
- Local app and ZIP release preflight passed; installed deep/strict signing
  verification and real launch/sidecar check passed.

Packaging used current full Xcode and its macOS 27 SDK. The separately selected
Command Line Tools failed because their SwiftUI macro plugin was unavailable;
no older SDK workaround was used. The local app is an ad-hoc-signed development
build, not a newly notarized public release. A future public release still needs
Developer ID signing/notarization and a real previous-release update-path test.

Logs and the machine-readable summary are retained in the ignored
`.build/security-fixes-2026-09-26/` directory. Unrelated audit recommendations
(GitHub automation, repository protection and website headers) remain separate.
