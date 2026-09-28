# Development details

Required subsystem rules linked from [AGENTS.md](../AGENTS.md). Read the
sections relevant to the behavior being changed. Keep detailed rules here and
project-wide guardrails in `AGENTS.md`; update the owning section when behavior
changes.

## Architecture map

One `SessionStore` (a `@MainActor ObservableObject`) is the single source of
truth, created in `LouppeApp` and passed to every view.

| File | Responsibility |
|---|---|
| `Sources/Louppe/LouppeApp.swift` | `@main`, window scene, menu-bar commands |
| `Sources/Louppe/SessionStore.swift` | Main-actor session state: ratings/cached counts, undo, navigation, selection, prepared filtering + cached sort/day groups, file-operation orchestration, persistence snapshots, recents |
| `Sources/Louppe/PreparedSessionIndex.swift` | Pure item-ID/sort/filter/group/header/location maps projected by `SessionStore`; owns stable Grid group identity and performance signposts |
| `Sources/Louppe/SelectionState.swift` | Pure stable-ID/index selection authority: range, edge, toggle, rubber-band, filter intersection, and generation remapping; projected by `SessionStore` |
| `Sources/Louppe/SessionPersistence.swift` | Actor that binds an open folder to stable directory identity, serializes typed sidecar/identity-keyed-backup outcomes, cross-process lineage locking, raw-byte CAS, monotonic generations, schema validation, and durable atomic writes off-main |
| `Sources/Louppe/DurableFileIO.swift` | POSIX write/sync/rename/directory-sync boundary shared by sessions and file-operation journals |
| `Sources/Louppe/FileOperationJournal.swift` | Per-file durable Copy/Move/Rename/Organize/Trash/undo checkpoints, stable file identity, and launch recovery |
| `Sources/Louppe/CleanUpWorker.swift` | Background Trash/restore file loops, progress throttling, pair rollback, O(n+k) restoration merge |
| `Sources/Louppe/FolderScanner.swift` | Recursive scan, deterministic volume-aware RAW+JPEG pairing, lazy partner-JPEG metadata enrichment, in-memory pairing projection, chronological sort |
| `Sources/Louppe/ImagePipeline.swift` | ImageIO decoding + AVFoundation first-frame generation, thumbnail memory+disk caches, prefetching |
| `Sources/Louppe/HistogramPipeline.swift` | Bounded photo-only luminance analysis plus cached Fit/phone-size clipping-warning previews |
| `Sources/Louppe/CameraQualityWarnings.swift` | Pure app-wide warning preferences and non-blocking photo warning state |
| `Sources/Louppe/DuplicateBurstAnalysis.swift` | Local, bounded exact-duplicate, likely-similar-preview, and capture-burst analysis for review-only groups |
| `Sources/Louppe/HighResolutionImagePipeline.swift` | Lazy Core Image source-region rendering plus the bounded 100% tile cache |
| `Sources/Louppe/ZoomViewport.swift` | Pure backing-scale/normalized-position geometry and persistent non-published 100% viewport state |
| `Sources/Louppe/TextPreviewLoader.swift` | Bounded actor-based Unicode text loading and native Markdown parsing for the current document |
| `Sources/Louppe/Views/TextPreviewView.swift` | Read-only serif NSTextView with selection, scrolling, and web/email links |
| `Sources/Louppe/VideoSupport.swift` | Native movie metadata loading, duration formatting |
| `Sources/Louppe/VideoPlaybackController.swift` | One shared AVPlayer for Gallery/Grid playback |
| `Sources/Louppe/MetadataExtractor.swift` | EXIF reading for capture dates + info panel |
| `Sources/Louppe/ExportManager.swift` | Export dialog state machine: destination prompt, copy/move orchestration |
| `Sources/Louppe/ExportWorker.swift` | Background copy/move loops, pair-wide collision planning and rollback |
| `Sources/Louppe/ExportDestinationValidator.swift` | Export preflight: source-tree exclusion, destination permission and capacity |
| `Sources/Louppe/SourceOrganization.swift` | Pure source-folder hierarchy/rename, exact-path collision/XMP-family preflight, and preview planning |
| `Sources/Louppe/SourceOrganizationWorker.swift` | Journaled source-folder moves/renames, exact directory creation, and in-session undo restoration |
| `Sources/Louppe/FileRenaming.swift` | Pure filename recipes, fixed date/time rendering, sanitization, sequencing, and source-rename configuration |
| `Sources/Louppe/Models.swift` | Physical `PhotoFile` records, projected `PhotoItem` groups, ratings/filter models, sidecar codables |
| `Sources/Louppe/Views/RootView.swift` | Phase switch (welcome/scanning/session), `Color.appBackground` |
| `Sources/Louppe/Views/WelcomeView.swift` | Start screen + cancellable scanning progress |
| `Sources/Louppe/Views/SessionView.swift` | Toolbar (incl. sort menu), export sheet, shared trailing Info panel, **all single-key hotkeys** (`handleKey`) |
| `Sources/Louppe/Views/FilterView.swift` | Toolbar filter popover: metadata search, date range, subfolder / file-type / camera / lens toggles |
| `Sources/Louppe/Views/GalleryView.swift` | Gallery media layout: Browser / photo |
| `Sources/Louppe/Views/BrowserView.swift` | Optional vertical thumbnail Browser with day separators |
| `Sources/Louppe/Views/GridView.swift` | Grid view, day-grouped rows, click-to-rate, rubber-band selection |
| `Sources/Louppe/Views/MetadataPanel.swift` | Info panel (filename header, photo histogram, camera, exposure row, fields) |
| `Sources/Louppe/Views/HistogramView.swift` | Photo-only histogram, shadow/highlight percentages, and Gallery clipping toggle |
| `Sources/Louppe/Views/CameraQualityWarningsView.swift` | Text-first Info-panel review warnings and the focused Warnings settings page |
| `Sources/Louppe/Views/ThumbnailView.swift` | Async thumbnail tile + rating badge |
| `Sources/Louppe/Views/MediaTileAccessibility.swift` | Shared VoiceOver descriptions and open/rate/select actions for Browser/Grid tiles |
| `Sources/Louppe/Views/FullImageView.swift` | Large photo with fit / 100% / phone-size zoom |
| `Sources/Louppe/Views/ActualSizeImageView.swift` | Persistent AppKit scroll view that displays source-pixel tiles and carries pan position across photos |
| `Sources/Louppe/Views/VideoPlayerView.swift` | Native AVPlayerView bridge for Gallery/Grid playback |
| `Sources/Louppe/Views/ExportView.swift` | Export dialog (mode + rating tiles → progress → done) |
| `Sources/Louppe/Views/OrganizeSourceView.swift` | Source-folder scope, draggable folder levels, preview, confirmation, progress, and outcome sheet |
| `Sources/Louppe/Views/RenameFilesView.swift` | Single-family and metadata-batch source rename preview, confirmation, progress, and outcome sheet |
| `Tests/PerformanceChecks/main.swift` | Dependency-free search, ordered persistence, restoration-merge, and export copy/move regression checks |

