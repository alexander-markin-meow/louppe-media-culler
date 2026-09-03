#!/bin/zsh
# Creates a signed installer package for Mac App Store upload from the
# sandboxed Louppe product. It never contacts App Store Connect or uploads.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 4 || "$1" != "--application-identity" || "$3" != "--installer-identity" ]]; then
    echo "Usage: $0 --application-identity 'Apple Distribution: …' --installer-identity '3rd Party Mac Developer Installer: …'" >&2
    exit 2
fi

APPLICATION_IDENTITY="$2"
INSTALLER_IDENTITY="$4"
APP="$PWD/dist/Louppe.app"
PACKAGE="$PWD/dist/Louppe.pkg"

[[ -d "$APP" ]] || {
    echo "dist/Louppe.app is missing. Run ./build_app.sh --app-store first." >&2
    exit 1
}

"$PWD/Scripts/verify_release.sh" --app-store
xattr -cr "$APP"
codesign --force --options runtime --timestamp --sign "$APPLICATION_IDENTITY" \
    --entitlements "$PWD/Louppe.entitlements" "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$PACKAGE"
productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PACKAGE"
pkgutil --check-signature "$PACKAGE"

echo "Prepared Mac App Store upload package → $PACKAGE"
