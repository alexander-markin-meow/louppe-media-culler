#!/bin/zsh
# Notarizes the Developer ID build, staples its ticket, and recreates the
# release ZIP from the exact stapled app. It never uploads a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 || "$1" != "--keychain-profile" ]]; then
    echo "Usage: $0 --keychain-profile PROFILE" >&2
    exit 2
fi

PROFILE="$2"
APP="$PWD/dist/Louppe.app"
ARCHIVE="$PWD/dist/Louppe.zip"
RESULT="$PWD/dist/notarization.json"
LOG="$PWD/dist/notarization-log.json"

[[ -d "$APP" ]] || {
    echo "dist/Louppe.app is missing. Build with --developer-id first." >&2
    exit 1
}
[[ -f "$ARCHIVE" ]] || {
    echo "dist/Louppe.zip is missing. Build with --developer-id first." >&2
    exit 1
}

"$PWD/Scripts/verify_release.sh" --developer-id

WORK_DIR="$(mktemp -d /private/tmp/Louppe-notarize.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
STAPLED_APP="$WORK_DIR/Louppe.app"
STAPLED_ARCHIVE="$WORK_DIR/Louppe.zip"

ditto --noextattr --noqtn "$APP" "$STAPLED_APP"
xattr -cr "$STAPLED_APP"

xcrun notarytool submit "$ARCHIVE" \
    --keychain-profile "$PROFILE" \
    --wait \
    --output-format json > "$RESULT"

STATUS="$(plutil -extract status raw "$RESULT")"
REQUEST_ID="$(plutil -extract id raw "$RESULT")"
if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization was not accepted. Apple log:" >&2
    xcrun notarytool log "$REQUEST_ID" --keychain-profile "$PROFILE" >&2 || true
    exit 1
fi
xcrun notarytool log "$REQUEST_ID" \
    --keychain-profile "$PROFILE" > "$LOG"

xcrun stapler staple "$STAPLED_APP"
xcrun stapler validate "$STAPLED_APP"
codesign --verify --deep --strict --verbose=2 "$STAPLED_APP"
spctl --assess --type execute --verbose=4 "$STAPLED_APP"

ditto -c -k --sequesterRsrc --keepParent \
    "$STAPLED_APP" "$STAPLED_ARCHIVE"
rm -rf "$APP"
ditto --noextattr --noqtn "$STAPLED_APP" "$APP"
cp "$STAPLED_ARCHIVE" "$ARCHIVE"

"$PWD/Scripts/verify_release.sh" --developer-id

echo ""
echo "Notarized and stapled → $APP"
echo "Rebuilt release archive → $ARCHIVE"
echo "Apple result → $RESULT"
echo "Apple log → $LOG"