See `Docs/PERFORMANCE.md` before changing concurrency, caching, filtering, or
Clean Up. It records ownership boundaries, cache budgets, and verification.

## File operations and recovery

- Copy, Move, Rename, Organize, Trash, and their supported undo paths must activate a
  `FileOperationJournal` before their first filesystem change. Recovery must
  verify stable file identity, never overwrite an existing path, never infer
  ownership from a filename alone, and keep unresolved journals retryable until
  the photographer explicitly chooses **Keep Files As They Are**. That escape
  may retire only a canonical Louppe journal by atomically setting it aside as
  `.forgotten`; it must never delete the record's contents, adopt an arbitrary
  `.operation` file, or touch media.
  Launch recovery for an intentional Trash action commits forward: it must
  never restore a photo the photographer deliberately sent to Trash. Only the
  explicit in-session Undo restores it. macOS owns Trash durability and may
  deny direct access to `.Trash`/`.Trashes`, so never make opening or syncing a
  protected Trash directory a requirement for operation success.
  A fully completed Export Move stays at its destination during recovery; only
  an incomplete RAW+JPEG item rolls back. A partially checkpointed paired Trash
  action remains nonblocking attention instead of silently discarding its
  evidence. Trash Undo must never move a successfully restored member back into
  protected Trash merely to make a pair look atomic—keep the restored original,
  rescan, and report the partial undo.
  New plan-v3 paths use exact raw filesystem bytes; never normalize them
  through Swift strings. Export validation and target construction must carry
  the exact selected destination bytes into the worker. Keep v1/v2 recovery
  compatibility. Copy's staged checkpoint means the duplicate was fully
  written, flushed, and source-verified: recovery must preserve staged and
  completed copies without requiring the source volume to remain mounted, and
  may publish an identity-verified staged temporary only with an exclusive
  rename to its exact planned destination. macOS can change a new copy's ctime
  when it attaches provenance metadata, so operation-created copy identity
  checks use volume/inode/birth/size/mtime but not ctime; exact source checks
  still include ctime. A thrown `copyItem` may leave a partial: checkpoint its
  exact identity before removing it, and never delete an unrecorded partial by
  pathname. A complete pre-staged temporary may be published only after the
  exact planned source is revalidated and every byte compares equal.
  Forward Move, Rename, Organize, and their in-session undo bind source,
  temporary, and target parents to opened directory descriptors per active
  file on the exclusive-POSIX path. The generated XMP sidecar in Move uses the
  same bound writes and publication. A changed parent must stop the operation
  without redirecting files; retain an ambiguous journal for attention when
  the change happens after a rename. ExFAT's existing Foundation fallback and
  launch recovery remain path-based with identity checks. Reproduce a concrete
  remaining risk before broadening those paths.
