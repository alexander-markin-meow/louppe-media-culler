# Louppe media and native UI audit — 2026-09-29

Canonical source: `/Users/alexander_markin/Documents/code/louppe/app`. Read-only audit of the current working tree, including existing uncommitted changes. No application source, tracked tests, Git state, originals, user preferences, installation, or releases were changed by this audit worker. All additional artifacts are under `/private/tmp/louppe-audit-2026-09-29/media-repro/`.

Read `app/AGENTS.md`, shared `../AGENTS.md`, the Media and Native UI references in `Docs/DEVELOPMENT_DETAILS.md`, and the relevant ownership/resource/caching/concurrency rules in `Docs/PERFORMANCE.md`.

## Findings

Five concrete issues: four reproduced through executable production logic and one established by the SwiftUI visibility condition. All are P2 (normal-priority corrections); no destructive-file-operation defect was identified within this worker's media/UI scope.

| ID | Finding | Evidence |
| --- | --- | --- |
| M1 | Post-scan file replacement can seed old-identity caches with replacement pixels | Executed actual ImagePipeline + HistogramPipeline with actual Models/Journal |
| M2 | Clipping analysis/overlay mishandles partially transparent pixels | Executed actual ClippingWarningProcessor on a valid premultiplied RGBA pixel |
| M3 | Cancelled whole-clip audio analysis monopolizes the single queue until EOF | Executed actual AudioLevelPipeline with a one-hour sparse WAV, then a one-second WAV |
| U1 | Opening/closing Filter can silently round an existing precise numeric cutoff | Executed exact FilterView draft sync/commit/format/parse/snap methods with an isolated store stub |
| U2 | Gallery video controls disappear during keyboard/accessibility playback | Direct SwiftUI control-visibility trace; native VoiceOver interaction not executed |

### M1 — P2: Validate source identity at actual read/cache-publication boundaries

**Primary locations:** `Sources/Louppe/ImagePipeline.swift:317–330` and `335–339`; related `Sources/Louppe/HistogramPipeline.swift:301–325`.

**Trigger:** Scan a photo, retain the resulting `PhotoItem`, and replace the source at the same pathname before its first thumbnail/full/histogram decode. Navigation keeps using the scan snapshot until a rescan.

**Observed behavior:** The v5 key correctly includes the scanned physical identity, but the decode accepts the current URL without comparing the current file to that identity. It then publishes replacement pixels under the old scanned identity. The thumbnail is also persisted under that old identity's disk key. A before/after scan revision task guard cannot detect this because the caller's `PhotoItem` itself has not changed.

**Executable evidence** (`media-repro/main.swift`, actual production source files; `media-repro/result-unsandboxed.txt`):

```
LIVE_IDENTITY_DIFFERS=true
OLD_REVISION_THUMB_PIXEL=[255, 255, 255, 255]
OLD_REVISION_FULL_PIXEL=[255, 255, 255, 255]
OLD_REVISION_HIST_HIGHLIGHTS=1, SHADOWS=0
OLD_REVISION_CACHED_AFTER_BLACK_REWRITE=[255, 255, 255, 255]
```

The scanned photo was a black PNG. A separate white PNG replaced it via remove/move, so the inode differed. The retained black item's thumbnail, full preview, and histogram all used white replacement pixels. Rewriting the pathname black afterward still returned the contaminated white thumbnail from the old item's cache. The identity mismatch was checked using `FileOperationJournal.captureIdentity`, and the item used actual production `PhotoItem` identity capture rather than a fake cache key.

**Consequence:** Louppe can display a different file's pixels beside the original scan metadata and identity. Reviewers can make a decision while seeing unrelated replacement content. The physical-identity guards in file operations remain a separate safeguard; this finding does not claim that a replacement is deleted or overwritten.

