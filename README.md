# IT Hub 1.0

A macOS menu bar app for IT support. It shows device health at a glance (FileVault, uptime, battery, storage, memory, software updates, network) and gives users one-click links, apps and scripts their IT team configures. Everything environment-specific comes from one JSON file or an MDM configuration profile. Requires macOS 13.6 or later.

Version 1.0 merges two earlier apps: IT Hub 0.9.6 (the health dashboard) and TopMenu (the JSON-driven launcher). The 0.9.x changelog is kept at the end of this file.

## Credits

This app is built on the IT-Hub work shared by Jorn de Koning on the Mac Admins Slack. His IT-Hub concept and implementation are the starting point for the health dashboard here; the configuration system, TopMenu merge, speed test and packaging were added on top of that foundation.

## Install

Build the installer and run it:

```
xcodebuild -scheme "IT Hub Direct Read" -configuration DirectRead build
./scripts/build-ithub-pkg.sh -a "path/to/IT Hub.app" -o build/ITHub.pkg
sudo installer -pkg build/ITHub.pkg -target /
```

The package places `IT Hub.app` in `/Applications`, a managed `menu.json` in `/Library/Application Support/IT Hub`, and a LaunchAgent in `/Library/LaunchAgents` that starts the app at login and keeps it running. Its postinstall restarts the app for every logged-in user, so an upgrade takes effect without a logout. `build/ITHubUninstall.pkg` (from `scripts/build-ithub-uninstall-pkg.sh`) removes all three; it does not touch per-user files or configuration profiles.

Upgrading from a 0.9.x build: those builds used a generated bundle identifier, and 1.0 uses the fixed `edu.slc.ithub`. macOS will not replace an app whose on-disk identifier differs, so the package carries a preinstall that removes the old copy and a postinstall that moves the new app into place if the installer had already planned around it. Because the identifier changed, macOS treats 1.0 as a new app for Location Services: users who had allowed the Wi-Fi name lookup see the prompt once more.

Two build schemes exist. **IT Hub Direct Read** runs outside App Sandbox and is the one to ship: it can read FileVault status and run update scans. **IT Hub** is sandboxed; FileVault and software-update checks show as unavailable there. Always pass `-configuration DirectRead` with the Direct Read scheme; `-configuration Release` silently swaps in the sandboxed entitlements. Builds are ad-hoc signed; Developer ID signing and notarization are the deployer's responsibility.

## What the dashboard shows

Click the laptop icon in the menu bar to open a 720-point panel. The icon outline is tinted by the worst monitored condition, and its hover text lists the reasons:

| Colour | Meaning |
|---|---|
| Red | A confirmed critical condition: FileVault off (per policy), storage or battery critically low, critical memory pressure |
| Orange | An actionable warning: an offered update or upgrade, uptime over the limit, low storage or battery, no configured network address |
| Grey | One or more required readings are unavailable or still checking, with nothing known to be wrong |
| Green | Every applicable check has a usable passing reading |

Priority is red, then orange, then grey, then green. Known problems stay visible even when unrelated checks are unknown, and green is not a compliance guarantee. The health policy section below describes how each condition is tuned.

The panel contains:

- **Needs attention**: shown only when there are reasons. Confirmed issues are listed individually; several unavailable checks collapse into one line with full hover detail.
- **macOS, FileVault, Uptime, Battery**: the four summary cards. FileVault off shows a red dot on its card regardless of policy. Uptime over the limit reads "A restart may speed up your Mac." Battery shows charge, cycle count and estimated capacity; Macs without an internal battery skip the check.
- **Device & Support**: computer name, model, chip, RAM and serial, read through `system_profiler` off the main thread. Copy Support Details copies a plain-text report to the clipboard; Preview opens it in its own window. The report carries device, macOS, FileVault, uptime, battery, storage, memory, network services with Wi-Fi name and addresses, internet reachability, the last speed test, and the software-update result with its check time. Nothing is uploaded; no Wi-Fi passwords or recovery keys are collected.
- **Storage** and **Memory**: free space with a usage bar; memory pressure, estimated use and swap, with an Activity Monitor link.
- **Services**: the Internet line, speed test, each network service with its address, and the Wi-Fi name with the expected-network comparison. Reading the Wi-Fi name needs Location Services; on first launch the app shows a one-time explanation window and asks once. Denied or restricted access shows an explanation with a link to Location Settings, and a denial never implies the user is on the wrong network. The prompt is skipped entirely when `wifiNameLookup` is `false`.
- **Software Update**: result of the last `softwareupdate` scan with Check now and Open Settings. Nothing is installed by the app. Labels say "update" or "upgrade" only when a recognisable major version is present.
- **Quick Actions**: the configured groups, see below.
- Footer: refresh cadence, the active settings source, and the Quit button if allowed.

Links that open System Settings or Activity Monitor hand activation to the destination and hide the panel first, so the menu bar panel never covers the app it just opened. All device checks are read-only: the app never changes system state.

## How settings load

All settings live in one document with this shape:

```json
{
  "functionIdentifier": "public.submenu",
  "settings": {
    "title": "Quick Actions",
    "branding": { "title": "IT Hub", "subtitle": "Device Health" },
    "policy": { "fileVaultOff": "critical", "uptimeWarningDays": 14 },
    "content": [ ...quick action groups... ]
  }
}
```

The app takes the first source that exists and parses, highest priority first, and uses it for everything (quick actions, policy and branding together; sources are not merged):

| Source | Who edits it | Scripts allowed |
|---|---|---|
| Configuration profile, preference domain `edu.slc.ithub` | MDM | Yes |
| `/Library/Application Support/IT Hub/menu.json` | Admin (root) | Yes |
| `~/Library/Application Support/IT Hub/menu.json` | The user | No |
| `menu.json` inside the app bundle | Ships with the app | Yes |

"Scripts allowed" means `public.script` rows are honoured; from the other sources they are silently dropped, so a user cannot add commands by editing their own file. A plain `defaults write edu.slc.ithub ...` is honoured for everything except scripts, because macOS does not report such values as managed.

Changes apply live. Both file folders and the files themselves are watched, so an in-place rewrite (`cp`, an MDM file push) and an editor that replaces the file both trigger a reload within about half a second. Profile installs and removals arrive through the preferences system and reload the same way. As a fallback, the configuration is re-read on the one-minute device refresh. The dashboard footer shows the active source: Configuration profile, Managed file, User file or Built-in defaults. A document that is not a JSON object is skipped and the next source is tried; a missing or invalid individual value keeps its default.

`examples/menu-slc.json` is a complete filled-in configuration for one campus. The bundled default contains only placeholders (`example.com` links, a `555` phone number) so the generic package can ship anywhere.

## Quick Actions

`settings.content` is an array of groups. Each group is a `public.submenu` whose own `settings.content` holds rows. Rows placed directly at the top level are collected into one group named after the root `settings.title`. A group with no visible rows is not shown.

| `functionIdentifier` | `settings` keys | What it does |
|---|---|---|
| `public.submenu` | `title`, `content`, optional `hidden` | A titled group of rows |
| `public.title` | `template` | A plain text row (hours, phone, email). Rows containing `{value}` are skipped: TopMenu used them for live values the health cards already show. |
| `public.link` | `url`, optional `title` (defaults to the URL), `icon`, `hidden` | Opens the URL in its default handler. The URL must have a scheme (`https:`, `mailto:` and so on). |
| `public.open.application` | `bundleIdentifier` and/or `name`, optional `title` (defaults to the name), `icon`, `hidden` | Opens the app and brings it to the foreground. The bundle identifier is tried first, then `name.app` in the user, local and system Applications folders. A missing app shows an alert. |
| `public.script` | `command`, `title`, optional `showOutput` (default `true`), `icon`, `hidden` | Runs the command with `/bin/zsh -c` from a trusted source only. One script runs at a time; others are disabled while it runs. Output is shown in an alert when `showOutput` is true, and always when the command fails or times out. The timeout is 60 seconds, after which the script's whole process group is stopped, including background jobs it started. |

