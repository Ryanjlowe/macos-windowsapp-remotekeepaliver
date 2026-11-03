# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
swift build
swift test
swift test --filter KeepAliveCoreTests.SessionWindowSelectorTests/testName
make bundle      # build/RemoteKeepAliver.app, signed (Apple Development identity if present, else ad-hoc) with identifier com.ryanlowe.RemoteKeepAliver
make install     # kills the running app, copies the bundle to /Applications
```

Diagnostic flags (safe to run from an agent session, they never show the GUI):

```sh
build/RemoteKeepAliver.app/Contents/MacOS/RemoteKeepAliver --list-windows
build/RemoteKeepAliver.app/Contents/MacOS/RemoteKeepAliver --jiggle-once
build/RemoteKeepAliver.app/Contents/MacOS/RemoteKeepAliver --idle
log stream --predicate 'subsystem == "com.ryanlowe.RemoteKeepAliver"' --level info
```

## Architecture

Swift Package Manager only, Swift 5 language mode. `KeepAliveCore` is a library with all logic so `swift test` can import it. `RemoteKeepAliver` is a thin AppKit executable (`main.swift`, no `@main`, because tests cannot import an `@main` executable).

`KeepAliveEngine` is a pure state machine. It owns no timers: `AppDelegate` calls `engine.tick()` every 5 s from a `.common`-mode `Timer`. States are `disabled`, `needsPermission`, `watching`, `away`, `awayNoTarget`. Tests drive it with a `FakeClock` and fakes for each protocol below.

Protocols and their real adapters:

- `Clock`: `SystemClock`.
- `IdleSource`: `CGIdleSource` (`CGEventSource.secondsSinceLastEventType`, `.hidSystemState`).
- `WindowSource`: `AXWindowSource` (Accessibility enumeration of Windows App).
- `WindowActivating`: `WindowActivator`.
- `MousePosting`: `CGMousePoster` (posts `mouseMoved` to `.cghidEventTap`).
- `FocusRestoring`: `WorkspaceFocusRestorer` (waits 300 ms, then re-activates the previous app).
- Also in `System/`: `SleepAssertion` (IOPMAssertion), `Permissions`, `LoginItem` (SMAppService).

`SessionWindowSelector.select` is a pure function. It drops off-screen and untitled windows, drops `Windows App` (Connection Center) and other known non-session titles, prefers titles ending in `Desktop` (case-insensitive) with a fallback to any remaining titled window, and sorts by area, largest first.

Synthetic-event idle bookkeeping: the scout measured that our own posts to the HID tap reset the system idle counter. Each tick the engine computes `lastEventAt = now - idle`. If that falls inside the last burst window (start minus 0.5 s to end plus 0.5 s), it is ours and ignored. Otherwise it becomes `lastRealInputAt`. Without this the app would think the user returned after its first jiggle.

Window titles come from AX (`kAXTitleAttribute`), not `CGWindowListCopyWindowInfo`, because `kCGWindowName` needs Screen Recording permission and AX needs only the Accessibility trust we already require. CGWindowList is not used.

Activation is cooperative on macOS 14+ and can be declined. `WindowActivator` calls `activate()`, sets `kAXFrontmostAttribute`, performs `kAXRaiseAction`, waits 300 ms, checks `NSWorkspace.frontmostApplication`, and retries once. If it fails, that window is not jiggled. If nothing is jiggled the state is `awayNoTarget`.

Sleep assertions (system, and optionally display) are held only while the app is enabled and released on disable and quit.

## Gotchas

- `NSWorkspace.shared.frontmostApplication` and `NSRunningApplication.isActive` only update when the main run loop runs. The activate, jiggle, and restore steps block the main thread with short sleeps, so they verify focus through `Frontmost.pid()` (Accessibility system-wide focused application), which is synchronous. The first live `--jiggle-once` run failed for exactly this reason.
- Do not launch the GUI app (`open`, `make run`, or the bare binary) from an agent session. It triggers permission prompts and a menu bar item nobody is watching. Use the diagnostic flags.
- Run as a signed `.app` bundle. TCC remembers Accessibility per bundle id and signature, so a bare `.build` binary does not keep the grant. Ad-hoc signatures change on every rebuild and lose the grant; use a stable identity (`SIGN_IDENTITY=...`).
- Relaunch after the user grants Accessibility. Event posting trust is evaluated at launch.
- The Windows App bundle id is the constant `windowsAppBundleID` (`com.microsoft.rdc.macos`), not a setting. Focus restore is skipped when the previous app is Windows App.
- Session windows are titled like `Australia Desktop`; the Connection Center is titled exactly `Windows App`. Never target the latter.
- Posting without Accessibility trust fails silently, so check `AXIsProcessTrusted()` first when input seems to do nothing.
- `Makefile` `bundle` overwrites files in place and does not clear the old bundle.

## Docs

- `docs/DESIGN.md`: the spec, menu layout, and open questions.
- `docs/RESEARCH.md`: sourced reasoning; see "Design implications".
- `docs/scout-findings.md`: measured window inventory and idle counter behavior.