- **Clean Up has a three-phase boundary**: snapshot on `SessionStore`, file I/O
  in `CleanUpWorker`, apply on `SessionStore`. Do not put `trashItem`/`moveItem`
  loops back on the main actor. While `isCleaningUp`, keep item-index mutations
  blocked, folder switching disabled, and Quit refused so pair rollback and ⌘Z
  remain exact. Export follows the same boundary (`ExportWorker`). The shared
  `activeFileOperation` covers Clean Up, Copy, Move, Source Rename, and Source Organization;
  it blocks folder
  switching, rescan, undo, update checks/installation, and Quit until the
  worker completes or Copy cancels after rolling back its in-progress pair.
  That authority also retains the idle-system-sleep assertion; recovery owns
  it while reconciling. Keep display sleep enabled. Lid-close sleep cannot be
  blocked, so Copy must retain its bounded same-identity remount wait and may
  retry only when the operation temporary path is absent. Never retry over or
  delete an identity-ambiguous partial artifact. An identity-recorded partial
  may be removed through the journal's two reserved paths. Do not add a second
  independent in-flight flag. A recovery pass that is actively touching files
  remains mutually exclusive with new work. An unresolved journal awaiting
  attention blocks only new Copy, Move, Rename, Organize, Trash/Clean Up, and Trash
  undo actions;
  it must never block reviewing, rating, navigation, folder open/close/rescan,
  saving, updates, or Quit.

## Session persistence

- **Persistence failures are visible**: a folder sidecar save may fall back to
  the current Application Support snapshot, but failure of both destinations
  must keep the session open and show Retry Saving. Folder/session transitions
  and Quit await a safe result asynchronously. Never restore silent `try?`
  persistence or a main-thread semaphore.