Common keys: `icon` is an SF Symbol name; the defaults are `info.circle`, `link`, `app` and `terminal` by row type. `"hidden": true` on any group or row keeps it in the file but out of the panel; remove the key or set it to `false` to show it again. New groups and rows are added by appending entries in the same format.

TopMenu keys and plugins not carried over: `arguments`, `runOnStart`, `iconKind`, `badgeLabel`, `badgeColor`, `valueProvider`, and the `public.separator`, `public.quit`, `public.network.state` and `public.cloudflare.speed` identifiers. They are ignored if present. Network state and the speed test are built into the Services card instead.

## Health policy

`settings.policy` tunes the health rules. Every key is optional; a missing, negative or non-numeric value keeps the default. Severity words are `critical` (red), `warning` (orange) and `ignore` (no notice, no icon change); `attention` is accepted for warning, and `off` or `none` for ignore. Where a key says `0` disables a check, the card still shows the measured reading, it just never colours the icon or appears under Needs attention.

| Key | Default | Meaning |
|---|---|---|
| `fileVaultOff` | `critical` | What FileVault being off does to the menu bar icon and Needs attention. The FileVault card always shows the measured state with a red dot when off, whatever this says. `warning` and `ignore` cannot be applied to the card itself. |
| `uptimeWarningDays` | 14 | Days of uptime before the restart reminder. `0` disables it; the card then reads "Uptime check disabled". Fractional days work. |
| `storageWarningGB` | 20 | Free space (decimal GB) below which storage is orange. `0` disables. |
| `storageCriticalGB` | 5 | Free space below which storage is red. `0` disables. |
| `batteryWarningPercent` | 20 | Charge at or below this while on battery is orange. `0` disables. |
| `batteryCriticalPercent` | 10 | Charge at or below this while on battery is red. `0` disables. |
| `batteryHealthWarningPercent` | 80 | Maximum capacity below this percent of design capacity is orange. `0` disables. Cycle count is informational only. |
| `softwareUpdates` | `warning` | Severity of an available macOS update or upgrade. `ignore` for fleets where MDM owns updates. `critical` is not accepted. The Software Update card still shows the result. |
| `networkOffline` | `warning` | Severity when no network service has an address. `critical` or `ignore`. This is the configured-address check; the separate "Internet: Online/Offline" line in the Services card is informational and never affects the icon. |
| `updateScanMinutes` | 30 | Minutes between automatic `softwareupdate` scans. Minimum 1. Scans also run at launch, on wake if due, and on Check now. |
| `expectedWiFiSSID` | empty | Wi-Fi network name to compare the current connection against; shows "Expected Wi-Fi" or "Different from expected Wi-Fi" in the Services card. Empty disables the comparison. |
| `wifiNameLookup` | `true` | `false` hides the Wi-Fi name and the expected-network comparison, and the app never asks for Location Services permission. |
| `speedTestEnabled` | `true` | `false` hides Run speed test. |
| `speedTestSeconds` | 5 | Seconds per phase (download, then upload), clamped 2 to 20. Each phase runs at full link rate, so 5 s on a 200/40 Mbps link moves about 150 MB. |
| `allowQuit` | `true` | `false` hides the Quit button, for fleets where the LaunchAgent keeps the app running anyway. |

Fixed in code, on purpose: device readings refresh every minute, memory is sampled every 10 seconds, a clean update result older than one hour becomes unknown, memory-pressure severity follows the kernel's own levels, and the dashboard is 720 points wide.

## Branding

