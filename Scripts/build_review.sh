#!/bin/zsh
# Package a clearly named local review copy without installing over Louppe.
set -euo pipefail
cd "$(dirname "$0")/.."

REVIEW_NAME="${1:-louppe-$(date +%Y.%m.%d)}"
if [[ ! "$REVIEW_NAME" =~ ^louppe-[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
    echo "Usage: $0 [louppe-YYYY.MM.DD]" >&2
    exit 2
fi

./build_app.sh

REVIEW_STAGE="$(mktemp -d /private/tmp/Louppe-review.XXXXXX)"
trap 'rm -rf "$REVIEW_STAGE"' EXIT
REVIEW_APP="$REVIEW_STAGE/$REVIEW_NAME.app"
ditto --noextattr --noqtn dist/Louppe.app "$REVIEW_APP"
REVIEW_PLIST="$REVIEW_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $REVIEW_NAME" "$REVIEW_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $REVIEW_NAME" "$REVIEW_PLIST"
/usr/libexec/PlistBuddy -c 'Add :LouppeReviewBuild bool true' "$REVIEW_PLIST"
/usr/libexec/PlistBuddy -c 'Set :SUEnableAutomaticChecks false' "$REVIEW_PLIST"
/usr/libexec/PlistBuddy -c 'Set :SUAutomaticallyUpdate false' "$REVIEW_PLIST"
xattr -cr "$REVIEW_APP"
codesign --force --sign - "$REVIEW_APP"
codesign --verify --deep --strict "$REVIEW_APP"

REVIEW_OUTPUT="$PWD/dist/$REVIEW_NAME.app"
REVIEW_ARCHIVE="$PWD/dist/$REVIEW_NAME.zip"
rm -rf "$REVIEW_OUTPUT"
ditto --noextattr --noqtn "$REVIEW_APP" "$REVIEW_OUTPUT"
xattr -cr "$REVIEW_OUTPUT"
ditto -c -k --sequesterRsrc --keepParent "$REVIEW_APP" "$REVIEW_ARCHIVE"
mkdir "$REVIEW_STAGE/unpacked"
ditto -x -k "$REVIEW_ARCHIVE" "$REVIEW_STAGE/unpacked"
codesign --verify --deep --strict "$REVIEW_OUTPUT"
codesign --verify --deep --strict "$REVIEW_STAGE/unpacked/$REVIEW_NAME.app"
REVIEW_DIFFERENCES="$(rsync -rcln --delete --itemize-changes \
    "$REVIEW_OUTPUT/Contents/" "$REVIEW_STAGE/unpacked/$REVIEW_NAME.app/Contents/")"
if [[ -n "$REVIEW_DIFFERENCES" ]]; then
    print -r -- "$REVIEW_DIFFERENCES" >&2
    echo 'Review archive differs from the verified app.' >&2
    exit 1
fi
echo "Review app: $REVIEW_OUTPUT"
echo "Review archive: $REVIEW_ARCHIVE"
