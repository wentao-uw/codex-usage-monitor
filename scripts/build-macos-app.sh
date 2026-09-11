#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PLUGIN_ROOT="${SCRIPT_DIR:h}"
PACKAGE_ROOT="$PLUGIN_ROOT/macos/CodexUsageMenuBar"
APP_ROOT="$PLUGIN_ROOT/dist/Codex Usage Monitor.app"
CONTENTS="$APP_ROOT/Contents"

swift build --package-path "$PACKAGE_ROOT" -c release

rm -rf "$APP_ROOT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
install -m 755 "$PACKAGE_ROOT/.build/release/CodexUsageMenuBar" "$CONTENTS/MacOS/Codex Usage Monitor"
install -m 644 "$PACKAGE_ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP_ROOT"

echo "$APP_ROOT"
