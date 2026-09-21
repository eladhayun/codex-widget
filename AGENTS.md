# Codex Widget — maintainer and agent guide

## Project and scope

This repository builds an unofficial, MIT-licensed personal native macOS menu bar app that monitors Codex token activity and ChatGPT-plan quotas. Repository: `https://github.com/eladhayun/codex-widget`, default branch `main`. It is not affiliated with or endorsed by OpenAI or Anthropic.

The app uses the existing local Codex login. It has no backend, API key configuration, model calls, desktop WidgetKit extension, or App Store distribution. Do not add these features implicitly when maintaining the monitor.

The user explicitly chose a menu bar app for their own Mac. Later design requests replaced the original text status item with an icon and adopted the supplied Claude terminal screenshots as a visual reference. It still monitors **Codex**, not Claude.

## Build, run, and test

Work from the repository root. Requires macOS 14+, Swift 5.9+ for the package, and Xcode 16+ for the synchronized-folder Xcode project. Development was verified with Xcode 27 / Swift 6.4 and Codex CLI 0.155.1 on Apple Silicon.

```sh
make help
make test
make build
make check
make open
```

- `make test` runs the Swift Package Manager XCTest targets, including offscreen native view renders.
- `make build` compiles a release executable, assembles `build/Codex Widget.app`, copies `Resources/Info.plist`, the app icon, and the MIT license, and ad-hoc signs it with `codesign --sign -`.
- `make check` runs the executable's `--check` diagnostic mode. It reads account/usage information without creating a model task. It prints availability, daily bucket dates, and the local rolling total when needed; it does not print account identifiers or credentials.
- `make open` builds and opens the application. To launch an existing build without recompiling, use `open "build/Codex Widget.app"`.

From the repository root, launch the built app with:

```sh
open "build/Codex Widget.app"
```

Double-clicking the bundle in Finder also works. The executable inside `Contents/MacOS/CodexWidget` can run directly, but opening the app bundle is the normal user workflow. Look for the terminal icon in the menu bar; there is no Dock icon (`LSUIElement=true`). Quit from the panel. The app can be copied to Applications manually. It is not notarized.

Open `CodexWidget.xcodeproj` for Xcode development. Its synchronized `Sources` folder compiles the core and UI into one app module. SwiftPM compiles `UsageCore` separately, so UI files use conditional `canImport(UsageCore)` imports. Keep both build paths working.

```sh
xcodebuild -project CodexWidget.xcodeproj -scheme CodexWidget \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/Xcode build
```

The development machine has emitted unrelated CoreSimulator/CoreDevice compatibility warnings; macOS builds still succeeded. Swift/Xcode cache writes, GUI launches, and Git metadata writes may need normal sandbox escalation. Do not alter system tools or credentials to work around those restrictions.

## Source map

| File | Responsibility |
| --- | --- |
| `Sources/CodexWidget/CodexWidgetApp.swift` | Entry point, diagnostic mode, app delegate, menu bar icon, Settings window |
| `Sources/CodexWidget/UsageStore.swift` | Main-actor observable state, refresh loop, account changes, stale state, local fallback selection |
| `Sources/CodexWidget/UsagePanel.swift` | Terminal-style tabs, quota bars, reset-time bar, activity grid, shared panel layout |
| `Sources/UsageCore/CodexClient.swift` | App-server process, JSON-line transport, handshake, request timeouts, notifications, shutdown |
| `Sources/UsageCore/UsageModels.swift` | Account/quota/token decoding, formatting, UTC daily matching, reset calculations |
| `Sources/UsageCore/LocalUsageReader.swift` | Rolling 24-hour token counter from local session logs |
| `Tests/UsageCoreTests/` | Protocol, model, quota, and local-log tests |
| `Tests/WidgetTests/` | Store lifecycle/fallback tests and native panel renders |
| `Resources/Info.plist` | Bundle identifier, version, executable, minimum macOS, menu-bar-only behavior |
| `Makefile`, `Package.swift`, `CodexWidget.xcodeproj/` | Build and packaging entry points |

## UI requirements to preserve

