# Automatic updates

This guide applies only to Louppe’s direct-download product. Never embed or
enable Sparkle in the Mac App Store build; its separate sandbox, signing, and
submission procedure is documented in [APP_STORE.md](APP_STORE.md).

Louppe uses Sparkle 2.10.0 for daily update checks, secure background downloads,
installation on quit, and the manual **Louppe → Check for Updates…** command.
Photographers can turn automatic checks and downloads on or off in
**Louppe → Settings…**.

## Security model

- The appcast is served over HTTPS from `appcast.xml` on `main`.
- Both the feed and update archive are signed with Sparkle's Ed25519 key.
- Public builds are signed with Developer ID, use the hardened runtime, and
  carry a stapled Apple notarization ticket for offline Gatekeeper checks.
- Louppe requires the signed feed and verifies the archive before extracting
  it. A changed or forged download is rejected.
- Only the public key is embedded in `Louppe.app`. The private key remains in
  the release owner's macOS Keychain under the account
  `com.alexandermarkin.louppe`.

The current public key is:

```text
ZT/Kv98/mVd/uo2iUyBb0Gj0ShZqZ+FdfthHBjyH86k=
```

Back up the private key somewhere encrypted and outside this repository. After
building once, locate Sparkle's key tool and export the key (substitute the
path printed by `find` if SwiftPM uses a different artifact folder):

```sh
find .build/artifacts -path '*/Sparkle/bin/generate_keys' -print

.build/artifacts/louppe/Sparkle/bin/generate_keys \
  --account com.alexandermarkin.louppe \
  -x /secure/offline/location/louppe-sparkle-private-key
```

Losing the private key means existing updater-enabled builds cannot accept a
normally signed update. Never commit or upload the exported private key.

Sparkle is fetched as a public binary with its official SHA-256 checksum.
`build_app.sh` disables SwiftPM's optional Keychain credential lookup, so
building Louppe neither needs nor requests access to a saved GitHub login.

## Release procedure

1. Confirm `VERSION` and the top `CHANGELOG.md` entry are final. The normal
   one-bump-per-release-cycle rule still applies.
2. Confirm the Mac has a valid **Developer ID Application** certificate and a
   `notarytool` Keychain profile. Build the signed app and archive:

   ```sh
   ./build_app.sh --developer-id \
     'Developer ID Application: Your Name (TEAMID)'
   ```

3. Submit that archive to Apple, staple the accepted ticket, and recreate the
   archive from the exact stapled app:

   ```sh
   ./Scripts/notarize_release.sh --keychain-profile louppe-notary
   ```

   The script saves Apple's result as `dist/notarization.json` and the detailed
   log as `dist/notarization-log.json`. Preserve both with the release records;
   they contain the request ID and results, but no credentials.

4. Sign the notarized archive for Sparkle and regenerate the signed feed:

   ```sh
   ./Scripts/prepare_update_feed.sh
   ./Scripts/verify_release.sh --publishing
   ```

5. Create GitHub release `v<MARKETING_VERSION>` and upload the exact generated
   `dist/Louppe.zip`. Do not recompress or replace it after the feed is made.
6. Commit and push the generated `appcast.xml`. Verify its enclosure URL
   downloads the GitHub release asset.
7. From the previous public Louppe version, choose **Check for Updates…** and
   complete one real update before announcing the release.

The archive name stays `Louppe.zip`; its versioned GitHub tag makes the URL
unique. `prepare_update_feed.sh` embeds only the current changelog entry,
creates no delta files, signs the archive reference, and signs the complete
feed. `verify_release.sh --publishing` then refuses the release if its
version/build, archive length or signature, feed signature, enclosure URL,
minimum macOS version, embedded framework, Developer ID signature, hardened
runtime, notarization ticket, Gatekeeper acceptance, or app signature is
inconsistent.

## Local verification

`build_app.sh` preserves Sparkle's versioned framework symlinks, embeds it in
`Contents/Frameworks`, signs the complete app, and builds the same zip used for
GitHub. Useful checks:

```sh
codesign --verify --deep --strict dist/Louppe.app
otool -L dist/Louppe.app/Contents/MacOS/Louppe
plutil -p dist/Louppe.app/Contents/Info.plist
./Scripts/verify_release.sh

SPARKLE_TOOLS="$(find .build/artifacts -type d -path '*/Sparkle/bin' -print -quit)"
"$SPARKLE_TOOLS/sign_update" \
  --account com.alexandermarkin.louppe \
  --verify appcast.xml
```

The feed URL will not expose an unpublished local build. Automatic checks only
offer versions present in the committed, signed `appcast.xml`.
