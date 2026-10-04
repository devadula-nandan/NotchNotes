#!/bin/bash
# Dev mode: rebuild and relaunch NotchNotes whenever a source file changes.
set -uo pipefail
cd "$(dirname "$0")"

BIN=".build/debug/NotchNotes"
PID=""

# Modification times of everything that affects the build
fingerprint() {
    find Sources Package.swift -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort
}

stop_app() {
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
    fi
    PID=""
}

trap 'stop_app; exit 0' INT TERM
trap 'stop_app' EXIT

# The installed copy would overlap the dev build and share its notes file
if pgrep -f "NotchNotes.app/Contents/MacOS/NotchNotes" >/dev/null; then
    echo "⏹  Quitting installed NotchNotes.app"
    osascript -e 'tell application id "com.local.notchnotes" to quit' >/dev/null 2>&1
    sleep 1
fi

while true; do
    LAST="$(fingerprint)"

    echo "🔨 Building..."
    if swift build 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" ; [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        stop_app
        "$BIN" &
        PID=$!
        echo "🚀 Running (pid $PID). Watching for changes, Ctrl+C to stop"
    else
        # Keep the previous build running so the app doesn't vanish on a typo
        echo "❌ Build failed. Fix the error and save again"
    fi

    while [[ "$(fingerprint)" == "$LAST" ]]; do
        sleep 0.5
    done
    echo "♻️  Change detected"
done
