# Homebrew distribution

The app repository also serves as our Homebrew tap. The cask installs the exact
signed, notarized `Louppe.zip` from GitHub Releases. No separate app build,
installer, hosting service, or Homebrew repository is needed.

## Install

```sh
brew tap alexander-markin-meow/louppe https://github.com/alexander-markin-meow/louppe-media-culler
brew install --cask alexander-markin-meow/louppe/louppe
```

If Homebrew requests trust for this non-official tap, follow its prompt to trust
only `alexander-markin-meow/louppe/louppe`.

Louppe requires Apple silicon and macOS 14 or newer. It retains the built-in
Sparkle updater. `auto_updates true` tells Homebrew that the app updates itself;
users who prefer Homebrew can explicitly upgrade this cask with
`brew upgrade --cask --greedy alexander-markin-meow/louppe/louppe`.

The cask deliberately has no cleanup rule that deletes ratings, folder access,
or preferences. Uninstalling removes the app, not photo-library files.

## Releases

Publish a stable `vX.Y.Z` GitHub release with the final `Louppe.zip` attached,
following [UPDATES.md](UPDATES.md). The Homebrew workflow then downloads the
latest stable ZIP, checks its hash and size against GitHub, verifies the app's
identity, version, updater, minimum macOS, and architecture, and commits only
the cask's version/checksum update to `main`. Prereleases never become the
stable Homebrew package. This automation does not publish a Louppe release or
change the appcast.

There is no additional routine release step. Check that the Homebrew workflow
succeeded; it requires GitHub Actions to have permission to push to `main`.
If the ZIP was attached after publication, rerun **Update Homebrew package**
from GitHub Actions. Changes to architecture or minimum macOS stop automation
until the cask compatibility requirements are reviewed.

For manual verification/update:

```sh
python3 Scripts/update_homebrew_cask.py
```

This is our own tap, not a listing in Homebrew's main catalog. Main-catalog
inclusion can be requested later; until then, the explicit tap URL is required.