- Menu bar: a monochrome `terminal` SF Symbol only. Do not put quota numbers or usage text back in the menu bar label.
- Panel: 440-point width, monospace type, adaptive purple/lavender top rule and selected tabs. Settings offers Auto (follows macOS), Light, and Dark, persisted as `appearance`. The panel uses a lightly tinted native material with rounded corners; Reduce Transparency or Increase Contrast makes it opaque. Keep text and bars fully opaque and readable in both themes.
- Header: left-aligned “Codex Widget” on its own row above the tabs, over a subtle drifting star field. Decorative stars do not intercept input or appear in accessibility; Reduce Motion freezes them, and animation pauses while hidden.
- Tabs: Status, Usage (initial selection), and Stats.
- All tab contents participate in a top-aligned `ZStack`; only the selected tab is visible, interactive, enabled, and exposed to accessibility. The largest content sets the panel height, so switching tabs does not resize it. The footer stays in place. Height can respond to changed data, but must not depend on selected tab.
- Status shows app version, connection, login method, plan, email, last update, and refresh cadence. Do not invent current conversation/session metadata.
- Status reads the exact release tag from the bundle's `CodexReleaseTag` key, stamped by CI before signing (for example `v0.1.0+build.1`). Local bundles fall back to `CFBundleShortVersionString`; unpackaged runs show `Development`. Keep the standard macOS version keys numeric. CI verifies the tag inside the mounted DMG.
- Usage shows today's reported tokens or the local last-24-hours fallback, lifetime tokens, and all returned quota windows.
- Quota bars show **percent used**, not percent remaining. They are rectangular lavender bars, 14 points high, with a 72-point trailing percentage label and a 9-point gap.
- Weekly windows (`windowDurationMins == 10080`) have a separate **Time until reset** bar. It must match the usage bar's height and width. Its fill is the remaining fraction of the time window, and decreases toward reset. Keep the absolute reset text and relative countdown in addition to the bar.
- Stats uses purple/lavender consistently for the Overview highlight, activity grid, legend, All time label, and metric values. Orange remains a warning color, not a Stats accent.
- Stats shows a 26-week daily UTC activity grid plus lifetime tokens, peak daily tokens, longest turn, and streaks when supplied. Hover text distinguishes missing reports from reported zero. Do not invent model breakdowns, session counts, costs, or other Claude-specific fields from the reference screenshots.
- Refresh, Settings, and Quit remain available in the footer. Settings activates the accessory app and focuses its tracked Settings window through `SettingsWindowFocus`; keep this working both on first open and when reopening an existing window.

## Open at login

Settings provides an opt-in **Open at login** toggle backed by `SMAppService.mainApp` (ServiceManagement). `LoginItemSettings.swift` reads macOS registration status rather than persisting an independent Boolean. It handles pending approval with an Open Login Items button, displays failures without falsely changing state, and reloads status when Settings opens or the app becomes active. Registration only occurs when the user changes the toggle; do not automatically enable it during development or tests. Recommend installing in Applications first. This starts the app at user login, including after a restart, not before login. Tests and native renders inject fake service closures and must never register real login items.

## Account data and transport

The app launches its own `codex app-server --stdio` child process and exchanges newline-delimited JSON over pipes. It sends `initialize` with client metadata, then `initialized`, before issuing account requests.

Read-only monitor methods:

- `account/read`: signed-in account type, email, plan.
- `account/rateLimits/read`: quota windows, used percentages, durations, reset timestamps.
- `account/usage/read`: account token summary and optional date-only daily buckets.

Listen for `account/updated` and `account/rateLimits/updated`. A quota notification triggers a full read because a notification may contain only one bucket. Account changes clear old account data; a revision counter prevents applying results from a refresh interrupted by an account-change notification.

The client correlates integer request IDs, uses 20-second default request timeouts, limits buffered response data, and fails pending requests when disconnected. It rejects unsupported server-initiated requests. It never approves tool execution or provides auth tokens. Stopping closes pipes and terminates its own child process. Do not kill unrelated Codex processes when restarting the widget.

Executable lookup order: a nonempty Settings override (must be executable), `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `/Applications/Codex.app/Contents/Resources/codex`, `/Applications/ChatGPT.app/Contents/Resources/codex`, then `PATH`. Settings stores the override as the `codexPath` user-defaults key. Restart after changing it.

Credentials stay managed by Codex. The app-server may update its normal auth cache and logs. The widget discards server stderr to avoid displaying or retaining sensitive server/config details. No API key is needed for the ChatGPT account workflow. API-key-only accounts are not the intended quota source.

Protocol reference: `https://learn.chatgpt.com/docs/app-server`. Installed-version schema inspection is available through `codex app-server generate-json-schema --out <temporary-directory>`; keep generated schemas outside tracked source unless deliberately adopting them.