`settings.branding` sets `title` (default `IT Hub`) and `subtitle` (default `Device Health`). The title also appears in the menu bar hover text, on the Quit button and as the support report heading. Blank values keep the defaults.

## Configuration profile (Jamf and other MDM)

A profile delivers the same settings without a file and outranks every file. The JSON stays the source of truth: edit the JSON, regenerate the profile, upload it. Never edit a `.mobileconfig` by hand, because the next regeneration overwrites it.

### Create a profile

1. Start from a configuration file: `examples/menu-slc.json`, or a copy of it for another environment.
2. Edit the file. Quick Actions live in `settings.content`, health rules in `settings.policy`, header text in `settings.branding`; see the sections above for every key.
3. Generate the profile:

   ```
   python3 scripts/make-profile.py examples/menu-slc.json build/ITHub-SLC.mobileconfig --org "Sarah Lawrence College" --name "IT Hub (SLC)"
   ```

   `--org` fills the profile's organisation field and `--name` its display name in Jamf and in System Settings; both are cosmetic. The script validates the JSON and refuses a file without a `settings` object. Output goes to `build/`, which is not committed, so regenerate after cloning.

4. Check it if you like: `plutil -lint build/ITHub-SLC.mobileconfig`, or open it in a text editor. It is an XML plist with one custom-settings payload of type `edu.slc.ithub` whose `settings` dictionary mirrors the JSON.

### Deploy it

- **Jamf Pro**: Computers → Configuration Profiles → Upload, choose the `.mobileconfig`, scope it, save. Jamf shows it as a Custom Settings payload for the `edu.slc.ithub` domain. Other MDMs that accept a `.mobileconfig` upload work the same way.
- **One Mac, for testing**: double-click the file in Finder, then approve it in System Settings → Privacy & Security → Profiles. Remove it from the same place.

Either way macOS stores the payload at `/Library/Managed Preferences/edu.slc.ithub.plist`. The app switches to it within a second of it landing, the dashboard footer reads "Configuration profile", and removing the profile falls back to the files. Profile values are trusted, so `public.script` rows are honoured.

### Change settings later

Edit the JSON, regenerate, and upload the new `.mobileconfig` in Jamf as a replacement for the existing profile (edit the profile and upload again, or upload a new one with the same scope and retire the old). Macs pick up the change the next time the MDM pushes the profile; no app restart is needed. Alternatively, Jamf lets you edit the Custom Settings payload in place in its own editor: the keys are the same, but then Jamf holds the master copy instead of the JSON, so pick one place and stay with it.

### Profile versus file

| | Configuration profile | Managed `menu.json` |
|---|---|---|
| Delivered by | MDM | Installer package, MDM file push, or hand copy |
| User can override | No | Only by a per-user file for non-script rows |
| Scoping | Per MDM group | Whatever the package or push targets |
| Edited with | JSON then regenerate | Any text editor, `sudo` to save |
| Audit trail | In the MDM | None |

Use the profile for a managed fleet. Use the file for a single Mac, a lab, or anywhere without MDM.

## Services card: reachability and speed test

The Internet line uses `NWPathMonitor`: Online, Offline or Checking, with the card's dot following it. It is informational only. Run speed test measures the link the way WifiDiag's SpeedTestManager does: a warm-up request so TLS and HTTP/2 setup are not charged to the result, ten small latency probes reduced to a trimmed mean, six parallel download streams and eight parallel upload streams with adaptive chunk sizes, each phase bounded by `speedTestSeconds`, and a ramp-up window excluded from the figure. It runs against `speed.cloudflare.com` with browser-style headers, which Cloudflare requires for large transfers. Results show download, upload and latency with the time of measurement, appear in the support report, and are not kept across restarts. The test runs only on demand, never at launch.

## Packaging scripts