- **Persistence is bound to one folder and one sidecar lineage**: capture
  `SourceFolderIdentity` before scanning, recheck it after scanning/read, carry
  the returned `AccessContext` through every save, and compare the exact raw
  sidecar revision immediately before replacement. Backups are keyed by stable
  directory identity and current snapshots use actor-assigned monotonic
  generations; never fall back to path or `scannedAt` as the current authority.
  One stable-folder advisory lock must span sidecar and backup revision checks,
  replacement/fallback, and lineage update; do not split that transaction.
  Lock acquisition must have a short finite deadline so a stale second process
  can produce a retryable save failure but can never freeze Close or Quit.
  If the exact opened folder path is absent because its volume disconnected,
  a save may advance only its stable-identity-keyed backup under that same lock,
  retaining the last proven sidecar revision and never recreating the missing
  path. Preserve exact `lstat` identities for every ancestor of the opened path
  so a different folder, symlink, non-directory ancestor, permission ambiguity,
  or replacement appearing there fails as `sourceFolderChanged` without
  touching either lineage. A UUID-owned source volume may receive a different
  `st_dev` on remount; allow that only after the complete folder is recaptured
  and its UUID/folder identity matches. If the final folder is absent or
  unreadable, retain strict device checks so a different mounted card cannot be
  classified as the missing original. If a sidecar rename
  may have committed immediately before disconnection, only that exact
  per-access marked revision may be adopted after reconnect; equality with an
  older backup alone must never bypass sidecar CAS. A backup rename followed
  by a sync error must likewise be adopted only when its exact desired bytes
  are observed, so Retry cannot conflict with Louppe's own commit. Quit must
  await an active checkpoint and compare the live monotonic change generation
  with the generation captured by successful sidecar/backup requests; a
  just-opened generation-zero session is a discard-safe baseline, so failure of
  its optional repair does not block Quit. Clean sessions start no new I/O,
  while a backup-only success is already safe to quit and remains manually
  retryable for sidecar repair.
  The obsolete path-keyed backup is read only when both current locations are
  absent. Schema 1–3 filename-only ratings migrate automatically only when
  every saved filename is present. A folder-owned legacy sidecar whose recorded
  path differs may proceed only after **Open Anyway** acknowledges that exact
  sidecar revision; it is rescanned and filename-checked before migration. An
  unowned legacy backup or missing legacy entries require explicit confirmation
  and must not autosave, close-save, or quit-save before it. Missing entries
  may be discarded
  only through **Open Folder and Forget Missing Items**; Close Folder and Quit
  must preserve both legacy copies byte-for-byte.

## Session state and selection

- **`visibleIndices` must never outlive `items`**: any place that replaces or
  empties `items` must reset/recompute `visibleIndices` in the same turn
  (see `openFolder`) — stale indices crashed the app on re-scan once.
  `visibleItems` bounds-checks as a backstop; keep it that way.
- **Derived session data is explicit**: rating counts update incrementally;
  filter facets and sorted indices rebuild after structural `items` changes.
  Any new code that inserts/removes/replaces photos must call
  `rebuildDerivedData()` before `applyFilter()`.
- **Pairing is a projection, ratings are per physical file**: a paired scan
  keeps the JPEG as a lightweight hidden `PhotoFile`. The first split enriches
  only missing JPEG metadata off-main; later toggles must reuse it without a
  folder rescan. Different RAW/JPEG ratings form a Mixed item (conservatively
  treated as undecided and protected from rating-based Clean Up) until rating
  the pair writes one decision to both files. Schema 2 introduced one entry
  per physical file; schema 4 binds each entry to scan-time file identity,
  schema 5 adds independent stars and color, and schema 6 records the exact
  pre-organization parent path so future hierarchy changes do not nest an old
  Louppe layout. Schema 1 combined entries remain readable.
- **Multi-selection model**: `selectedIndices` empty = "just the current
  photo" (`effectiveSelection` handles both cases). `SelectionState.itemIDs`
  is the stable authority; `selectedIndices` is its published
  current-generation UI projection. Structural changes must clear both through
  `setSelectionIndices`, or explicitly snapshot/remap stable IDs as same-folder
  rescan does. `applyFilter` removes hidden IDs from both. The Grid-view rubber
  band hit-tests tile frames collected via a `PreferenceKey`, so only
  *rendered* (on-screen) lazy-grid tiles can be caught by the rectangle —
  fine in practice, but don't "fix" it by de-lazifying the grid.

## Media rendering and caches

- Text documents have their own `MediaKind.text`, remain standalone during
  RAW+JPEG pairing, and use ordinary per-file review metadata and operations.
  The explicit extension list excludes XMP and hidden session sidecars.
  `TextPreviewLoader` reads/parses only the current document on one actor,
  bounds reads to 1 MiB, checks scan identity before/after reading, and rejects
  non-regular files, invalid Unicode and stale results. Native Markdown
  semantics become serif text, with web/email links; XML is literal text.
  The reader's lifetime follows `contentRevision`; ordinary rating updates
  preserve text selection and scrolling. Text never enters image decoding.

