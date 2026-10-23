#!/usr/bin/env bash
# Build a payload-free package whose postinstall unloads the LaunchAgent and removes the app and managed config.
set -euo pipefail
usage() { echo "build-ithub-uninstall-pkg.sh [-v version] [-i identifier] [-l launchagent.label] [-o output.pkg]"; }
VERSION="1.0.0"; IDENTIFIER="com.ayala.solutions.ithub.uninstall"; LABEL="com.ayala.solutions.ithub.launcher"; OUTPUT="build/ITHubUninstall.pkg"
while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help) usage; exit 0 ;; -v) VERSION="$2"; shift 2 ;; -i) IDENTIFIER="$2"; shift 2 ;; -l) LABEL="$2"; shift 2 ;;
  -o) OUTPUT="$2"; shift 2 ;; *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
esac; done
DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT
mkdir -p "$DIR/Scripts" "$(dirname "$OUTPUT")"
cat > "$DIR/Scripts/postinstall" <<POST
#!/bin/bash
LABEL="$LABEL"
launchctl bootout system/"\$LABEL" >/dev/null 2>&1 || true
for uid in \$(dscl . -list /Users UniqueID | awk '\$2 >= 500 { print \$2 }'); do
  launchctl bootout gui/"\$uid"/"\$LABEL" >/dev/null 2>&1 || true
done
pkill -x "IT Hub" >/dev/null 2>&1 || true
rm -f "/Library/LaunchAgents/\$LABEL.plist"
rm -rf "/Library/Application Support/IT Hub" "/Applications/IT Hub.app"
exit 0
POST
chmod +x "$DIR/Scripts/postinstall"
# pkgbuild looks for postinstall directly inside the --scripts directory.
pkgbuild --identifier "$IDENTIFIER" --version "$VERSION" --nopayload --scripts "$DIR/Scripts" "$OUTPUT"
# Fail loudly if the package did not register the script.
CHECK="$(mktemp -d)"; pkgutil --expand "$OUTPUT" "$CHECK/expanded" >/dev/null
grep -q "<postinstall" "$CHECK/expanded/PackageInfo" || { echo "postinstall was not registered in $OUTPUT" >&2; rm -rf "$CHECK"; exit 1; }
rm -rf "$CHECK"
echo "Built $OUTPUT"