**Related source traces:** `HighResolutionImagePipeline.swift:135–158,275–303` creates a lazy source from `item.primaryURL` without live identity comparison. `AudioLevelPipeline.swift:270–301,337–346`, `VideoPlaybackController.swift:169–172`, and `MetadataExtractor.swift:76–83` likewise read source URLs without revalidating scan identity. These additional lanes were not independently subjected to replacement reproduction; they are instances of the same missing source-read boundary rather than five additional confirmed pixel-cache defects. `TextPreviewLoader` already performs before/open/after identity checks and is a useful nearby model.

**Minimal correction:** Keep body-time cache lookups independent of filesystem I/O. At actual uncached source I/O, pass the scanned identity alongside the URL, verify it before/after the read, and refuse to cache/publish a mismatching source. For lazy Core Image sources, ensure the verified source owns the bytes/file handle it will actually render, or revalidate at tile render before returning a tile; checking only when constructing a URL-based recipe is insufficient if a later render rereads the path. Surface an actionable changed-file/rescan outcome instead of relabeling new pixels as old content. Tests should replace a file *after* item construction, including a same-path/same-mtime replacement and replacement during a delayed read. Existing cache tests mainly prove different keys after reconstructing/rescanning the item and do not exercise this boundary.

### M2 — P2: Preserve the premultiplied-alpha contract in clipping work

**Locations:** `Sources/Louppe/HistogramPipeline.swift:105–112,139–150,171–184,204–212`.

**Trigger:** Preview a PNG/TIFF with partially transparent pixels and inspect its histogram or enable the clipping overlay.

**Root cause:** The processing bitmap is declared `premultipliedLast`, but analysis thresholds raw RGB bytes as if they were straight, fully opaque color. The overlay blends with full-intensity red without multiplying the warning by the retained alpha. It also transforms alpha-zero pixels instead of skipping them, creating invalid RGB values in nominally fully transparent output.

**Executable evidence:** A valid one-pixel image containing straight white at alpha 3/255 has premultiplied bytes `[3,3,3,3]`. Actual production processor output:

```
TRANSLUCENT_WHITE_HIST_SHADOW=1, HIGHLIGHT=0, BIN3=1
TRANSLUCENT_WHITE_OVERLAY_PREMULTIPLIED_PIXEL=[184, 1, 1, 3]
```

The histogram reports translucent white as a black/shadow pixel. The overlay output's red 184 exceeds alpha 3 in a bitmap explicitly labeled premultiplied, so it violates that format's invariant and can produce bright colored halos on translucent/transparent edges. Normal opaque-photo tests pass because alpha is always 255; the existing transparent test covers only fully transparent histogram exclusion.

**Minimal correction:** Define whether clipping measures straight source RGB or the visible composited color, and implement it consistently. For straight source RGB, ignore alpha zero, unpremultiply nonzero-alpha RGB before calculating luminance, then blend in straight color and re-premultiply the result by the original alpha. If clipping is intended to represent composited appearance, composite onto the actual backdrop first; still never write RGB greater than alpha into a premultiplied output. Add alpha 0, 3, 128, 255 tests for white, black, and midtone colors, ensuring overlays preserve valid alpha representation.

### M3 — P2: Cancel abandoned running audio readers at a safe boundary

**Locations:** `Sources/Louppe/AudioLevelPipeline.swift:244–247` (one-operation queue), `317–334` (bridge cancellation), `468–487` (final-waiter policy).

**Trigger:** Open a long recording, leave it after its waveform/meter reader has started, then select another recording. Canceling the Gallery/Info tasks removes their waiters but does not cancel an executing reader.

**Observed behavior:** `cancelWaiter` cancels only when `!pending.operation.isExecuting`. A running operation with zero waiters continues through the entire source and is retained for cache warming. Its `isCancelled` closure never becomes true, so the decoder's cancellation checks do not stop it. Every subsequent recording shares the single queue and waits for this abandoned decode.

**Executable evidence:** Release-optimized standalone harness linking actual production `AudioLevelPipeline` and actual `PhotoItem`. A one-hour stereo 48 kHz silent WAV was a sparse disposable file (691,200,044 logical bytes); cancel occurred 100 ms after starting its analysis. A fresh one-second WAV requested immediately afterward:

