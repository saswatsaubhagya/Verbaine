#!/bin/bash
#
# Release builds for Polish.
#
#   scripts/release.sh testflight   archive, export a signed pkg, upload to App Store Connect
#   scripts/release.sh direct       archive, export a notarized+stapled zip for direct download
#
# Required environment:
#   TEAM_ID                  Apple Developer team id
#   ASC_KEY_ID               App Store Connect API key id        (testflight)
#   ASC_ISSUER_ID            App Store Connect API issuer id     (testflight)
#   ASC_KEY_PATH             path to the .p8 private key         (testflight)
#   NOTARY_PROFILE           notarytool keychain profile name    (direct)
#
# Build number comes from the git commit count, so every upload is unique.

set -euo pipefail

MODE="${1:-}"
case "$MODE" in
testflight | direct) ;;
*)
	echo "usage: $0 {testflight|direct}" >&2
	exit 2
	;;
esac

cd "$(dirname "$0")/.."
: "${TEAM_ID:?set TEAM_ID to your Apple Developer team id}"

BUILD=$(git rev-list --count HEAD)
VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' Polish.xcodeproj/project.pbxproj | head -1)
OUT="build/release"
ARCHIVE="$OUT/Polish.xcarchive"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Archiving Polish $VERSION ($BUILD)"
xcodebuild archive \
	-project Polish.xcodeproj \
	-scheme Polish \
	-configuration Release \
	-destination 'generic/platform=macOS' \
	-archivePath "$ARCHIVE" \
	-allowProvisioningUpdates \
	DEVELOPMENT_TEAM="$TEAM_ID" \
	CURRENT_PROJECT_VERSION="$BUILD" \
	CODE_SIGN_IDENTITY="$([ "$MODE" = testflight ] && echo 'Apple Distribution' || echo 'Developer ID Application')" \
	CODE_SIGN_STYLE=Automatic

if [ "$MODE" = testflight ]; then
	cat >"$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>destination</key><string>export</string>
</dict>
</plist>
EOF
	echo "==> Exporting for App Store Connect"
	xcodebuild -exportArchive \
		-archivePath "$ARCHIVE" \
		-exportOptionsPlist "$OUT/ExportOptions.plist" \
		-exportPath "$OUT/export" \
		-allowProvisioningUpdates

	: "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}" "${ASC_KEY_PATH:?set ASC_KEY_PATH}"
	PKG=$(find "$OUT/export" -name '*.pkg' | head -1)
	echo "==> Validating $PKG"
	xcrun altool --validate-app -f "$PKG" -t macos \
		--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
	echo "==> Uploading to App Store Connect (TestFlight)"
	xcrun altool --upload-app -f "$PKG" -t macos \
		--apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
	echo "==> Uploaded build $BUILD. Processing takes a few minutes; then add testers in App Store Connect."
else
	cat >"$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
EOF
	echo "==> Exporting Developer ID build"
	xcodebuild -exportArchive \
		-archivePath "$ARCHIVE" \
		-exportOptionsPlist "$OUT/ExportOptions.plist" \
		-exportPath "$OUT/export" \
		-allowProvisioningUpdates

	: "${NOTARY_PROFILE:?set NOTARY_PROFILE (see: xcrun notarytool store-credentials)}"
	ZIP="$OUT/Polish-$VERSION-$BUILD.zip"
	ditto -c -k --keepParent "$OUT/export/Polish.app" "$ZIP"
	echo "==> Notarizing $ZIP"
	xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$OUT/export/Polish.app"
	spctl --assess --type execute --verbose "$OUT/export/Polish.app"
	rm "$ZIP"
	ditto -c -k --keepParent "$OUT/export/Polish.app" "$ZIP"
	echo "==> Notarized and stapled: $ZIP"
fi
