#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${SUMLY_ASC_CONFIG:-$HOME/.config/sumly/appstore-connect.env}"
if [[ ! -f "$CONFIG_FILE" && -f "$IOS_DIR/.appstore-connect.env" ]]; then
  CONFIG_FILE="$IOS_DIR/.appstore-connect.env"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

: "${ASC_KEY_ID:?Missing ASC_KEY_ID. Put it in $CONFIG_FILE or export it in the shell.}"
: "${ASC_ISSUER_ID:?Missing ASC_ISSUER_ID. Put it in $CONFIG_FILE or export it in the shell.}"

ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.private_keys/AuthKey_${ASC_KEY_ID}.p8}"

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "App Store Connect private key not found: $ASC_KEY_PATH" >&2
  exit 1
fi

if [[ ! -r "$ASC_KEY_PATH" ]]; then
  echo "App Store Connect private key is not readable: $ASC_KEY_PATH" >&2
  exit 1
fi

if [[ "${1:-}" == "--check-auth" ]]; then
  xcrun altool --list-apps \
    --api-key "$ASC_KEY_ID" \
    --api-issuer "$ASC_ISSUER_ID" \
    --p8-file-path "$ASC_KEY_PATH" >/dev/null
  echo "App Store Connect API Key authentication succeeded."
  exit 0
fi

cd "$IOS_DIR"

xcodegen generate >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sumly/Support/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sumly/Support/Info.plist)"
ARCHIVE_PATH="build/Sumly-${VERSION}-b${BUILD}.xcarchive"
EXPORT_PATH="build/ipa-b${BUILD}"

mkdir -p build
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "Archiving Sumly ${VERSION} (${BUILD})..."
xcodebuild   -project Sumly.xcodeproj   -scheme Sumly   -configuration Release   -destination 'generic/platform=iOS'   -archivePath "$ARCHIVE_PATH"   -allowProvisioningUpdates   -authenticationKeyPath "$ASC_KEY_PATH"   -authenticationKeyID "$ASC_KEY_ID"   -authenticationKeyIssuerID "$ASC_ISSUER_ID"   archive

echo "Uploading Sumly ${VERSION} (${BUILD}) to App Store Connect..."
xcodebuild   -exportArchive   -archivePath "$ARCHIVE_PATH"   -exportPath "$EXPORT_PATH"   -exportOptionsPlist "$SCRIPT_DIR/ExportOptions-upload.plist"   -allowProvisioningUpdates   -authenticationKeyPath "$ASC_KEY_PATH"   -authenticationKeyID "$ASC_KEY_ID"   -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "Upload command completed for Sumly ${VERSION} (${BUILD})."
