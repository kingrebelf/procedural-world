#!/usr/bin/env bash
# Starts the Procedural World dedicated server (macOS). Double-click in Finder, or run
# from Terminal. Settings: server.cfg beside this file (made on first start).
cd "$(dirname "$0")"
APP="Procedural World Server.app"
# Downloaded apps are quarantined; the server isn't notarized, so lift that once.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
exec "./$APP/Contents/MacOS/Procedural World" --headless -- --server "$@"
