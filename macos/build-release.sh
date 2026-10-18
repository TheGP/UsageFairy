#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?Usage: bash macos/build-release.sh v1.2.3}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must have the form v1.2.3" >&2
  exit 1
fi
case "$(uname -m)" in
  x86_64) arch=x64; swift_arch=x86_64 ;;
  arm64) arch=arm64; swift_arch=arm64 ;;
  *) echo "Unsupported Mac architecture" >&2; exit 1 ;;
esac
node="$(command -v node)"
if [[ "$("$node" -p 'process.arch')" != "$arch" ]]; then
  echo "Node architecture does not match the build host" >&2
  exit 1
fi
license="$(dirname "$node")/../LICENSE"
if [[ ! -f "$license" ]]; then
  echo "Node distribution LICENSE was not found" >&2
  exit 1
fi

out="$root/dist"
mkdir -p "$out"
stage="$(mktemp -d "$out/stage.XXXXXX")"
app="$stage/UsageFairy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -swift-version 5 -target "$swift_arch-apple-macosx11.0" \
  -framework Cocoa -framework ApplicationServices \
  "$root/macos/UsageFairy.swift" -o "$app/Contents/MacOS/UsageFairy"
cp "$node" "$app/Contents/Resources/node"
cp "$license" "$app/Contents/Resources/Node-LICENSE.txt"
cp "$root/TaskbarAllowancesData.js" "$app/Contents/Resources/TaskbarAllowancesData.js"
cp "$root/macos/README.md" "$app/Contents/Resources/README.md"
"$node" --version > "$app/Contents/Resources/Node-version.txt"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.usagefairy.macos</string>
<key>CFBundleName</key><string>UsageFairy</string>
<key>CFBundleDisplayName</key><string>UsageFairy</string>
<key>CFBundleExecutable</key><string>UsageFairy</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$version</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/Resources/node"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/UsageFairy" --self-test
"$app/Contents/MacOS/UsageFairy" --check-bundle

name="UsageFairy-v$version-macos-$arch"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/$name.zip"
ln -s /Applications "$stage/Applications"
hdiutil create -volname UsageFairy -srcfolder "$stage" -format UDZO "$out/$name.dmg"
(
  cd "$out"
  shasum -a 256 "$name.zip" "$name.dmg" > "$name.sha256"
)
echo "Release assets: $out"
