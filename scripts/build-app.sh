#!/bin/bash
# Fabrique OptiMac.app (universelle Intel + Apple Silicon) puis OptiMac.dmg.
set -euo pipefail
VERSION="${VERSION:-1.2.0}"
BUILD="${BUILD:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --arch arm64 --arch x86_64 2>&1 | tee build.log
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/OptiMac"

APP="dist/OptiMac.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/OptiMac"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/logo.png "$APP/Contents/Resources/logo.png"
cp -R Resources/Sounds "$APP/Contents/Resources/Sounds"
cp Resources/signatures.json "$APP/Contents/Resources/signatures.json"

# Icône de l'application à partir du logo
ICONSET="dist/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# macOS 11 n'a pas le moteur async/await de Swift : on l'embarque.
TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib"
CONC="$(find "$TOOLCHAIN" -path '*swift-5.5/macosx/libswift_Concurrency.dylib' 2>/dev/null | head -1 || true)"
if [ -n "$CONC" ]; then cp "$CONC" "$APP/Contents/Frameworks/"; echo "Concurrency embarqué : $CONC"; else echo "ATTENTION : libswift_Concurrency introuvable"; fi

# Signature ad hoc (le compte Apple Developer viendra plus tard)
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
lipo -info "$APP/Contents/MacOS/OptiMac"
# Contrôle de compatibilité : version minimale de macOS inscrite dans le programme (attendu : 11.0).
for A in arm64 x86_64; do echo "minos $A : $(vtool -arch $A -show-build "$APP/Contents/MacOS/OptiMac" | awk '/minos/{print $2}')"; done
otool -L "$APP/Contents/MacOS/OptiMac" | grep -i concurrency || true

# Image disque avec raccourci vers Applications
STAGE="dist/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "OptiMac" -srcfolder "$STAGE" -ov -format UDZO "dist/OptiMac.dmg"
# Ancien nom conservé : les liens de téléchargement déjà diffusés continuent de fonctionner.
cp dist/OptiMac.dmg dist/OptiMac-1.0.0.dmg
ls -la dist