```
AUDIO_CANCEL_RETURNED_NIL=true AFTER=2.5987625122070312e-05s
NEXT_ONE_SECOND_AUDIO_ANALYSIS=true WAIT=4.01311194896698s TOTAL=4.119922995567322s
ABANDONED_LONG_ANALYSIS_CACHE_HIT=3.898143768310547e-05s
```

Cancellation returned promptly to its caller, while the whole hour still decoded and entered the cache. The selected one-second clip waited approximately four seconds. Real compressed/high-channel-count/slow-storage recordings can increase this delay; those additional formats were not timed and no extrapolated delay is asserted.

The initial sandboxed execution could not read WAVs through native AVFoundation services and returned nil. It is preserved in `result.txt` as an environment limitation. The successful timing reproduction is `result-unsandboxed.txt`, run with explicitly escalated native-media-service access. No production user files or preferences were touched.

**Minimal correction:** When the final waiter disappears, request cancellation of an executing decode as well. Keep the queue slot occupied until the detached AVAssetReader task has actually reached its cancellation boundary and signaled completion; simply adding `operation.cancel()` to the current bridge is not enough because the bridge currently returns immediately after `task.cancel()`, which could let the next queue operation overlap a still-terminating reader. Keep same-content coalescing valid when a new waiter arrives during shutdown, and use operation identity/generation when reconciling completion. Add a deterministic slow-reader test proving no overlapping readers and proving B can start soon after A's cancellation without reading A to EOF.

### U1 — P2: Preserve exact numeric filter values unless a user edits them

**Locations:** `Sources/Louppe/Views/FilterView.swift:131–140,936–945,968–999,1016–1027,1152–1184`.

**Trigger:** Apply a precise interior numeric range, reopen Filter, then close it without editing. For example, folder durations span 5…30 seconds and the active cutoff is 10.2…20.8 seconds.

**Observed behavior:** On appearance, draft strings are generated through display formatters (whole seconds for duration, two decimals for aperture, three decimals for frame rate, rounded decimal/reciprocal shutter presentation). On disappearance, every numeric draft is committed regardless of whether its text was edited. Snap logic protects only the folder-wide minimum/maximum, not an existing interior cutoff. The formatted strings therefore become new authoritative numeric values on a no-edit close. Committing a different field also commits every other numeric draft.

**Executable evidence:** `media-repro/filter.swift` contains exact extracted FilterView range/commit/parse/format/snap methods, executed unchanged against a minimal store stub and production `PhotoFilter`/formatters. This reproduces the pure operations invoked by appearance/disappearance; it is not a hosted popover interaction test.

```
BEFORE_POPUP: 10.2...20.8
SYNCED_DRAFTS: 0:10...0:21
AFTER_NO_EDIT_CLOSE: 10.0...21.0
```

**Consequence:** Merely inspecting Filter can change visible media, widening or narrowing a cutoff. The same concern applies to non-extreme aperture/shutter/fps cutoffs. Neutral full-folder edges already have protection and should retain it.

**Minimal correction:** Track which draft pair the user edited, or retain each original exact numeric value and display string so an unchanged display round trip retains the original value. Only commit modified fields; do not interpret initializing or reformatting drafts as user edits. Add a hosted open/close regression and exact-value tests for each numeric filter, including changing one range while preserving all the others.

### U2 — P2: Keep playback controls reachable when focus is keyboard/accessibility-owned

**Locations:** `Sources/Louppe/Views/VideoPlayerView.swift:37–73,76–79,94–95`; Play/Pause is in `214–220`.

**Trigger:** Start a Gallery video with keyboard or VoiceOver, with the pointer outside the movie pane, or move the pointer out while a playback control retains focus.