`scripts/build-ithub-pkg.sh` options: `-a` app bundle (required), `-j` menu.json to ship as the managed file (default `IT Hub/menu.json`; validated as JSON first), `-v` version (default: the app's `CFBundleShortVersionString`), `-i` package identifier (`edu.slc.ithub`), `-l` LaunchAgent label (`edu.slc.ithub.launcher`), `-o` output (`build/ITHub.pkg`). The package is built non-relocatable with the preinstall and postinstall described under Install.

`scripts/build-ithub-uninstall-pkg.sh` options: `-v`, `-i` (`edu.slc.ithub.uninstall`), `-l`, `-o` (`build/ITHubUninstall.pkg`). It verifies that its removal script was registered in the package and fails the build otherwise.

`scripts/make-profile.py source.json output.mobileconfig [--org NAME] [--name NAME]` as above.

## Validation

`python3 Validation/run.py` compiles the app sources with the Xcode toolchain for macOS 13 and runs 132 checks in 16 groups: command parsing and bounded execution, process-group timeout, uptime boundaries and storage arithmetic, memory pressure and usage, health priority and update naming, update freshness and network uncertainty, quick-action parsing (grouping, `{value}` skipping, URL validation, script filtering by trust, hidden flags, source ordering), speed maths and reachability labels, every policy key (FileVault, Wi-Fi, uptime, storage, battery, updates, network, feature switches, branding), and configuration-profile parsing. Both Xcode schemes build. The speed engine was also run end to end from a command-line harness, and the installed app was checked live for reachability, speed, hot reload of files, and profile precedence through staged managed preferences.

## Release history

### 1.0.0

- Merged TopMenu's JSON-driven quick actions, hot reload and installer packaging into IT Hub. TopMenu's info rows are dropped because the health cards show the same data.
- Every environment-specific rule moved into configuration: quick actions with add and hide, all health thresholds and severities, update scan interval, feature switches, branding, expected Wi-Fi.
- Configuration profile support with a generator for Jamf; stable `edu.slc.ithub` bundle identifier.
- Speed test rebuilt on WifiDiag's method; the previous single 2 MB request under-reported download about five-fold.
- Deployment target lowered from 14.6 to 13.6.
- Installer: non-relocatable package, old-identifier migration, agent restart after upgrade; uninstaller now actually registers its removal script.
- Script timeouts stop the whole process group; a managed config rewritten in place now triggers a reload.
- Sandboxed scheme gained the outgoing-network entitlement.

### 0.9.6

Reliability audit. Kept the measured FileVault result visible while its next read runs; kept the previous update result during a new scan and expired a clean result after one hour; treated unreadable network state as unknown rather than disconnected; removed the universal 1,000-cycle battery warning, since Apple rates cycles per model; locked temporary command output to the owner and used a monotonic timeout; stopped retaining a stale memory-pressure snapshot after a failed query.

### 0.9.5

Settings and Activity Monitor receive activation authority before they are opened, all IT Hub windows hide first, and a launch failure unhides the app and shows the error instead of leaving it hidden.

### 0.9.4

Destination activation centralised; the dashboard orders out before external apps open so its panel cannot cover them. Support Details Preview became its own retained window above the panel.

### 0.9.3

One shared computer symbol for the dashboard header and the menu bar icon, rendered through the same path so the shapes match.

### 0.9.2

Left column ordered Device & Support, Storage, Memory.

### 0.9.1

Visible Wi-Fi permission flow: a one-time onboarding window at startup for installations without a decision, an explicit Allow Wi-Fi Name action, and explanations for denied or restricted access. macOS keeps the user's decision; the app never resets it.

### 0.9

Quiet health summary: one shared model drives the dashboard and the menu bar; monitoring starts with the app; the icon outline is tinted by status instead of showing an uptime-only dot; Needs attention summarises reasons; updates are scanned at launch and every 30 minutes without installing anything.

### Earlier

Device & Support card with the support report (0.8); the hardware reader, zero-value formatting and the icon fix project predate the numbered history kept here.
