# IT Hub 0.9.6 audit — 20 October 2026

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
