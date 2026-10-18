#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/data/macos/UsageFairy.app"
binary="$app/Contents/MacOS/UsageFairy"
source="$root/macos/UsageFairy.swift"
node="$(command -v node)"

if [[ ! -x "$binary" || "$source" -nt "$binary" || "$root/macos/launch.sh" -nt "$binary" ]]; then
  mkdir -p "$app/Contents/MacOS"
  swiftc -O -framework Cocoa -framework ApplicationServices "$source" -o "$binary"
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.usagefairy.macos</string>
<key>CFBundleName</key><string>UsageFairy</string>
<key>CFBundleDisplayName</key><string>UsageFairy</string>
<key>CFBundleExecutable</key><string>UsageFairy</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>11.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
  codesign --force --sign - "$app"
fi

if [[ "${1:-}" == "--build-only" ]]; then
  echo "Built $app"
  exit 0
fi

open "$app" --args --repo "$root" --node "$node"
