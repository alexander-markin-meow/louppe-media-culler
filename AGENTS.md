# Louppe Media Culler — guidance for AI assistants

Native macOS photo-culling app. Swift/SwiftUI, plain SwiftPM executable —
**no Xcode project**. Use the installed full Xcode explicitly for builds,
tests, and packaging: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
Verified on 2026-09-27 with Xcode 27.0 and the macOS 27.0 SDK. The separately
selected Command Line Tools lack XCTest and their SwiftUI macro plugin failed;
do not use an older SDK to work around that installation.

The owner is a photographer, not a programmer: do the technical work for him,
explain results in plain language, and always verify the app actually launches
after changes.

There is no separate support team. The sole contact is Alex Markin at
`a@alex-markin.com`; use “Contact Alex” rather than “Contact support” in the UI.

## Engineering approach

- Reuse nearby implementations and existing state owners. Keep changes scoped;
  add abstractions only for concrete needs. Prefer native SwiftUI/AppKit controls
  and Apple APIs; preserve the documented bridges that solve native limitations.
- Use Swift enums for exclusive states and existing typed identities/plans
  across boundaries. Keep domain decisions pure, UI state in its owner, and I/O
  in workers or actors. Alternate command entry points share domain logic.
  Prefer labeled arguments; group related values when they must travel together.
- Give immediate native feedback while work runs. Report durable success only
  after worker confirmation; partial results must match the actual files.
- Diagnose from a reproduction and relevant errors, sidecars, journals, or
  measurements. Extend existing `Logger` / `OSSignposter` patterns as needed;
  keep personal paths/metadata private. Give actionable errors and preserve
  intentional backup/preview fallbacks without disguising failures as defaults.
- Test meaningful contracts: disposable folders and real I/O for file operations,
  targeted fault injection for failures, focused logic tests for edge cases,
  and affected flows in the app. Follow the mandatory checks below.
- Verify uncertain APIs against the selected SDK, pinned sources, and matching
  official documentation. Keep instructions in one place, update affected docs,
  and report what changed, what was verified, and any verification gap.

Sources and adaptation decisions: [engineering review](Docs/ENGINEERING_RULES_REVIEW.md).

## Read when relevant

Read the matching sections **before changing the affected behavior**; consult
all matching sections for changes spanning several areas. These are required
project rules, moved out of this file for readability. Documentation-only edits
need only their relevant references.