- **ImageIO embedded thumbnails**: many JPEGs embed a tiny (~160px) preview.
  `ImagePipeline.decodeImage` asks for the fast embedded path first and falls back
  to a full decode when the result is undersized — removing that fallback
  brings back blurry/pixelated previews.
- **Presentation ID is not content identity**: same-folder rescans deliberately
  preserve `PhotoItem.id`, and replacements can preserve filenames and mtimes.
  Media caches and asynchronous thumbnail/full/metadata/histogram/100%-tile/
  video state must follow `PhotoItem.contentRevision`. The v5 disk cache binds
  pixels to scan-time physical identity. Identity-bound production items never
  trust v4/v3 cache bytes; compatibility is limited to items without scanned
  identity and still requires the cache timestamp to postdate the captured
  source timestamp.
- **100% view identity is persistent**: `GalleryView` must not add
  `.id(item.id)` back to `FullImageView`. The AppKit actual-size viewport stays
  alive across current-item changes so its normalized inspection position can
  be restored. `FullImageView.loadedItemID` prevents stale preview state from
  appearing while that persistent view changes files.
- **100% rendering stays tiled**: one source pixel maps to one backing-store
  pixel. Keep high-resolution work on the two-operation tile queue, retain
  only the visible tile ring, and preserve the 128 MiB decoded-tile ceiling.
  Never replace it with a whole-file 45–100 MP bitmap.

## Native UI

- Toolbar Liquid Glass groups follow the owner's arrangement in
  `SessionView.toolbarContent` and use Apple's native fixed `ToolbarSpacer`.
  macOS 26 may show little or no extra separation in the `.navigation`
  placement and wider trailing gaps; the owner explicitly prefers that native
  result to custom equal-width spacing. Do not add custom spacer views.

- **Browser rows must observe the store directly**: `BrowserRow` holds its own
  `@ObservedObject` because a macOS `LazyVStack` does not reliably re-resolve
  already-created rows on data changes — as a plain value subtree the rows
  froze their badges and current-photo frame until the view was recreated.
  Keep the row's `.id(item.id)` too (follow-scroll target + state reset when
  Clean Up remaps indices). Details in `Docs/PERFORMANCE.md`.
- **Grid control drags are not selection drags**: rubber-band hit testing uses
  the existing tile frames and fixed Rating/Play control regions. Do not add a
  `GeometryReader` per control, and do not reject native multi-click Button
  activations—every activation must cycle the rating exactly once.
- **Grid photo selection must be immediate**: `GridImmediateClickSurface`
  commits the first mouse-up synchronously and treats only the second click as
  double-click-to-open. Do not replace it with exclusive single/double SwiftUI
  tap gestures; they delay selection for the system double-click interval.
- **Grid scrolling keeps AppKit's native scroller**:
  `PersistentVerticalScroller` may make the native legacy scroller permanently
  visible and reserve its gutter, but must not replace it with a hand-drawn
  subclass. Resolve an already-mounted scroll view synchronously and coalesce
  the initial deferred lookup so fast lazy-grid updates cannot queue main-actor
  work ahead of the scrolling indicator.
- `RootView` owns the persistent window's phase-aware content layout through
  `WindowContentLayout`: Welcome/Scanning use a compact launch size and
  `.fullSizeContentView`, while Ready restores the session minimum and removes
  full-size content so photos cannot scroll behind the liquid-glass toolbar.
  These settings do not choose the window radius. Welcome and Scanning include
  a real unified toolbar (`LaunchToolbarTitle`) so macOS 26 supplies its larger
  native toolbar-window corners; never fake them with a custom window mask.
- `WelcomeView` owns one folder drop target across its entire content area;
  the dashed chooser remains only the visual prompt. Keep dropped-item
  validation and errors shared for every point in the window.
- Thumbnails letterbox (`fit`) inside square tiles on purpose — fill-mode
  cropping both hid parts of the photo and let portrait images overflow
  their tiles.
