# UsageFairy for macOS

The Mac version keeps the Windows-style floating widget: draggable app logos,
segmented allowance and week bars, used/remaining settings, and a transparent
minimal mode. It shows open apps (and Codex CLI when a reading is available).
Click `%` in the menu bar to show or hide it. Right-click the icon
or widget for settings and Quit. The position and settings are saved locally.
The menu-bar control replaces Windows taskbar badges; other apps' Dock icons
are not modified.

## Download

Download the Intel (`macos-x64`) or Apple Silicon (`macos-arm64`) installer from
[GitHub Releases](https://github.com/TheGP/UsageFairy/releases/latest).
Open the DMG and drag UsageFairy to Applications. The ZIP contains the same app.
Node is bundled; no development tools or source checkout are required.

The app is ad-hoc signed, not Apple-notarized. The first launch may need approval
in System Settings → Privacy & Security. Readings/history go to
`~/Library/Application Support/UsageFairy`; credentials remain in their existing
provider locations.

## Run from source

Requires macOS 11+, Node.js 18+, and the Xcode Command Line Tools with Swift.

```sh
cd ~/Websites/UsageFairy
bash macos/launch.sh
```

The script builds a native AppKit app under ignored `data/macos/`, signs it
locally, and opens it without a terminal window. `--build-only` compiles without
opening the widget. No npm packages are required. It does not install a login
item automatically.

## Readings

- Codex uses the installed Codex CLI or Codex app's `app-server` rate-limit read.
  Set `CODEX_BIN` to override its executable path.
- ZCode uses the credentials already installed on this Mac and the same
  read-only usage endpoint as Windows. No credentials are copied from Windows.
- Claude reads the **visible Usage view** through macOS Accessibility. Choose
  **Enable Claude usage reading…**, allow UsageFairy in System Preferences →
  Security & Privacy → Privacy → Accessibility, and open Claude's Usage view.
  It does not click through Claude or make a Claude usage API call. An existing
  local usage-history file can provide cached readings when available.

Refresh is every 30 seconds. Orange dots mean cached readings. Missing readings
show `--`; a missing reset time also shows `--` in the week bar. Hover over the
widget for provider errors, or turn off minimal mode for status labels. Week
bars show time elapsed toward the provider's reported weekly reset.

## Checks

```sh
node --test macos/data-platform.test.cjs
data/macos/UsageFairy.app/Contents/MacOS/UsageFairy --self-test
```

The existing Windows launchers and taskbar widget continue to use the same
poller. Mac support does not install Windows startup scripts or transfer AI
login files.

## Releases

Pushing a version tag such as `v0.1.0` builds Intel and Apple Silicon apps in
GitHub Actions, tests the bundled runtime, and publishes DMG/ZIP installers
with SHA-256 checksums. A failed build prevents release publication.

To build locally, use an official Node.js distribution (with its LICENSE), then
run `bash macos/build-release.sh v0.1.0`. Only the app binary, poller, runtime,
license, and documentation enter the bundle; local data is excluded.
