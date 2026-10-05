#!/bin/bash
# Runs the tests. With full Xcode this is just `swift test`; with only the Command Line Tools,
# SwiftPM doesn't find the bundled Testing framework on its own, so it is pointed at it.
set -euo pipefail
cd "$(dirname "$0")"

F="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools* && -d "$F/Testing.framework" ]]; then
    swift test -Xswiftc -F"$F" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" "$@"
else
    swift test "$@"
fi
