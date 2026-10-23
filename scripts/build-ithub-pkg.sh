#!/usr/bin/env bash
# Build an MDM-ready installer: IT Hub.app, a managed Quick Actions menu.json, and a LaunchAgent that starts the app at login.
set -euo pipefail
usage() { cat <<'U'
build-ithub-pkg.sh [-v version] [-i identifier] [-a path/to/IT Hub.app] [-j menu.json] [-l launchagent.label] [-o output.pkg]
Defaults: version and identifier from the app's Info.plist, menu "IT Hub/menu.json", label <identifier>.launcher, output build/ITHub.pkg
U
}
APP=""; JSON="IT Hub/menu.json"; IDENTIFIER=""; LABEL=""; OUTPUT="build/ITHub.pkg"; VERSION=""
while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help) usage; exit 0 ;; -v) VERSION="$2"; shift 2 ;; -i) IDENTIFIER="$2"; shift 2 ;; -a) APP="$2"; shift 2 ;;
  -j) JSON="$2"; shift 2 ;; -l) LABEL="$2"; shift 2 ;; -o) OUTPUT="$2"; shift 2 ;; *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
esac; done
[[ -d "$APP" ]] || { echo "Pass -a with a built IT Hub.app (Product > Archive, or xcodebuild -scheme 'IT Hub Direct Read')." >&2; exit 1; }
[[ -f "$JSON" ]] || { echo "menu.json not found at $JSON" >&2; exit 1; }
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$JSON" || { echo "menu.json is not valid JSON" >&2; exit 1; }
VERSION="${VERSION:-$(defaults read "$(cd "$APP" && pwd)/Contents/Info.plist" CFBundleShortVersionString)}"
BUNDLE_ID="$(defaults read "$(cd "$APP" && pwd)/Contents/Info.plist" CFBundleIdentifier)"
IDENTIFIER="${IDENTIFIER:-$BUNDLE_ID}"
LABEL="${LABEL:-$BUNDLE_ID.launcher}"
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/Applications" "$ROOT/Library/Application Support/IT Hub" "$ROOT/Library/LaunchAgents" "$(dirname "$OUTPUT")"
cp -R "$APP" "$ROOT/Applications/IT Hub.app"
cp "$JSON" "$ROOT/Library/Application Support/IT Hub/menu.json"
cat > "$ROOT/Library/LaunchAgents/$LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/Applications/IT Hub.app/Contents/MacOS/IT Hub</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
# Without this the installer may "relocate" the app onto any existing copy with the same bundle
# identifier that Spotlight knows about (a developer's DerivedData, an old copy in ~/Downloads)
# and leave /Applications untouched while still reporting success.
# Builds before 1.0 used a generated bundle identifier. The installer will not replace a bundle
# whose identifier differs from the package, so remove such a copy first or the upgrade lands
# beside it in "IT Hub.localized" while reporting success.
SCRIPTS="$(mktemp -d)"
cat > "$SCRIPTS/preinstall" <<PRE
#!/bin/bash
APP="/Applications/IT Hub.app"
if [[ -d "\$APP" ]]; then
    current="\$(defaults read "\$APP/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)"
    if [[ "\$current" != "$BUNDLE_ID" ]]; then
        pkill -x "IT Hub" >/dev/null 2>&1 || true
        rm -rf "\$APP"
    fi
fi
# Retire LaunchAgents from earlier identifiers that still point at this app.
for plist in /Library/LaunchAgents/*.plist; do
    [[ -f "\$plist" ]] || continue
    grep -q "IT Hub.app/Contents/MacOS/IT Hub" "\$plist" || continue
    label="\$(defaults read "\$plist" Label 2>/dev/null || true)"
    [[ -n "\$label" && "\$label" != "$LABEL" ]] || continue
    for uid in \$(dscl . -list /Users UniqueID | awk '\$2 >= 500 { print \$2 }'); do
        launchctl bootout "gui/\$uid/\$label" >/dev/null 2>&1 || true
    done
    rm -f "\$plist"
done
exit 0
PRE
chmod +x "$SCRIPTS/preinstall"
# The installer plans its paths before preinstall runs. If an old-identifier copy was still at the
# destination at planning time, the new app lands in "IT Hub.localized"; move it into place, then
# restart the LaunchAgent for every logged-in user so the upgrade takes effect without a logout.
cat > "$SCRIPTS/postinstall" <<POST
#!/bin/bash
APP="/Applications/IT Hub.app"
for stray in /Applications/IT\ Hub*.localized; do
    if [[ -d "\$stray/IT Hub.app" ]]; then
        rm -rf "\$APP"
        mv "\$stray/IT Hub.app" "\$APP"
    fi
    # Whether or not an app was inside, drop the folder once only the installer's marker remains.
    if [[ -z "\$(find "\$stray" -mindepth 1 -not -path '*/.localized*' -print -quit 2>/dev/null)" ]]; then
        rm -rf "\$stray"
    fi
done
for uid in \$(dscl . -list /Users UniqueID | awk '\$2 >= 500 { print \$2 }'); do
    # A freshly installed or renamed agent is not yet loaded in the session: bootstrap first (no-op if loaded).
    launchctl bootstrap "gui/\$uid" "/Library/LaunchAgents/$LABEL.plist" >/dev/null 2>&1 || true
    launchctl kickstart -k "gui/\$uid/$LABEL" >/dev/null 2>&1 || true
done
exit 0
POST
chmod +x "$SCRIPTS/postinstall"
COMPONENTS="$ROOT.components.plist"
pkgbuild --analyze --root "$ROOT" "$COMPONENTS" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$COMPONENTS"
# pkgbuild's ownership pass prints "write: Permission denied" for files it cannot chown in the
# temporary root; the package is still correct, so hide that one line.
pkgbuild --root "$ROOT" --component-plist "$COMPONENTS" --scripts "$SCRIPTS" --identifier "$IDENTIFIER" --version "$VERSION" --ownership recommended "$OUTPUT" 2> >(grep -v '^write: Permission denied' >&2)
rm -f "$COMPONENTS"; rm -rf "$SCRIPTS"
echo "Built $OUTPUT (version $VERSION). Managed config: /Library/Application Support/IT Hub/menu.json"
