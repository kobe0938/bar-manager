#!/bin/zsh
# Builds Bar Manager.app into build/. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

app="build/Bar Manager.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

[[ -f icon.icns ]] || swift make-icon.swift

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
    -o "$app/Contents/MacOS/bar-manager" sources/main.swift
cp info.plist "$app/Contents/Info.plist"
cp icon.icns "$app/Contents/Resources/icon.icns"
print -n "APPL????" > "$app/Contents/PkgInfo"
codesign --force --sign - "$app"
print "built $app"

if [[ "${1:-}" == "--install" ]]; then
    dest="$HOME/Applications/Bar Manager.app"
    mkdir -p "$HOME/Applications"
    pkill -x bar-manager || true
    rm -rf "$dest"
    ditto "$app" "$dest"
    open "$dest"
    print "installed and launched $dest"
fi