| Work area | Reference |
| --- | --- |
| Finding ownership or changing module boundaries | [Architecture map](Docs/DEVELOPMENT_DETAILS.md#architecture-map) |
| Copy, Move, Rename, Organize, Trash, undo, recovery, operation gates or sleep | [File operations](Docs/DEVELOPMENT_DETAILS.md#file-operations-and-recovery) |
| Save/load, sidecars, backups, migration, folder transitions or Quit | [Persistence](Docs/DEVELOPMENT_DETAILS.md#session-persistence) |
| Scanning, pairing, ratings, filtering, item replacement or selection | [Session state](Docs/DEVELOPMENT_DETAILS.md#session-state-and-selection) |
| Previews, thumbnails, media caches, zoom or asynchronous media loading | [Media](Docs/DEVELOPMENT_DETAILS.md#media-rendering-and-caches) |
| Browser/Grid interactions, scrolling, toolbar or window layout | [Native UI](Docs/DEVELOPMENT_DETAILS.md#native-ui) |

Also read [Docs/PERFORMANCE.md](Docs/PERFORMANCE.md) before changing concurrency,
caching, scanning, filtering, image decoding, persistence, or Clean Up.

## Architecture essentials

One `SessionStore` (`@MainActor ObservableObject`), created in `LouppeApp`, owns
session state and is passed to every view. Slow I/O stays off the main actor.

- Keep `visibleIndices` valid whenever `items` changes; rebuild derived data
  before filtering after structural changes.
- `SelectionState.itemIDs` owns selection; `selectedIndices` is its projection.
  Empty selection means the current photo, not no photo.
- Ratings belong to physical files; pairing is a projection. Preserve Mixed
  decisions and legacy session compatibility.
- Asynchronous media and caches follow `PhotoItem.contentRevision`, not just
  presentation ID. Keep 100% rendering tiled within its 128 MiB limit.

## Invariants — do not change

- **Bundle identifier** `com.alexandermarkin.louppe` and **sidecar filename**
  `.louppe_session.json`. (Renamed from the original "loupe" spellings on
  2026-07-12 with the owner's consent — old sessions and folder permissions
  were intentionally abandoned. Don't rename again without asking: it resets
  saved ratings and macOS folder permissions.)
- **Originals are never modified or deleted, and never move without an
  explicit, confirmed command.** Export's default mode only copies. Four
  sanctioned exceptions, all owner-requested: (1) Clean Up in `SessionStore`
  (2026-07-13) moves rejected files to the macOS Trash via
  `FileManager.trashItem` — never a permanent delete — behind a confirmation
  dialog, with ⌘Z restoring the whole batch; no *single-key* hotkey for it
  (⌘⌫ trashing the selection without a dialog is the one sanctioned
  shortcut — Finder parallel, ⌘Z restores). (2) The Export dialog's
  **Move to…** mode (2026-07-21) transfers the chosen ratings' files to a
  user-selected folder after an explicit mode choice and an in-dialog
  warning; moved photos leave the session, the move is not undoable, and the
  files stay intact at the destination. (3) **Organize Source Folder…**
  (2026-08-17) moves a confirmed All/Filtered/Selected scope inside the opened
  source folder according to its previewed metadata hierarchy; it retains old
  folders, never overwrites or renames a collision, and ⌘Z restores file
  locations during the open session. (4) **Rename Files…** and the Info-panel
  pencil (2026-09-04) rename original filename stems inside their current
  folders after an exact preview or explicit single-name submission. Extensions
  and contents never change; RAW+JPEG and recognized XMP names follow as one
  journaled family, collisions and `.acr` companions block the plan, and ⌘Z
  restores the prior names during the open session. No other code path may move originals;
  nothing ever hard-deletes.
- Activate `FileOperationJournal` before the first filesystem change in
  Copy/Move/Rename/Organize/Trash and supported undo. Verify exact paths and
  stable identity; never overwrite or infer ownership from a filename. Read
  the file-operation reference before changing recovery or retry behavior.
- Persistence must preserve folder identity, sidecar lineage, durable writes,
  and visible failure/retry behavior. Folder transitions and Quit await a safe
  save asynchronously; never hide failures or block the main thread.
- Keep the shared `activeFileOperation` authority. Active file work blocks
  conflicting operations and Quit. Unresolved recovery awaiting attention
  blocks new file mutations, not reviewing, saving, folder access, updates, or
  Quit. See the reference for exact operation and recovery boundaries.
- The hotkey map lives in `SessionView.handleKey` and is documented in
  README's shortcut table — keep the two in sync when changing keys.
- `SessionView`'s local monitor is the sole owner of session Command shortcuts;
  do not add duplicate menu `.keyboardShortcut` equivalents that bypass its
  window/focus gates. Review letters remain active after ordinary controls,
  but keyboard-focused controls keep Space, Tab, Escape, and arrows; editing or
  selecting text and modal UI keep every key. Preserve VoiceOver, Fn/Globe,
  Help, and unsupported modifier chords. Its monitor token belongs to the
  AppKit bridge attached to the live session window; do not move it back into
  SwiftUI `@State` with independent `onAppear`/`onDisappear` callbacks.
- One background gray everywhere: `Color.appBackground`. Don't introduce
  other panel shades; use `Divider()` lines to separate regions.
- One accent color everywhere: `Color.louppeAccent`, the brand purple
  #9853A6 (defined in RootView.swift, applied as a global `.tint` and used
  for the app-icon glyph). Green/red stay reserved for yes/no ratings; don't
  use blue or `Color.accentColor` for anything.

## Build & install

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./build_app.sh                        # release build → dist/Louppe.app
cp -R dist/Louppe.app /Applications/    # install (remove old copy first)
xattr -cr /Applications/Louppe.app      # copy can attach Finder metadata
codesign --verify --deep --strict /Applications/Louppe.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build --disable-keychain        # quick debug check; no dependency login
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --disable-keychain         # XCTest is supplied by full Xcode
```

`build_app.sh` bundles the binary + icon + Info.plist in `/private/tmp`, strips
extended attributes, ad-hoc signs, verifies there, then copies the result to
`dist/`, where `Scripts/verify_release.sh` verifies the exact app and archive.
Staging outside the File Provider-managed workspace is required:
Finder metadata may otherwise reappear between signing and verification. Still
run `xattr -cr` after copying into `/Applications`.

`VERSION` is the source of truth for the About-panel marketing version and
build number. **Bump the version/build pair exactly once per GitHub release
cycle**: the first change after the latest published GitHub release bumps
`VERSION` and opens one new `CHANGELOG.md` entry, and every further change
folds into that same entry (update its bullets and date — do not bump again)
until that version ships as the next GitHub release. Check the latest release
(`gh release list`) before deciding whether a bump is due; local installs of
work-in-progress builds are not releases and never justify a bump.
`build_app.sh` deliberately refuses to package a pair missing from the
history. History headings use
`## <MARKETING_VERSION> (<BUILD_NUMBER>) — <DATE>`. Keep release tags in the
form `v<MARKETING_VERSION>`.

Always build against the current macOS SDK. Do not work around toolchain errors
with an older SDK: doing so compiles out current SwiftUI features such as macOS
26 liquid-glass toolbar styling.

## Testing a build

Run the focused logic tests first, then verify by launching with a folder:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --disable-keychain --filter HotkeyTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  ./Tests/run_performance_checks.sh
```

The complete `HotkeyTests` run is mandatory before **every** local app install,
even when the change seems unrelated to keyboard handling. It exercises the
installed-monitor path with real AppKit window events, including detaching and
reattaching the session view; direct `handleKey` unit tests alone are not an
adequate regression check.

The last two checks use disposable files for a real Trash/restore round trip.
In a restricted agent sandbox, rerun the script with permission to access the
macOS Trash if those checks report that the paired photo could not move.

```sh
open /Applications/Louppe.app --args -openFolder /path/to/photos
```

**Never pass a bare path argument** (`--args /path`): macOS treats it as a
document-open request, and because the app declares no document types the
system suppresses the app's default window — the app runs headless and
appears broken. The `-openFolder` flag form avoids this entirely.

The app writes `.louppe_session.json` into the opened folder within a few
seconds; inspect it from the CLI to confirm scanning/pairing/rating logic
without seeing the screen. Screen capture is NOT available for verification
(no Screen Recording permission) — ask the user to look, or check the sidecar.

- If the app ever launches with no window visible, suspect corrupted window
  restoration state: `defaults delete com.alexandermarkin.louppe` and
  `rm -rf ~/Library/Saved\ Application\ State/com.alexandermarkin.louppe.savedState`.
- Release verification must validate the loose and archived app independently
  and compare their complete `Contents/` trees; checking only the executable
  and Info.plist can miss a stale or altered embedded framework/resource.

## Repo conventions

- GitHub: `alexander-markin-meow/louppe-media-culler` (public). Commit/push only when the
  owner asks; he reviews PRs via the GitHub UI "Merge" button or asks here.
- **Use `main` only.** Do not create or retain local or remote feature branches
  unless the owner explicitly asks for one. Commit directly to `main` only when
  asked; after any exceptional branch is merged, delete it both locally and on
  GitHub.
- `dist/` and `.build/` are gitignored build products; `AppIcon/` holds the
  source glyph and the built `.icns` (both tracked).

## Louppe project location

Shared project layout and materials are documented in `../AGENTS.md` and `../README.md`. Use `/Users/alexander_markin/Documents/code/louppe/` for application work; personal notes and CAS logs stay in Obsidian.