## Quotas, refresh, and missing data

- Prefer nonempty `rateLimitsByLimitId`; otherwise use legacy `rateLimits`. Preserve every primary/secondary window with a stable bucket/slot ID.
- Remaining quota is `clamp(100 - usedPercent, 0...100)`. UI usage fill is its complement. These percentages do **not** imply a token allowance.
- Reset timestamps are Unix seconds. Display absolute times in the user's local timezone, including its identifier.
- Time-bar fraction is `clamp((resetsAt - now) / (windowDurationMins * 60), 0...1)`. Missing timestamps or nonpositive durations produce no fraction. Its timeline updates every minute. A passed reset never optimistically replenishes quota; wait for the service response.
- Poll at the saved Settings interval (`refreshIntervalSeconds`): 15/30 seconds or 1/2/5/15 minutes, default 1 minute. Invalid saved values fall back to 1 minute. Interval changes reschedule the next poll immediately without canceling in-flight reads; completed reads schedule using the latest interval. The same interval controls stale-panel age checks. Refresh on wake, on opening a stale panel, and on manual Refresh. Avoid overlapping refreshes. Failure retries back off from 5 seconds to a 5-minute ceiling.
- Retain the previous in-memory snapshot during transport failures and visibly mark it stale. Do not persist account usage snapshots to disk.
- Missing summary metrics are `Unavailable`, not zero. Token activity failures should not discard successful quota responses.
- Daily bucket keys are matched to `yyyy-MM-dd` in UTC, explicitly labeled because the API does not document a timezone for date-only buckets.

During live diagnosis on September 21, 2026, the service returned daily history ending September 20 and no entry for the current date. This explained the original missing today's value; it was not a transport or decoding failure. This observation is historical, not a guaranteed reporting schedule.

## Last-24-hours fallback

Use the official current-day bucket when present, **including zero**. Only when it is missing, read local token activity and display **Last 24h** with **This Mac · all local Codex sessions**. This source covers local sessions across logins; it is not account-wide usage and excludes other devices. Do not relabel yesterday's daily bucket as a rolling 24-hour total.

`LocalUsageReader` resolves `CODEX_HOME` or defaults to `~/.codex`, and enumerates `sessions` and `archived_sessions`. It considers recently modified regular JSONL files, reads in 64 KiB chunks off the UI thread, and only decodes session metadata and token-counter events. Conversation text is never retained or logged.

Counting rules:

1. Use event timestamps in `(now - 24 hours, now]`; older counter events establish the baseline.
2. Count increases in cumulative `total_token_usage.total_tokens`; repeated totals contribute nothing.
3. For initial/reset counters, use the reported last increment, capped by total, rather than counting an inherited cumulative baseline.
4. Skip known inherited fork history preceding the fork timestamp. Explicit non-OpenAI providers are excluded.
5. Deduplicate archived/active copies using session ID, timestamp, and cumulative total.
6. Cached input is already included in total tokens; do not add it again.
7. Wait for a newline before counting a trailing record that may still be written. Oversized/unreadable records make results partial. Missing directories, or a wholly unreadable zero result, return unavailable rather than a fabricated zero.

Partial totals are labeled in the UI. Local logs are an internal format and may be missing, pruned, or incomplete. The reader rescans qualifying files each refresh rather than maintaining an incremental cache; revisit this if a very large local history affects performance. Default auth and `CODEX_HOME` may differ between Finder and shell launches; do not silently combine directories.

## Testing and verification

There are currently 35 tests covering JSON transport, failures/timeouts, quota calculations, optional metrics, UTC date matching, rolling counters, duplicate archives, inherited fork events, account changes, stale recovery, wake notifications, shutdown, daily-report precedence, and appearance persistence. Native renders cover Auto/Light/Dark against both system themes and high-contrast appearances.

Store tests inject a fake `CodexServing` client and a local-usage reader; they must not read real account data. Panel tests use sample data in offscreen native `NSHostingView` windows. They assert equal dimensions across all selected tabs and save previews under `.build/previews/panel-{status,usage,stats}-{light,dark}.png`. Use those renders to inspect layout without capturing unrelated desktop content.

