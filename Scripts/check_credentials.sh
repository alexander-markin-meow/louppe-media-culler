#!/bin/zsh
# Scan repository history locally; never send the source to a scanning service.
set -euo pipefail
cd "$(dirname "$0")/.."

readonly version="8.30.1"
case "$(uname -m)" in
    arm64)
        readonly architecture="arm64"
        readonly checksum="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
        ;;
    x86_64)
        readonly architecture="x64"
        readonly checksum="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"
        ;;
    *)
        echo "Credential checks require a supported macOS architecture." >&2
        exit 1
        ;;
esac
readonly scan_directory="$(mktemp -d /private/tmp/louppe-credential-check.XXXXXX)"
trap 'rm -rf "$scan_directory"' EXIT
readonly archive="$scan_directory/gitleaks.tar.gz"
curl --fail --silent --show-error --location --retry 3 \
    "https://github.com/gitleaks/gitleaks/releases/download/v${version}/gitleaks_${version}_darwin_${architecture}.tar.gz" \
    --output "$archive"
print -r -- "$checksum  $archive" | shasum -a 256 --check --status
tar -xzf "$archive" -C "$scan_directory" gitleaks
"$scan_directory/gitleaks" git --redact --no-banner --log-opts="--all" .
# Also check staged and unstaged tracked edits when run before committing.
"$scan_directory/gitleaks" git --pre-commit --staged --redact --no-banner .
"$scan_directory/gitleaks" git --pre-commit --redact --no-banner .
