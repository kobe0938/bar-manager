#!/bin/zsh
# Builds Bar Manager.app into build/ as a universal binary.
#   --install   copy it to ~/Applications and launch it
#   --zip       also write build/Bar-Manager.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

app="build/Bar Manager.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

[[ -f icon.icns ]] || swift make-icon.swift

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macosx13.0" \
        -o "build/bar-manager-$arch" sources/main.swift
done
lipo -create build/bar-manager-arm64 build/bar-manager-x86_64 -output "$app/Contents/MacOS/bar-manager"
rm build/bar-manager-arm64 build/bar-manager-x86_64
cp info.plist "$app/Contents/Info.plist"
cp icon.icns "$app/Contents/Resources/icon.icns"
print -n "APPL????" > "$app/Contents/PkgInfo"
codesign --force --sign - "$app"
print "built $app"

for flag in "$@"; do
    case "$flag" in
        --install)
            dest="$HOME/Applications/Bar Manager.app"
            mkdir -p "$HOME/Applications"
            pkill -x bar-manager || true
            rm -rf "$dest"
            ditto "$app" "$dest"
            open "$dest"
            print "installed and launched $dest"
            ;;
        --zip)
            rm -f build/Bar-Manager.zip
            ditto -c -k --keepParent "$app" build/Bar-Manager.zip
            print "wrote build/Bar-Manager.zip"
            ;;
    esac
done
