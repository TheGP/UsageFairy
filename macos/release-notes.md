Native macOS floating usage widget, with a compact transparent layout, draggable
app logos, segmented allowance/week bars, and used/remaining settings.

Download **macos-arm64** for Apple Silicon or **macos-x64** for Intel. Open the
DMG and drag UsageFairy to Applications, or unzip the ZIP and move the app there.
Node.js is included; no separate runtime or source checkout is required.

The app is ad-hoc signed, not Apple-notarized. macOS may require first-launch
approval in System Settings → Privacy & Security. See Apple's instructions:
https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac

Click `%` in the menu bar to show or hide the widget; right-click for settings.
Local readings and history are stored in `~/Library/Application Support/UsageFairy`.
Login files and credentials are never included in release downloads.

- Codex uses your existing local Codex sign-in; quota reads need a valid session.
- ZCode uses your existing local Coding Plan credential.
- Claude needs Accessibility permission for UsageFairy and its Usage view open.

This release adds macOS support. The existing Windows scripts remain available
in the repository. Readings which cannot be obtained show `--`.
