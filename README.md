# Louppe Media Culler

(˶ᵔ ᵕ ᵔ˶)

**Louppe is a fast, open-source media culler for photos, video, and audio on Mac.**

Louppe helps review a folder or memory card, mark the shots you want to
keep, and export them.

Your photos stay in their original quality. Export copies them by default.
Louppe only moves or renames originals when you deliberately choose **Move
to…**, send photos to the macOS Trash, confirm **Organize Source Folder**, or
confirm a rename. It never permanently deletes a file.

macOS 14 or newer.

Learn more at [louppe.eu](https://louppe.eu).

## Download

Download `Louppe.zip` from the
[latest release](https://github.com/alexander-markin-meow/louppe-media-culler/releases/latest),
unzip it, and drag `Louppe.app` into Applications.

Louppe is not notarized by Apple. The first time you open it, macOS may say it
cannot verify the developer. Right-click Louppe, choose **Open**, then choose
**Open** again. You only need to do this once.

## Basics

1. Open a folder or memory card.
2. Press **F** for Yes or **D** for No as you review.
3. Filter, sort, or select several photos when needed.
4. Press **⌘E** to copy your chosen photos to another folder.

When one copy folder is not enough, turn on **Route copies to multiple
folders** in Export. Add an explicit route for a decision, stars, color label,
file type, or media type, then choose a separate destination for each route.
Louppe previews every source and destination before copying. Items that do not
match a route stay in the source folder; routes that overlap, match nothing,
lack a folder, or collectively exceed a shared drive's space cannot start.

Most photo, video, and audio formats are supported; support for more file types is
planned. Filters and sorting cover decisions, star ratings, color labels,
dates, folders, file types, camera details, media type, media length, and—when
videos are present—resolution, frame rate, and codec.

Choose **File → Organize Source Folder…** to move All, Filtered, or Selected
items into nested folders such as Decision → Date. Check the folder levels you
want and drag them into priority order. Existing folder, date, stars, color,
camera, lens, file type, and media type can all be levels; date folder names
follow the Mac's language, region, and custom short-date format. The Command
Palette includes **Organize by Date Taken Only…** to open this screen with Full
date as the sole enabled folder level, ready for preview and confirmation.

Rename one item directly where its filename is shown in the Info panel. Click
the filename, edit the base name, and press Return; the extension stays
unchanged, matching RAW+JPEG files keep one shared name, and recognized XMP
sidecars follow. For a batch, select multiple items and choose **Rename Files…**
in the Info panel, or search **⌘K** for **Rename Files from Metadata**.
Choose All, Filtered, or Selected, then combine and order Date taken, Time
taken, Camera, Lens, Original name, and Sequence. The preview shows every new
name before confirmation. Sequence order is deterministic—capture time first,
then the original path—and is enabled by default to distinguish shots captured
in the same second. Missing metadata is written explicitly as Unknown rather
than silently omitted. Renaming never changes file contents, extensions, or
folders, never overwrites, and one **⌘Z** restores the previous names during
the open session. A Lightroom `.acr` companion blocks the affected rename so
it cannot be left under a misleading old name.

Matching RAW+JPEG files are separate photos by default. In Filter → File types,
**Treat matching RAW + JPEG as one photo** groups an unambiguous match, including
across subfolders. RAW and JPEG always keep their own decision, stars, and color
label; while grouped, ratings, selection, Export, Move, and Clean Up apply to
both files.

For archiving, **Clean Up → Move Paired JPEGs to Trash…** keeps the RAW member
of every matching pair in the chosen All Media, Filtered, or Selected scope.
**Move Paired RAWs to Trash…** does the reverse. These actions recognize the
same unambiguous pairs whether files are currently reviewed together or
separately, never touch standalone files or XMP sidecars, ask for confirmation,
and can be undone with **⌘Z** while the files remain in the Trash. Both actions
are also searchable in the **⌘K** Command Palette.

For close inspection, Gallery offers a fast Fit view, a phone-sized preview
(**A**), and true 100% zoom (**S**). Video and audio positions are remembered
while the folder stays open, and the Info panel offers 1×, 1.5×, 2×, or 2.5×
playback for both video and audio recordings. Standalone audio fills the
Gallery with its whole-file waveform and moving playhead. For video and audio,
Info shows independent live loudness meters for every channel, with green,
orange, and red level zones. The Info panel includes metadata, a histogram,
and clipping information. Press **X** to show or hide the red preview clipping
overlay.

The Info panel can show optional **Quality cues** for high ISO, slow shutter
speeds, and substantial near-black or near-white luminance areas. When cues
exist, one quiet row beneath the shooting metadata opens their exact values and
sources. The defaults are ISO 6400 or above, 1/30 s or slower, and 10% or more
near black or white; choose **Louppe → Settings → Quality Cues** to adjust
them. They never change ratings, filters, selection, exports, sidecars, or
files.

The histogram appears immediately from the rendered preview. For a supported
RAW primary file, a delayed, bounded Core Image RAW decode replaces the
histogram and clipping cues when ready; its small `Rendered` / `RAW` label
makes the source clear. This is a scaled RGB decode from RAW sensor data, not a
camera-maker proprietary per-photosite histogram. If RAW decoding is not
available, the rendered estimate remains. **X** always controls a preview
clipping overlay, because a RAW-derived mask would not align honestly with the
displayed rendering.

## Duplicate and burst review

Choose **Sort → Review groups → Analyze Folder Locally**, or use the Command
Palette, to review candidate groups without changing anything. Louppe keeps
this analysis on your Mac and never automatically rates, exports, moves, or
trashes a file.

- **Exact duplicates** require matching local SHA-256 file fingerprints.
- **Likely similar photos** use small local preview fingerprints. They are a
  conservative starting point for your review, not a certainty; the
  Similarity control makes suggestions stricter or broader.
- **Capture bursts** group consecutive still photos taken close together; the
  Burst interval controls that capture-time gap.

Grouped review respects the current filter and is easy to leave with **Normal
Review**. Matching RAW+JPEG files remain one review item when that option is
enabled; videos and audio recordings can be found as exact byte duplicates but
are not treated as visually similar photos or still-photo bursts.

## Keyboard shortcuts

### Review and navigation

| Key | What it does |
|---|---|
| **F** | Mark Yes and move to the next undecided item |
| **D** | Mark No and move to the next undecided item |
| **0–5** | Clear stars or assign 1–5 stars without changing the Yes/No decision |
| **← / →** | Go to the previous / next item. In Gallery on a playable video, seek backward / forward by 0.5 seconds instead |
| **⇧← / ⇧→** | In Gallery on a playable video, seek backward / forward by 5 seconds |
| **J / L** | Go to the previous / next item, including when a video is open |
| **↑ / ↓** | Gallery: previous / next item. Grid: previous / next row |
| **Space** or **K** | Play or pause a video or audio file. On a photo, Space goes to the next item |
| **S** | Gallery: switch between Fit and true 100% zoom |
| **A** | Gallery: switch between Fit and a phone-sized preview |
| **X** | Gallery: show or hide the red preview clipping overlay |
| **Tab** or **G** | Switch between Gallery and Grid |
| **Q** | Show or hide the thumbnail browser in Gallery |
| **W** | Show or hide the info panel |
| **⌘+ / ⌘−** | Make Grid thumbnails bigger / smaller |

### Actions and selection

| Key | What it does |
|---|---|
| **E** or **⌘E** | Open Export |
| **R** | Clear all Yes/No decisions. Large sets ask for confirmation; **Return** confirms |
| **Z** or **⌘Z** | Undo the last decision, star, color-label, decision reset, Trash action, source rename, or source-folder organization |
| **⌘O** | Open a different folder |
| **⌘R** | Scan the current folder again |
| **⌘K** | Open the Command Palette to search actions, renaming, metadata tools, filters, and folder operations |
| **⌘A** | Select every item currently shown by the filter |
| **⌘← / ⌘→** | Choose a slower / faster speed for playable video or audio. On a photo, select the previous / next visible item |
| **⌘⇧← / ⌘⇧→** | Select from the current item to the first / last |
| **Esc** | Cancel a scan or clear the current selection |
| **⌘⌫** | Move the selection to the Trash immediately, without a dialog. **⌘Z** restores it |

Letter review shortcuts such as F, D, and G stay active after clicking Decision,
View, toolbar, or media controls. When a control has keyboard focus, Space,
Tab, Escape, and the arrow keys remain available to that control. Louppe also
leaves every shortcut alone while you are editing or selecting text, or
responding to a dialog, sheet, or popover.

## Mouse and trackpad

- In Grid, click a photo to select it immediately. Click its status circle to
  change its Yes/No decision. Double-click the photo to open it in Gallery. These
  actions keep the Grid at the same scroll position.
- **Shift-click** selects a range. **Command-click** adds or removes one item.
- Drag across Grid photos to select several of them.
- In Gallery, double-click a point on a photo to inspect that area at true
  100% size. Double-click again to return to Fit.

Louppe also supports VoiceOver. Decisions, stars, labels, and controls do not rely on color
alone, so the main review workflow can be completed with the keyboard.

## Keeping your files safe

- Export first limits its work to **All Media**, **Filtered**, or **Selected**
  items, then combines decisions, stars, and colors so only items inside that
  scope matching all selected metadata are included. **Filtered** is the safe
  default, and Selected means the explicit selection or the current item when
  there is no multi-selection. Export uses **Copy** by default. **Move** is
  available when the destination is
  on the same storage volume and uses atomic filesystem renames; use Copy for
  another drive or card. **Metadata (XMP)** safely writes or merges sidecars
  beside the selected originals without copying, moving, or embedding media.
  Choose Universal XMP, Lightroom Classic, Bridge, Capture One, or darktable
  so decisions use the intended portable representation; stars and colors
  always keep their native XMP fields.
- Copy and Move now offer **Include XMP sidecars**. It starts off when the
  selected photos have no recognized XMP and starts on when at least one does;
  a manual choice remains in force until the Export sheet closes. With it on,
  Louppe creates or safely merges the destination stem packet and carries
  extension-qualified application packets unchanged. Copy never edits the
  source packet. Move leaves XMP behind when the option is off; when it is on,
  a shared RAW+JPEG packet is copied if a same-stem member stays behind and is
  transferred only when the whole family moves. Lightroom Classic `.acr`
  heavy-edit companions are never included or modified; Export warns when an
  exact associated companion will remain in the source folder.
- Metadata (XMP) inspects every same-stem family before writing. It shows
  creates, updates, already-current packets, unsupported files, and conflicts,
  then publishes through three bounded background lanes. When exactly one RAW
  and one JPEG disagree, **Resolve RAW + JPEG Conflicts…** can explicitly use
  either file’s Louppe metadata for both in one undoable action, or leave them
  separate and skip the shared packet. Louppe always rebuilds the selection and
  complete plan after a resolution. Existing edit data and unrelated keywords
  survive; replacing or removing an external color label requires explicit
  confirmation. A stop, folder change, rescan, or Quit waits
  for an atomic sidecar boundary, and an externally changed packet is skipped
  instead of overwritten. Sidecars for JPEG, TIFF, DNG, HEIC, and PNG are
  best-effort because some applications expect metadata embedded in those
  formats; Louppe never modifies the original to work around that limitation.
- Export checks the destination before starting. A long copy can be stopped
  safely, and a RAW+JPEG pair never gets left half-copied. Louppe prevents
  automatic system sleep while files are moving (the display may still turn
  off). Keep a MacBook lid open until the transfer finishes. If lid-close
  sleep does happen, Copy waits for the exact same removable source to remount
  after wake and safely retries an untouched in-progress file once. Completed
  copies remain at the destination; a failed in-progress temporary is removed
  only after Louppe verifies that exact physical file belongs to the operation.
- **Route copies to multiple folders** is Copy-only. Every route has one
  explicit condition and a separately chosen destination—there is no hidden
  “any” route. Louppe blocks overlapping or empty routes, duplicate or unsafe
  folders, split XMP families, and insufficient combined capacity on a shared
  drive, then shows the complete source-to-destination plan along with media
  that will not be copied. All route copies share the same durable recovery
  record and collision handling as normal Copy.
- **Clean Up** sends files to the macOS Trash, never to permanent deletion.
  It asks for confirmation unless you use **⌘⌫**. Immediately afterward,
  **⌘Z** can restore the whole batch during the open session while the files
  remain in the Trash. It can also remove only the JPEG or only the RAW member
  of unambiguous pairs while retaining the other file. Emptying the Trash
  deletes moved files permanently.
- **Organize Source Folder** previews every destination before moving anything.
  All, Filtered, and Selected scopes show live counts. Checked folder levels
  are applied in draggable priority order, so Decision → Date and Date →
  Decision create different layouts. **Existing folder** preserves either the
  old top-level folder or its full relative path; turning it off flattens that
  structure into the chosen new levels. Old folders are not deleted, even when
  they become empty, and hidden, unrelated, unsupported, and `.acr` files
  remain where they are. Grouped RAW+JPEG files and recognized XMP sidecars
  follow together. Any filename, sidecar-family, or destination conflict blocks
  the complete move—Louppe never adds a suffix or overwrites. **⌘Z** restores
  the previous file locations during the same open session. ExFAT camera cards
  show an extra reduced-crash-protection warning because macOS cannot durably
  flush their folder entries like APFS. After confirmation, Louppe first tests
  a pair of disposable files to prove macOS refuses an occupied destination,
  preserves the same physical file during a move, and keeps the bytes intact;
  it moves no photo if that check fails. Keep the card connected and the Mac
  awake until the operation finishes.
- **Rename Files** changes originals only after an exact plan. A single rename
  starts where the filename is shown in the Info panel; metadata batches use All, Filtered,
  or Selected scope and sortable filename parts. Extensions and folders stay
  unchanged. Recognized RAW+JPEG/XMP families move as one journaled unit, while
  `.acr`, ambiguous sidecars, occupied names, case-equivalent names, and names
  that could create a false RAW+JPEG pair block the plan. No suffix is invented
  silently and nothing is overwritten. **⌘Z** restores the prior names.
- Matching RAW+JPEG files, if grouped, move or copy together.
- Louppe keeps a small safety record during file operations. If the app is
  interrupted, Louppe checks the exact files and never overwrites an existing
  file. A completed Trash action stays in Trash—it is never silently undone on
  the next launch. If an unusual file action still needs attention, reviewing,
  rating, opening folders, saving, and quitting remain available; only another
  Copy, Move, Rename, Organize, Clean Up, or Trash undo waits. Retry when the relevant
  drive is available, or choose **Keep Files As They Are** to set aside only Louppe's
  recovery record—without deleting its contents—and continue with the files
  exactly where they are.
- Ratings are saved automatically in `.louppe_session.json` inside the opened
  folder, with an identity-bound local backup when that folder is read-only or
  its card/drive is temporarily disconnected. A clean Quit does not rewrite an
  already saved session just because the photo volume is no longer connected.
  Ratings follow the
  verified physical file across a rename, remain saved while a file is
  temporarily missing, and current identity-bound ratings are never silently
  applied to a same-named replacement. If a reused card or folder contains
  different files with those names, **Open as New Session** explicitly replaces
  the stale saved decisions and opens the current files unrated. Louppe also refuses to overwrite a session file changed by
  another app and will not confuse two cards or folders that later use the
  same path. An older filename-only session upgrades automatically when every
  saved filename is still present. If its saved folder path differs, Louppe
  first asks you to **Open Anyway**, rechecks the exact session file and saved
  filenames, then binds the migrated session to the current folder. If old
  saved items are missing, you can explicitly forget only their ratings and
  open the rest of the folder without restoring intentionally deleted files.

Louppe recognises common camera RAW files, JPEG, TIFF, PNG, HEIC, WebP, AVIF,
and the photo, video, and audio formats supported by macOS. An unsupported file still
appears in the review, so it can be rated and exported.

---

For architecture, safety rules, and contributor notes, see
[AGENTS.md](AGENTS.md). Performance details are in
[Docs/PERFORMANCE.md](Docs/PERFORMANCE.md), and release instructions are in
[Docs/UPDATES.md](Docs/UPDATES.md). The separate Mac App Store build, signing,
privacy, reviewer-note, and submission checklist is in
[Docs/APP_STORE.md](Docs/APP_STORE.md).

---

## License

Louppe is free and open source under the [MIT License](LICENSE).

Created by [Alex Markin](https://alex-markin.com); contact: a@alex-markin.com