Relevant checks:

```sh
swift test
swift test --filter PanelRenderTests
make build
make check
codesign --verify --strict "build/Codex Widget.app"
git diff --check
```

Run checks appropriate to the change. UI-only changes usually need the render test and a build, not repeated full live reads. Actual menu clicks and physical sleep/resume are separate manual smoke checks; the automated wake test posts the notification. Automated inspection of the Codex app itself was blocked, so styling was based on user-supplied screenshots. Never bypass a desktop capture or app-access restriction.

## Distribution assets and screenshots

- `Resources/AppIcon.icns` is the Finder/application icon. Keep `CFBundleIconFile`, Makefile resource copying, and the Xcode Resources phase consistent. The menu bar still uses the monochrome terminal SF Symbol.
- `scripts/render-assets.swift` is the editable AppKit vector source for the icon and installer background. `make assets` regenerates the tracked PNG/ICNS assets; no image service or API key is needed.
- Run `make dmg-tools` once to install pinned `dmgbuild`, `ds-store`, and `mac-alias` into `build/dmg-tools`. `make dmg` builds `build/Codex-Widget.dmg`; override `DMG_PATH` or `DMGBUILD` as needed.
- `scripts/package-dmg.sh` and `scripts/dmg-settings.py` create a compressed read-only HFS+ image with a custom Finder background, positioned icons, and `/Applications` symlink. No Finder automation is required. The script mounts the final image read-only, verifies its signature, icon, license, shortcut, and optional release tag, then detaches it. CI installs these tools before packaging. New releases distribute DMGs instead of ZIPs; historical ZIP releases remain available.
- `make screenshots` renders fictional account data using `PanelRenderTests` and copies the three dark panel PNGs, light Usage panel, and Settings image into `docs/screenshots/`. Inspect them before committing. Never use real account screenshots for public documentation.
- `scripts/set-dmg-icon.swift` applies the app icon to the DMG file itself with NSWorkspace; this extended metadata only persists locally or through metadata-preserving copies. Direct GitHub/HTTP downloads lose that file icon. The mounted volume icon is embedded and independently verified against AppIcon.icns. Do not claim that a bare HTTP-downloaded DMG retains a custom Finder file icon.
- These builds are still ad-hoc signed and unnotarized. Developer ID distribution would require the owner's signing identity and notarization credentials; do not claim it is enabled.

## Git and maintenance

`.github/workflows/release.yml` tests pull requests and every push to `main` on `macos-15` (arm64). Its release job depends on the full test job and only publishes for pushes. It builds and ad-hoc signs the app, sets `CFBundleVersion` to the workflow run number, verifies the mounted DMG's app signature and release tag, and publishes the DMG, SHA256SUMS.txt, and CHANGELOG.md. Tags use `v<CFBundleShortVersionString>+build.<run_number>`; do not reset or rename the workflow casually because its run counter identifies releases. The source plist is not modified by CI.

Each release changelog lists commits since the nearest preceding ancestor `v*` tag. All pushes, including documentation edits, qualify. Runs are not canceled by newer pushes; only a run still at the tip of main explicitly marks its release latest. Publishing stages assets in a draft before making the release visible, supports retrying drafts, and leaves already-published releases unchanged. Only the release job receives `contents: write`; PR tests have read access and never need Codex credentials. Do not add `make check` to CI because it reads a real login. Validate workflow edits with `actionlint` and relevant local build/test checks.

`.gitignore` excludes Swift/Xcode outputs, app bundles, per-user IDE state, render/test artifacts, logs, local Codex state, and common credential/environment files. Keep source, tests, the Xcode project, plist, Makefile, and documentation tracked. Never commit auth files, rollouts, real account snapshots, or build products.

Before a requested commit/push, inspect status and staged contents, check whitespace, and push the intended branch without force. Preserve unrelated user changes. Documentation-only edits do not require rebuilding the running app. When code changes need a restart, quit this widget and its own helper, build, then open the app bundle; do not run multiple widget copies.

Keep `README.md` as the user-facing quick start and this `AGENTS.md` as the implementation/handoff reference and repository guidance for coding agents. Update both when behavior or commands change.
