#!/usr/bin/env bash
# Builds dist/Spectrum.app, dist/Spectrum-<version>.zip and dist/Spectrum-<version>.dmg.
#
#   scripts/bundle.sh 0.1.0
#
# The app is signed ad hoc unless SIGN_IDENTITY names a Developer ID certificate.
set -euo pipefail
cd "$(dirname "$0")/.."

version=${1:?usage: scripts/bundle.sh <version>}
build=$(git rev-list --count HEAD)
identity=${SIGN_IDENTITY:--}

swift build -c release --arch arm64 --arch x86_64
binary=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Spectrum

app=dist/Spectrum.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Spectrum"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist \
    > "$app/Contents/Info.plist"

codesign --force --options runtime --timestamp=none \
    --entitlements Resources/Spectrum.entitlements --sign "$identity" "$app"
codesign --verify --strict "$app"

zip="dist/Spectrum-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

# Drag-to-install disk image: the app next to a shortcut to /Applications.
dmg="dist/Spectrum-$version.dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname Spectrum -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null

echo "$app"
echo "$zip"
echo "$dmg"