**Source-proven behavior:** All transport, timeline, volume, PiP, and fullscreen controls are conditional children of `if showsControls`. That condition is only `isHovering || !playback.isPlaying || isScrubbing`. Once the video is playing without hover or scrub, the entire subtree is removed, regardless of keyboard focus, VoiceOver state, or accessibility focus. The fitted `AVPlayerLayer` surface contributes no native transport alternative.

**Consequence:** The focused Play button can disappear on activation and playback controls become unavailable in the accessibility hierarchy. Review-letter K may remain a play/pause fallback where the session monitor accepts it, but there is no accessible timeline/volume/PiP control while the subtree is absent. A manual native VoiceOver run was not executed, so focus relocation behavior is unverified; subtree removal itself follows directly from the code.

**Minimal correction:** Keep controls visible while keyboard or accessibility focus is within them, and while VoiceOver requires a transport surface. Alternatively keep a stable accessible transport surface while fading pointer-only decoration. Avoid removing the active focused element. Verify actual keyboard tab traversal and VoiceOver start/pause/seek/volume/fullscreen interaction with the pointer outside the pane.

## Optimization opportunities (not additional reproduced crashes)

1. **Routing-copy confirmation is lazy only by route, not by file.** `ExportView.swift:916–930` wraps up to twelve route blocks in a LazyVStack, but each block is an eager VStack containing `ForEach(route.files)`. The unmatched-file block at `933–945` is eager too. A route containing tens of thousands of files becomes one enormous realized lazy child, so per-route laziness does not bound text/selectable-row creation. Flatten headers/files/dividers into one lazy list or use real lazy sections whose *file rows* are individual lazy elements. Preserve exact preview access; do not silently truncate safety-critical paths. No large hosted-sheet timing was run, so classify as structurally supported optimization, not a measured hang.
2. **Disk thumbnail budget is only pruned once on eligible launch.** `ImagePipeline.swift:110–128` schedules one delayed maintenance pass only at singleton initialization. Thumbnail writes at `326–330` do not trigger another budget check, and the pass does not reschedule. A long-running process can add arbitrary cache bytes after that pass, exceeding the documented 512 MiB/90-day budget indefinitely until a later launch. A same-day launch may skip pruning as well. Use utility-queue accounting and a coalesced threshold/periodic maintenance trigger while preserving the launch delay; avoid directory walks on every thumbnail. The 512 MiB condition is best described as a prune target in the current implementation, not a strict live ceiling.
3. **Fit-size measurement eagerly enters the RAW source lane.** `FullImageView.swift:417–423` immediately requests `HighResolutionImagePipeline.source` for each realized fitted image, even though the full-preview decode is guarded by a 40 ms dwell and neighbor prefetch by 60 ms. Source continuations are not individually canceled. Source creation retains lazy recipes rather than full decoded bitmaps, but CIRAWFilter creation/header I/O can be meaningful on RAW/slow media. Benchmark rapid navigation with cold RAWs before changing it; consider scan-cached oriented dimensions or the same short dwell for an uncached scale measurement.
4. **Secondary metadata detail is detached but unbounded across abandoned requests.** `MetadataPanel.swift:245–248` launches `Task.detached { MetadataExtractor.fields(...) }` and only drops the result after it finishes. The 80 ms dwell protects fast navigation, but once started, a slow file may keep running alongside later metadata reads; no queue/coalescer or worker cancellation is provided. Measure cold removable/network storage rather than assuming this is costly locally. If material, share a bounded/coalesced lane keyed by revision and perform source identity verification there.
5. **macOS 27 migration debt.** The selected SDK warns that AVAssetReader `add`, `startReading`, and `copyNextSampleBuffer` plus old AVPlayer notification aliases are deprecated. These are currently functional compatibility APIs, not audit failures. Migrate to current provider/async reader APIs as part of the audio-cancellation correction if that simplifies waiting for the actual stopped-reader boundary; retain support for the project's deployment target.

## Coverage and positive checks

### Media pipelines

