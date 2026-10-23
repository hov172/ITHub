# IT Hub 1.0.0 audit — 22 October 2026

## Corrected during the 1.0 work

- Uninstall package built with `--scripts` pointing one level too high, so its removal script was packaged as a helper and never registered; packages reported success while removing nothing. Fixed and the build now verifies registration (Codex adversarial review finding).
- Script timeouts only signalled the shell, leaving background children running and allowing a retry to overlap them. The whole process group is now stopped and confirmed empty before another script may run (Codex adversarial review finding).
- Config watcher observed only the folder, so an in-place rewrite of `menu.json` (what `cp` and MDM file pushes do) never reloaded. Files are watched as well, and watchers are re-armed after every reload.
- Speed test download counted bytes through one task per delegate callback; thousands were still pending when totals were read, giving 0 Mbps. Counting is synchronous per stream. Cloudflare also answers 403 to large requests without browser headers, and that one-byte error body was being counted as data.
- Building the Direct Read scheme with `-configuration Release` silently used the sandboxed entitlements; documented, and the sandboxed build gained the network entitlement.
- Changing the bundle identifier made the installer place the new app beside the old one in `IT Hub.localized` while reporting success. The package now carries migration scripts and is marked non-relocatable.
- A stray `\n` appended to the bundled `menu.json` was caught by the package script's JSON check; the build chain now fails on it instead of reusing the previous package.

## Validation

- IT Hub Direct Read and IT Hub (sandboxed): Xcode builds succeeded at deployment target 13.6.
- 132 focused regression checks in 16 groups passed (`python3 Validation/run.py`).
- Installed app checked live: reachability, speed test (208 and 161 Mbps down on a link where the old method read 31), managed-file hot reload, configuration-profile precedence via staged managed preferences, postinstall agent restart.

## Remaining limitations

- Builds are ad-hoc signed. Developer ID signing and notarization are still required for distribution outside a managed fleet.
- The dashboard panel could not be driven by scripted accessibility clicks in testing, so hidden-row and branding changes were verified through the harness and the menu bar icon rather than panel screenshots.
- Speed test results are not persisted and the test is not run automatically; a scheduled test would need a data budget decision.
- The configuration profile path was verified by writing managed preferences directly, which is how MDM delivers them, not through a Jamf tenant.
- Office-network or location detection is still not implemented; `expectedWiFiSSID` is a name comparison only.

# IT Hub 0.9.6 audit (previous release) — 20 October 2026

## Corrected

- Preserve the measured FileVault result while its next read runs, so a warning does not vanish during the minute refresh.
- Keep the previous update result during a new scan; show scan progress separately. A confirmed no-update result older than one hour becomes unknown rather than remaining green. Refresh device readings on wake and request an update scan when needed.
- Treat unreadable network state as unknown rather than assuming a disconnection. A confirmed connected service still counts as connected.
- Remove the universal 1,000-cycle battery warning: Apple specifies cycle limits by model. Cycle count remains informational; existing capacity and charge warnings remain.
- Restrict temporary command-output files to their owner (0600), create exclusively, and remove after reading. Use a monotonic command timeout so changes to the system clock cannot prolong it.
- Avoid retaining an old memory-pressure snapshot after the pressure query fails unless an actual pressure event supports it.
- Remove the unused alternative menu-icon implementation and disable the debug dylib payload in app builds.

## Validation

- IT Hub Direct Read: Xcode build succeeded.
- IT Hub (sandboxed): Xcode build succeeded.
- 56 focused regression checks passed: update/FileVault parsing and failure handling, command timeout, storage arithmetic, uptime thresholds, memory calculations, health priority, update freshness, and unreadable network state.
- Reproduce checks with `python3 Validation/run.py` on an Apple Silicon Mac with Xcode installed at /Applications/Xcode.app.
- Xcode emitted SDK macro, Simulator-service and unused App Intents metadata diagnostics. These did not prevent either macOS build; this is not a warning-free toolchain claim.

## Remaining limitations

- This is a source and build audit, not a full interactive test of the running app. The user confirmed Settings and Activity Monitor foreground launching in 0.9.5; that handoff is preserved.
- Location permission and SSID visibility must still be checked in the installed app. A permission denial or unreadable SSID must not imply the user is on the wrong network.
- Memory use is an estimate, and the initial pressure snapshot uses a best-effort sysctl in addition to pressure events. Unsupported reads show unknown.
- Software Update shows the result returned by macOS; an unavailable scan remains unknown. A clean scan is time-limited, not a promise that the device will remain current.
- Quick Actions still need actual support URLs/configuration. Office-network/location detection is not configured.
- The DMG app is locally/ad-hoc signed, not Developer ID signed or notarized. It is a local test build, not a completed enterprise deployment package.
