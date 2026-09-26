# Louppe security audit — 26 September 2026

No exposed credentials were confirmed in the material examined. There are nevertheless security fixes to make, especially the outdated updater, XML parser hardening, and export destination binding. This is an audit result, not a claim that every possible vulnerability has been eliminated. Findings below describe the original audit, which did not change application code or GitHub settings. The subsequent authorized dependency, XMP and Copy fixes are recorded in [the remediation report](SECURITY_FIXES_2026-09-26.md); the public release remains unchanged until a new release is published.

## Scope and evidence

- App: public and local `main`, final audited commit `23b8551264ee384dd9720c2df19e8d7897728262`; current development version 1.9.0 (11).
- Website: public and local `main`, final audited commit `e7352700d29165ccc9ea8fb8f334ab41480ae9d0`; live HTTPS site inspected.
- Public history: 72 reachable app commits, 33 website commits, all ten release tags, and both app pull-request heads. Local histories and reflogs were scanned as well.
- All ten published release ZIPs, 60 downloaded workflow-log archives, four website deployment artifact copies collected across two snapshots, and available issue/PR discussion text.
- Local working files, ignored local configuration, installed app and local distribution files, plus the Louppe notes and screenshot-editor project.
- Automated scans covered the source corpus and historical blobs; manual review concentrated on trust boundaries: parsing, filesystem mutations, recovery, persistence, update verification, build/release scripts, browser code, and local API routes. This was not a line-by-line independent review of every vendored library implementation or a long-running fuzzing campaign.

Other work published documentation and marketing assets during the audit. GitHub snapshots were refreshed and rescanned; the app source under test did not change.

Redacted scan reports, test logs, repository settings and the machine-readable summary are retained locally in [.build/security-audit-2026-09-26](/Users/alexander_markin/Documents/code/louppe/app/.build/security-audit-2026-09-26/summary.json). That directory is ignored by Git. No private key was exported from Keychain and no credential was tested against its provider.

## Follow-up status — 27 September 2026

This document preserves the original audit findings. The app dependency,
parser-complexity, and destination-bound Copy fixes are implemented and tracked
in [the repair report](SECURITY_FIXES_2026-09-26.md). The formerly stale Trash
wording test now passes. The app quality workflow now pins checkout, avoids
persisted Git credentials, scans history and tracked edits with redacted
Gitleaks output, and receives weekly action update PRs. Signing/private-key
and local environment files are ignored. These changes do not claim that the
still-published 1.8.0 binary has been updated.

Repository protection remains an optional account setting; website findings
are outside the app-only completion review. The original evidence below is
historical, rather than a statement that those repaired app bugs remain open.

## Findings requiring action

### 1. High priority: the shipped updater has known security vulnerabilities

[Package.swift:17](/Users/alexander_markin/Documents/code/louppe/app/Package.swift:17) pins Sparkle **2.9.4**. The actual downloaded 1.8.0 app also contains 2.9.4.

Two upstream advisories cover this version and identify 2.9.6 as the fix:

- [GHSA-3x7w-j75x-ppq5](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-3x7w-j75x-ppq5): a local path-replacement race in privileged installation.
- [GHSA-4v99-qgq9-6pxp](https://github.com/sparkle-project/Sparkle/security/advisories/GHSA-4v99-qgq9-6pxp): unsafe cache cleanup when the updater is invoked as root.

These are conditional local privilege risks, not evidence that a remote attacker can forge Louppe updates. The second advisory's root-running CLI/daemon scenario was not established in ordinary Louppe use. Signed feeds and downloads remain valuable but do not repair vulnerable installer code.

**Action:** update the checksum-pinned Sparkle dependency to a maintained patched version, at least 2.9.6, and test a real update from the previous release. Upstream's latest release at the time of the check was 2.10.0. Publish a newly signed and notarized Louppe release after validation; editing the dependency locally does not protect existing installations.

### 2. Release priority: crafted XMP nesting crashes the production parser

[XMPBridge.mm:486](/Users/alexander_markin/Documents/code/louppe/app/Sources/XMPBridge/XMPBridge.mm:486) forwards packets into XMPCore. The parser's [element handler](/Users/alexander_markin/Documents/code/louppe/app/Sources/XMPBridge/Vendor/XMPToolkit/XMPCore/source/ExpatAdapter.cpp:313) grows its XML tree without a nesting limit. The 64 MiB packet limit does not constrain nesting or total tree complexity.

An isolated harness linked against the **freshly built production bridge objects** exercised `LouppeXMPMerge`. A synthetic 700,048-byte XML packet with 100,000 nested elements terminated with SIGSEGV. Smaller control inputs returned normally. The payload was below the existing byte limit and required no DTD or external entity. No real photo or running Louppe session was used.

**Impact:** a malicious sidecar processed through XMP publication/export can terminate the app. This establishes denial of service, not arbitrary code execution. The same process contains the app's session state, so an actor/background queue is not a crash-isolation boundary.

**Action:** enforce nesting, node-count and attribute/text budgets before growing the XML tree; return an ordinary malformed-packet error. Add regression cases for deeply nested UTF-8 and UTF-16 packets. Ensure all bridge entry points share the limits. Updating Expat alone must not be assumed to fix XMPCore tree-depth behavior.

### 3. Release priority: bundled Expat 2.5.0 predates substantial security fixes

The [vendor manifest](/Users/alexander_markin/Documents/code/louppe/app/Sources/XMPBridge/Vendor/README.md:8) pins Expat 2.5.0. This is compiled into the app rather than supplied by macOS, so OS updates do not update this copy.

[Upstream's current change history](https://github.com/libexpat/libexpat/blob/master/expat/Changes) documents many subsequent security fixes, including malformed UTF-16 handling in 2.8.5, released 22 September 2026. The existing configuration disables DTD support and bans DOCTYPE, which materially reduces exposure. Some advisories require features, APIs or architectures Louppe does not use; this audit does not label every Expat CVE exploitable in Louppe.

**Action:** update both vendored Expat header/source copies and the configuration/provenance records together, retaining the entity restrictions. Validate XMPCore compatibility, malformed encodings, resource limits and existing interoperability tests. Treat the separate reproduced nesting crash above as an independent acceptance criterion.

### 4. Medium: replacing a validated destination can redirect Copy writes

[ExportDestinationValidator.swift:79](/Users/alexander_markin/Documents/code/louppe/app/Sources/Louppe/ExportDestinationValidator.swift:79) resolves the selected path once. This protects against retargeting the original picker alias. It does not bind later operations to the identity of the resolved directory. Subsequent filesystem operations still use paths, including [DurableFileIO.swift:418](/Users/alexander_markin/Documents/code/louppe/app/Sources/Louppe/DurableFileIO.swift:418).

A disposable test validated a normal destination, renamed that directory away, and replaced its path with a symlink to another folder before invoking the worker. **Copy wrote the synthetic photo into the unapproved folder and then reported failure** (`copiedFiles=0`, `failedPhotos=1`). The original remained intact. In the equivalent Move test, the original remained and no photo reached the unapproved destination.

**Impact:** another process able to modify the destination's parent can redirect a write; a shared or synchronized destination makes this more relevant. The test did not establish overwrite or deletion of an original. Failure reporting after the write does not undo possible disclosure into an unintended folder.

**Action:** bind selected directories to opened descriptors/stable identities and use descriptor-relative operations through the mutation boundary. Add this replacement scenario beside the existing alias-retargeting test. Extra confirmation dialogs would not solve the race.

### 5. High priority maintenance, local tooling: screenshot-editor dependencies and API boundaries

The separate screenshot editor in the Louppe media library uses Next.js **15.5.14**, sharp **0.34.5**, and a nested PostCSS **8.4.31**. A local comparison of 184 installed package instances against 7,470 public reviewed npm advisories produced **30 affected-version matches across these three package names**. These are not 30 demonstrated exploits: several advisories overlap or require features and platforms the editor does not use. The [complete match results](/Users/alexander_markin/Documents/code/louppe/app/.build/security-audit-2026-09-26/editor-advisory-match-results.json) are retained locally.

The most consequential matches concern Next.js image optimization and sharp's image-decoding dependencies: [Next.js AVIF advisory](https://github.com/vercel/next.js/security/advisories/GHSA-2xp9-vwfh-vxw4), [sharp/libheif advisory](https://github.com/lovell/sharp/security/advisories/GHSA-rgj7-g3m4-5g8c). The sharp advisory describes possible code execution on glibc-based Linux under particular conditions; this audit did not establish code execution on this Mac. A separate Windows-only Next.js advisory is inapplicable here. RSC denial-of-service and nested PostCSS source-map issues also match installed versions; their specific exploit paths were not dynamically established. The patched top-level PostCSS does not remove its older nested copy.

The inspected process was listening on **127.0.0.1:3410**, not all network interfaces. That substantially limits exposure. However, its ordinary `dev`/`start` scripts do not enforce that binding, and the project-write/upload API routes have no origin/authentication checks. The project route reads the entire request before writing it to a fixed project file; the upload limit is checked only after parsing and decoding the body. No arbitrary-path write was established.

**Action:** update Next.js to at least the maintained 15.5.26 release, resolve sharp to at least 0.35.4 and the nested PostCSS to a patched version, then recheck the actual installed dependency tree. Make loopback binding explicit, check Origin/Host and accepted content types, and enforce request limits before buffering. These safeguards can remain invisible to normal editing. Keep this local tool separate from the public static website.

For accuracy, the different [September 22 Next.js Satori remote-code-execution advisory](https://nextjs.org/blog/nextjs-security-update-september-22-2026) explicitly excludes 15.x; it should not be conflated with the earlier image-optimization findings above.

### 6. Low-friction prevention gaps

Both GitHub repositories already have secret scanning and push protection enabled, with no returned secret alerts. Both use read-only default Actions permissions; only Alex was listed as a collaborator, and neither had repository deployment keys, webhooks or Actions secrets.

The gaps are:

- Dependabot alerts/security updates were disabled and no code-scanning analysis existed. Vendored C and a Swift binary dependency need an explicit inventory/advisory check; generic dependency tooling may not recognize them automatically.
- [The quality workflow](/Users/alexander_markin/Documents/code/louppe/app/.github/workflows/quality.yml:24) references a movable `actions/checkout@v6` tag and leaves credential persistence at its default. Pin the reviewed action commit and set `persist-credentials: false`; this job only needs to read source.
- The app and website `.gitignore` files do not protect typical `.env` files, exported private keys or signing archives. Add focused patterns plus a redacted credential scan in CI. Ignore rules supplement scanning; they do not remove historical leaks.
- Neither `main` branch had protection/rulesets. Blocking branch deletion and force-pushes is a useful option that can preserve direct pushes to `main`; mandatory PRs are unnecessary for this workflow.

### 7. Low: website defense in depth

HTTPS is enforced and HTTP redirects correctly. Requests to `/.env` and `/.git/config` returned 404. The site is static, with no account, payment, database or public upload backend in its code. Dynamic text uses safe text assignment; no user-controlled HTML execution sink was identified.

The inspected response lacked Content-Security-Policy, X-Content-Type-Options and an explicit Referrer-Policy. A carefully tested CSP/referrer policy would reduce future injection exposure. Some response-header controls require a hosting layer beyond ordinary GitHub Pages. This is hardening, not a demonstrated website compromise.

Google Analytics loads only after consent; eight behavioral assertions passed, including refusal, withdrawal, localhost exclusion and duplicate-load prevention. Google Fonts still receives requests before analytics consent; the notice discloses this. Self-hosting the font is an optional privacy improvement without adding a banner.

## Credential and release verification results

Gitleaks 8.30.1 was downloaded from its official release and checksum-verified. History, working-tree and archive scans used full redaction and recursive decoding. A supplementary scan checked private-key headers, embedded URL credentials and Apple app-password-shaped strings.

**No confirmed published secret was found.** Eleven binary-string matches were Apple's public `cdhashes`, not passwords. Four local screenshot-editor matches represented three generated Next.js build keys in ignored `.next` files; exact-value comparisons found no occurrence in the scanned public/project corpus. Those generated files should continue to stay out of source control and deployments of public static content.

The Sparkle verification public key, Apple team ID, code signatures, GA measurement ID and intended contact address are public identifiers, not leaked authentication credentials. This audit provides no evidence requiring their rotation.

All ten release ZIPs matched GitHub's recorded SHA-256 digests. For the actual public 1.8.0 archive:

- Deep/strict code-signature verification passed with Alex's configured Developer ID team and hardened runtime.
- Stapled notarization validation passed; Gatekeeper accepted it as Notarized Developer ID.
- The feed and archive Ed25519 signatures both verified using only the embedded **public** key.

Initial signing checks failed inside the restricted execution sandbox; rerunning with access to macOS signing services passed. That was an environment limitation, not a damaged public release. Older releases received checksum/content scans, not the same full notarization assessment as 1.8.0.

## Existing safeguards and test results

The reviewed design includes identity-bound file operations, no-overwrite renames, durable journals before mutation, recoverable partial operations, conservative collision handling, exact path bytes, bounded regular-file reads, entity rejection, per-folder save locking, visible persistence failures, and asynchronous save/quit barriers. Destructive actions retain their existing explicit UI boundaries. The standalone app uses Apple media APIs; no custom shell execution or photo-upload client was found in first-party app code. The direct-download build is not App Sandbox-contained; the separate Store build has narrowly scoped user-selected-file entitlements.

| Verification | Result |
|---|---|
| Full existing XCTest suite | 401/402 passed |
| Complete HotkeyTests | 34/34 passed |
| Deterministic performance/filesystem checks, including real disposable Trash/restore | 74/74 passed |
| Website consent assertions | 8/8 passed |
| Independent hostile XML probe | Reproduced crash; finding 2 |
| Independent destination replacement probe | Reproduced redirected Copy write; finding 4 |

The single XCTest failure is [CleanUpWorkerSafetyTests.swift:475](/Users/alexander_markin/Documents/code/louppe/app/Tests/LouppeTests/CleanUpWorkerSafetyTests.swift:475): it expects the former “Keep Only Yes again” wording, while the UI now uses “Trash No + Undecided.” The corresponding GitHub run fails at the same assertion. Repair the stale expectation so a red baseline does not hide future regressions. It is not evidence that Trash moved an unsafe file.

## Practical next steps

1. Patch Sparkle and Expat, add parser complexity limits, and close the reproduced destination-binding gap.
2. Update the local editor and make its loopback/origin/request-size safeguards automatic.
3. Add quiet credential and dependency checks; pin the checkout action and remove unnecessary persisted credentials.
4. Restore a green test baseline, build and launch the app on disposable media, then complete signing, notarization and update-path verification before a new release.

These fixes should not add passwords, repeated confirmations, or friction to ordinary reviewing/rating. They belong at parsing, filesystem and release boundaries.

## Limits

No audit can establish that a credential has never existed anywhere online. Deleted inaccessible GitHub refs, third-party caches, unrelated repositories, account-wide session security/2FA, encrypted material and private Keychain contents were outside this examination. Published screenshots were spot-checked; video frames were not exhaustively OCR-scanned. Existing tests and focused adversarial probes do not replace sustained fuzzing or independent penetration testing.

Automatic approval rejected uploading the complete installed dependency inventory to npm because it could include private package metadata. Nothing was sent. Instead, the public reviewed npm advisory catalog was downloaded and compared with the installed dependency tree entirely on this computer. This completed the known-advisory comparison without uploading the inventory; unpublished vulnerabilities and advisory-database omissions remain outside its coverage.