- **ImagePipeline:** Reviewed public guards, separate full/thumbnail lanes, request coalescing and foreground promotion, memory cost limits, embedded-thumbnail fallback, first-frame background generation/timeouts, v5/legacy compatibility boundaries, disk promotion/healing, FNV disk key hashing, maintenance scheduling. M1 identified at uncached source reads; old cache-key separation itself is correct. No cache-key collision claim is made.
- **HighResolutionImagePipeline:** Reviewed lazy oriented source creation, queue bounds, source LRU, tile region mapping, clipping variants, tile LRU cost accounting, request retention/cancellation, normal/software contexts. Canceled queued waiters are resumed rather than stranded. Completion by key can consume a replacement request for the same immutable tile key; absent source-byte changes the result is equivalent, so this is not reported as a separate functional bug. Actual Core Image internal/GPU allocation is outside the explicit CGImage tile-cache accounting and was not measured.
- **HistogramPipeline/RawHistogramPipeline/ClippingPreviewPipeline:** Reviewed photo-only eligibility, bounded preview size, integer thresholds, transparent exclusion, bounded RAW linear buffer, delayed one-operation RAW lane, numeric LRUs, waiter cancellation/coalescing, clipping cache sizes. M2 concerns semi-transparent pixels, not normal opaque JPEG/RAW inputs. No true raw-photosite or inter-channel clipping claim is made; source labels correctly distinguish rendered and demosaiced RAW estimates.
- **AudioLevelPipeline/AudioLevelView:** Reviewed per-channel aggregation, signed envelopes/RMS/peaks, sample sanitization, temporal bin/cache budgets, PCM format/channel bounds, queue/cancellation, playback-following meter and downsampled Canvas waveform. Channels are not mixed down; whole-clip numeric payload is bounded. M3 identifies cancellation behavior rather than numeric-bin growth.
- **MetadataExtractor/VideoSupport:** Reviewed numeric sanitization, per-scan EXIF metadata, video/audio codec/header extraction, 15-second scanner bridges, bounded background worker assumptions, full Info fields, date/size formatting. Metadata work stays out of the SwiftUI body. Live read identity is included in M1's related lanes.
- **TextPreviewLoader/TextPreviewView:** Reviewed 1 MiB read cap, BOM Unicode decoding, NUL rejection, nonregular/leaf-symlink rejection, descriptor device/inode checks, scan identity before/after reading, cancellation checks, actor serialization, Markdown semantics, safe link-scheme filtering, retained native selection/scroll lifetime. No additional confirmed defect found. Complex Markdown layout and worst-case 1 MiB document layout were not visually stress-tested.
- **VideoPlaybackController:** Reviewed player ownership, remembered-position LRU, revision identity, status/end/failure callback generation guards, periodic observer/token teardown, rate/seek clamping, mutual exclusivity. Tested a real ready AVPlayer: seek to 20 seconds, seek to 60, immediately navigate away; actual currentTime and remembered position both stayed at 60. The suspected asynchronous nonzero-seek resume overwrite did **not** reproduce and is not a finding (`media-repro/seek.swift`, `seek-result.txt`).

### Native UI

