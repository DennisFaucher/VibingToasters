#!/bin/bash
#
# Assembles FlyingToasters.saver from the SwiftPM build products.
#
#   Tools/make-saver.sh             build ./FlyingToasters.saver
#   Tools/make-saver.sh --install   build, then install to ~/Library/Screen Savers
#
# A .saver is a loadable bundle, not an app: Contents/MacOS holds a dylib and
# Contents/Resources holds the precompiled Metal library. macOS loads it as a
# plugin inside legacyScreenSaver.appex.
#
# The shader is also compiled here rather than only at runtime, because the
# sandboxed legacyScreenSaver host may not reach MTLCompilerService. The renderer
# tries the inline source first and falls back to this metallib.

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
BUNDLE="FlyingToasters.saver"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

echo "==> Extracting shader source from ShaderSource.swift"
python3 - "$TMP/FlyingToastersShaders.metal" <<'PY'
import sys
src = open('Sources/FlyingToastersKit/ShaderSource.swift').read()
marker = 'let metalShaderSource = """'
start = src.index(marker) + len(marker)
end = src.index('"""', start)
open(sys.argv[1], 'w').write(src[start:end])
PY

echo "==> Compiling shader"
xcrun -sdk macosx metal -O -c "$TMP/FlyingToastersShaders.metal" -o "$TMP/Shaders.air"
xcrun -sdk macosx metallib "$TMP/Shaders.air" -o "$TMP/FlyingToastersShaders.metallib"

echo "==> Assembling bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp ".build/$CONFIG/libFlyingToastersSaver.dylib" "$BUNDLE/Contents/MacOS/FlyingToasters"
cp "$TMP/FlyingToastersShaders.metallib" "$BUNDLE/Contents/Resources/"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>FlyingToasters</string>
	<key>CFBundleIdentifier</key>
	<string>com.faucherd.flyingtoasters.saver</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Flying Toasters</string>
	<key>CFBundleDisplayName</key>
	<string>Flying Toasters</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSPrincipalClass</key>
	<string>FlyingToastersSaverView</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$BUNDLE/Contents/MacOS/FlyingToasters"
codesign --force --sign - "$BUNDLE"
codesign --verify --verbose=1 "$BUNDLE" 2>&1 | sed 's/^/    /'

if [ "${1:-}" = "--install" ]; then
    DEST="$HOME/Library/Screen Savers"
    echo "==> Installing to $DEST"
    mkdir -p "$DEST"
    rm -rf "$DEST/$BUNDLE"
    cp -R "$BUNDLE" "$DEST/"
    # Make the host reload the plugin list.
    killall legacyScreenSaver 2>/dev/null || true
    echo "    done — pick it in System Settings > Wallpaper > Screen Saver (under Other)"
fi

echo "==> Built $BUNDLE"
