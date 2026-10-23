#!/usr/bin/env bash
# One command from source to everything a deployment needs:
#   build/IT Hub.app, build/ITHub-<name>.pkg, build/ITHubUninstall.pkg, build/ITHub-<name>.mobileconfig
set -euo pipefail
usage() { cat <<'U'
build-release.sh [-j menu.json] [-n name] [-O org] [-a "Developer ID Application: ..."] [-I "Developer ID Installer: ..."] [-k notarytool-keychain-profile] [-o build]

  -j  Configuration shipped as the managed file and turned into the profile (default: IT Hub/menu.json)
  -n  Short name used in output file names and the profile display name (default: default)
  -O  Organisation name written into the profile (default: IT)
  -a  Developer ID Application identity; signs the app with the hardened runtime (default: ad-hoc)
  -I  Developer ID Installer identity; signs both packages (default: unsigned)
  -k  notarytool keychain profile; notarizes and staples the installer package (needs -a and -I)
  -o  Output folder (default: build)

Examples:
  ./scripts/build-release.sh
  ./scripts/build-release.sh -j examples/menu-as.json -n AS -O "Ayala Solutions"
  ./scripts/build-release.sh -j examples/menu-as.json -n AS -O "Ayala Solutions" \
      -a "Developer ID Application: Ayala Solutions (TEAMID)" \
      -I "Developer ID Installer: Ayala Solutions (TEAMID)" -k as-notary
U
}
CONFIG="IT Hub/menu.json"; NAME="default"; ORG="IT"; APP_ID=""; PKG_ID=""; NOTARY=""; OUT="build"
while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help) usage; exit 0 ;; -j) CONFIG="$2"; shift 2 ;; -n) NAME="$2"; shift 2 ;; -O) ORG="$2"; shift 2 ;;
  -a) APP_ID="$2"; shift 2 ;; -I) PKG_ID="$2"; shift 2 ;; -k) NOTARY="$2"; shift 2 ;; -o) OUT="$2"; shift 2 ;;
  *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
esac; done
cd "$(dirname "$0")/.."
[[ -f "$CONFIG" ]] || { echo "Configuration not found: $CONFIG" >&2; exit 1; }
[[ -z "$NOTARY" || ( -n "$APP_ID" && -n "$PKG_ID" ) ]] || { echo "-k needs both -a and -I" >&2; exit 1; }
mkdir -p "$OUT"
DERIVED="$(mktemp -d)"; trap 'rm -rf "$DERIVED"' EXIT

echo "==> Validation"
python3 -I Validation/run.py >/dev/null && echo "    harness passed"

echo "==> Building IT Hub (Direct Read)"
if [[ -n "$APP_ID" ]]; then
    xcodebuild -project "IT Hub.xcodeproj" -scheme "IT Hub Direct Read" -configuration DirectRead -derivedDataPath "$DERIVED" \
        -destination "platform=macOS" CODE_SIGN_IDENTITY="$APP_ID" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" build 2>&1 | grep -E "error:|BUILD " || true
else
    xcodebuild -project "IT Hub.xcodeproj" -scheme "IT Hub Direct Read" -configuration DirectRead -derivedDataPath "$DERIVED" \
        -destination "platform=macOS" CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E "error:|BUILD " || true
fi
[[ -d "$DERIVED/Build/Products/DirectRead/IT Hub.app" ]] || { echo "Build failed" >&2; exit 1; }
rm -rf "$OUT/IT Hub.app"; cp -R "$DERIVED/Build/Products/DirectRead/IT Hub.app" "$OUT/IT Hub.app"
codesign --verify --deep --strict "$OUT/IT Hub.app" && echo "    signature verified ($([[ -n "$APP_ID" ]] && echo "$APP_ID" || echo ad-hoc))"
VERSION="$(defaults read "$(pwd)/$OUT/IT Hub.app/Contents/Info.plist" CFBundleShortVersionString)"

echo "==> Packages"
./scripts/build-ithub-pkg.sh -a "$OUT/IT Hub.app" -j "$CONFIG" -o "$OUT/ITHub-$NAME.pkg" >/dev/null
./scripts/build-ithub-uninstall-pkg.sh -v "$VERSION" -o "$OUT/ITHubUninstall.pkg" >/dev/null
if [[ -n "$PKG_ID" ]]; then
    for pkg in "$OUT/ITHub-$NAME.pkg" "$OUT/ITHubUninstall.pkg"; do
        productsign --sign "$PKG_ID" --timestamp "$pkg" "$pkg.signed" >/dev/null && mv "$pkg.signed" "$pkg"
    done
    echo "    packages signed ($PKG_ID)"
fi
if [[ -n "$NOTARY" ]]; then
    echo "==> Notarizing installer (this waits for Apple)"
    xcrun notarytool submit "$OUT/ITHub-$NAME.pkg" --keychain-profile "$NOTARY" --wait
    xcrun stapler staple "$OUT/ITHub-$NAME.pkg"
fi

echo "==> Profile"
python3 -I scripts/make-profile.py "$CONFIG" "$OUT/ITHub-$NAME.mobileconfig" --org "$ORG" --name "IT Hub ($NAME)" >/dev/null
plutil -lint "$OUT/ITHub-$NAME.mobileconfig" >/dev/null

echo
echo "Release $VERSION ($NAME) in $OUT/:"
for f in "IT Hub.app" "ITHub-$NAME.pkg" "ITHubUninstall.pkg" "ITHub-$NAME.mobileconfig"; do
    printf "  %-28s %s\n" "$f" "$(du -sh "$OUT/$f" | cut -f1)"
done
cat <<'N'

Deploy: upload the .pkg as a policy and the .mobileconfig as a configuration profile, scoped to the same Macs.
Unsigned builds need Gatekeeper approval on each Mac; pass -a/-I/-k for a signed, notarized release.
N