- **Gallery/FullImage/Thumbnail:** Checked initial memory-cache seed, revision-qualified displayed state, task cancellation guards, view persistence, normal/clipping dwell, failure/retry paths, photo/media-specific branches. Gallery guards fitted-pinch completion against current store revision, preventing an old item closure from zooming a new photo.
- **ActualSizeImageView/ZoomViewport/PhotoZoomControl:** Checked persistent AppKit source generation, explicit placement requests, backing scale mapping, finite zoom clamps, fit/phone click geometry, slider/pinch handoff, native live-magnification terminal deduplication, drag panning, ten-frame reset/Reduce Motion, source-tile switch at 100%, visible ring retention, departure source retirement and balanced activity reporting. No new confirmed zoom/lifetime defect found. Actual high-resolution-source failure currently falls back to preview without a dedicated actual-size error/retry surface; this is a recovery/UX test gap rather than a demonstrated decode failure.
- **Browser/Grid/MediaTileAccessibility/PersistentVerticalScroller:** Reviewed directly observed lazy rows/cells, stable scroll IDs, bounds checks after structural mutation, immediate native single-click/double-click handling, rating-target isolation, rubber-band geometry/rendered-tile limitation, follow-scroll suppression/cancellation, native scroller configuration, accessibility actions/decision/stars/colors. Grid Play/Pause pointer action does not use the same follow-scroll suppression as photo/rating clicks; possible under-pointer movement is a low-priority UI consistency candidate, not a reproduced regression.
- **SessionView:** Reviewed modal confirmations/progress, shared Info-panel ownership, operation disabling, key-monitor AppKit window attach/detach lifecycle, exact-window/focus/modal gates, modifier normalization, review vs navigation shortcuts, text/VoiceOver chord preservation, shortcut/menu authority. Existing full HotkeyTests are the required integrated verification; root executed the complete Swift suite and should report its final results.
- **MetadataPanel/MetadataEditingControls/CameraQualityWarnings:** Reviewed revision guards, multi-selection eligibility, three histogram/audio tasks, filename planning cancellation and stale draft ownership, per-file metadata aggregates, cue preference/reset input commit paths, accessibility labels/actions. Source identity and unbounded secondary metadata readers are covered above. Stars/current-value accessibility ergonomics were not a standalone focus-order test.
- **Root/Welcome/Scanning/WindowContentLayout:** Reviewed phase-aware native window minimum/layout, usable-screen cap/vertical fallback, warning banners, display/backing changes, observation lifecycle, deferred state reports, folder drop decoding/validation, recents, drive chooser lifetime, cancel scan controls. No new confirmed phase/window defect found. Native display changes on a physically small display and delayed provider drops were not manually exercised.
- **Filter/Sort/ActionPalette:** Reviewed in-memory field bindings, checkbox/range validation, numeric debounce/commit, reset, dynamic action enablement, search/selection/keyboard actions and deferred sheet dismissal. U1 is the concrete numeric round-trip defect. No change to rating decision logic was made.
- **Export/Rename/Organize/SheetForm:** Reviewed selection/mode transitions, source inspection lifetime/cancellation, scope captures, planning cancellation flags, stale-result guards, preview/action separation, scrollable sheet content. Detailed filesystem mutation/recovery authority is owned by the other audit worker; this worker does not duplicate those conclusions. Copy-routing preview realization is the optimization above.

## Reproduction artifacts

- `media-repro/main.swift`: actual image replacement, alpha processor, and audio cancellation harness.
- `media-repro/repro`: release-optimized executable linked directly from canonical source files; module cache also stays in the disposable directory.
- `media-repro/result.txt`: sandboxed image/alpha evidence plus unavailable native audio result; not used for audio conclusion.
- `media-repro/result-unsandboxed.txt`: successful real AVFoundation run, including four-second abandoned-reader queue delay.
- `media-repro/filter.swift`, `filter`, `filter-result.txt`: exact extracted FilterView pure methods and reproduced precise-range drift (store boundary stub only).
- `media-repro/seek.swift`, `seek`, `seek-result.txt`: real AVPlayer ready-state seek/navigation check that rejected a suspected issue.
- `media-repro/fixtures`: only disposable PNG/cache/sparse WAV test inputs.

## Verification limits

Root owns full SwiftPM/test/build/native launch checks; this worker did not contend those outputs or install an app. The runtime reproductions above used actual canonical source, no source patches, Xcode selected via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, and an independent temporary module cache. Native AVFoundation runtime required sandbox escalation and succeeded. No screen capture, manual VoiceOver session, removable-drive benchmark, large-route hosted-layout benchmark, raw-camera corpus/color-profile comparison, or RSS/GPU-memory trace was performed. Those remain targeted follow-up checks, not implicit passes.
