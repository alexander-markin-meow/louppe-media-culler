# Mac App Store submission

Louppe has two intentionally separate distribution products:

- `./build_app.sh` is the existing direct-download build. It contains the
  signed Sparkle updater and its release ZIP.
- `./build_app.sh --app-store` is the Store product. It contains neither
  Sparkle nor an update feed, is sandboxed, and has a valid privacy manifest.
  Its ZIP is a local verification artifact only — do not upload it to App
  Store Connect.

The separation is deliberate: a Mac App Store app must use Store-delivered
updates, may not add code or functionality after review, and needs App
Sandbox. The Store product asks only for read/write access to folders the
photographer explicitly chooses. It retains those choices as security-scoped
bookmarks for Recent folders. An export destination receives the same treatment
only while its durable recovery journal could still need it after an
interruption; a completed or explicitly retired recovery record immediately
relinquishes that access. The app does not request broad Pictures, Movies,
Music, Full Disk Access, network, camera, microphone, contacts, or
accessibility permissions.

## What the build checks

`./Scripts/verify_release.sh --app-store` independently verifies the loose
app and the archive. It requires the sandbox, user-selected read/write, and
bookmark entitlements; a valid bundled `PrivacyInfo.xcprivacy`; no Sparkle
framework, link, or update-feed key; matching version/build values; and the
two bundled third-party notices.

The privacy manifest says that Louppe doesn’t track or collect data. It
declares only the local APIs the app uses: timestamps for media in folders the
person selected, disk-space checks before a copy or move, and the app’s own
preferences. Those values stay on the Mac.

## Before creating an upload package

1. Test the exact Store build on a physical Mac using a normal selected media
   folder: initial open, scan, close/reopen Recent, rating save, Copy, Move,
   Trash/Undo, source organization, video/audio playback, waveform analysis,
   and recovery after cancelling a Copy. Verify the app reports an actionable
   error rather than silently changing media when a card is removed or access
   is revoked.
2. In App Store Connect, create the Mac app record for
   `com.alexandermarkin.louppe`, use the version/build in `VERSION`, provide a
   support URL and a public privacy-policy URL, and answer App Privacy as
   “does not collect data” only while that remains true for every linked SDK.
   Set the age rating and category truthfully, and use screenshots containing
   media you own or have permission to show.
3. Add review notes explaining that the reviewer can use **Choose Photo
   Folder…** with a supplied sample folder; all analysis is local; originals
   change only after the explicit Move, Organize Source Folder, XMP, or Trash
   confirmations. Mention the optional video/audio features and the Command
   Palette so they are not mistaken for hidden functionality.
4. Use the Apple Distribution and 3rd Party Mac Developer Installer
   certificates from the correct team. Re-run the Store build immediately
   before signing it.

## Signing and upload artifact

After the Store build and checks pass, create the signed installer package:

```sh
./Scripts/package_app_store.sh \
  --application-identity 'Apple Distribution: Your Name (TEAMID)' \
  --installer-identity '3rd Party Mac Developer Installer: Your Name (TEAMID)'
```

The script never uploads. It re-signs only `dist/Louppe.app` with the
least-privilege entitlements, verifies it, then creates and verifies
`dist/Louppe.pkg`. Upload that signed package using the current App Store
Connect workflow, then complete Apple’s metadata, export-compliance, and
review-note forms. Do not sign or upload the direct-download ZIP.

## Release gate

For a Store submission, the final local gate is:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-keychain
./Tests/run_performance_checks.sh
./build_app.sh --app-store
./Scripts/package_app_store.sh --application-identity '…' --installer-identity '…'
```

`package_app_store.sh` needs the owner’s Apple certificates, so it cannot be
completed by an unsigned development build. App Store Connect metadata and
the final upload/review are also owner-controlled steps.
