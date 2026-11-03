# RemoteKeepAliver design

A minimalist macOS menu bar app that keeps a Windows App remote desktop session
alive. When you walk away from the Mac it brings the remote session window to
the front and moves the mouse a few pixels inside that window on a schedule.
The remote Windows PC sees real input, so idle-session policies do not
disconnect you and Microsoft Teams keeps showing you as Available. When you
come back it stops immediately.

See `RESEARCH.md` for the sourced reasoning and `scout-findings.md` for the
measurements that drove the decisions below.

## Goals and non-goals

Goals:

- Keep the Windows App session alive without a system-wide mouse jiggler.
- Act only after the user has been idle for a configurable period.
- Target only Windows App session windows (titles like `Australia Desktop`),
  never the Connection Center window (titled `Windows App`).
- Stop as soon as real user input is detected.
- Stay out of the way: no Dock icon, one menu bar item, a handful of settings.

Non-goals:

- Restoring focus at the moment the user returns. That races with the user
  starting to type. Focus is instead returned right after each pulse, while
  the user is still away (see the away-mode cycle).
- Diagnosing server-side causes. The README explains how to read the
  disconnect dialog and remote event log, but the app only injects input.
- Supporting other RDP clients. The bundle id is a constant, not a setting.

## Behavior

### States

```
disabled ──(enable)──▶ watching ──(idle ≥ threshold)──▶ away
   ▲                      ▲                               │
   └───(disable)──────────┴────────(real input)───────────┘
```

| State | Meaning | Menu bar icon |
|---|---|---|
| `disabled` | User turned the app off. Nothing runs. | dimmed |
| `needsPermission` | Accessibility trust missing. Menu shows a fix action. | warning badge |
| `watching` | User is present. Poll idle every few seconds. | normal |
| `away` | User idle. Every jiggle interval: find session windows, raise, jiggle. | filled / active |
| `awayNoTarget` | User idle, but no Windows App session window exists. Keep looking. | normal with note |

### Idle detection and the synthetic-event problem

Idle time comes from `CGEventSource.secondsSinceLastEventType(.hidSystemState,
eventType: kCGAnyInputEventType)`. The scout measured that the app's own
synthetic mouse events, posted to `.cghidEventTap`, reset that counter. So the
engine keeps its own bookkeeping:

1. On every tick, compute `lastEventAt = now - measuredIdle`.
2. If `lastEventAt` falls inside the time window of the app's own most recent
   synthetic burst (start minus 0.5 s to end plus 0.5 s), attribute it to the
   app and ignore it.
3. Otherwise set `lastRealInputAt = lastEventAt`.
4. Effective idle is `now - lastRealInputAt`.

This is pure logic in `KeepAliveEngine` and is covered by unit tests with a
fake clock and fake idle source.

### Away-mode cycle

Every `jiggleInterval` seconds while `away`:

1. Find the Windows App process by bundle id `com.microsoft.rdc.macos`.
2. Enumerate its windows through the Accessibility API and pick session
   windows with `SessionWindowSelector` (see the next section).
3. Remember the currently frontmost app (`NSWorkspace.frontmostApplication`).
4. For each session window:
   1. Activate Windows App (`NSRunningApplication.activate()`), then set
      `kAXFrontmostAttribute` on the app element and perform `kAXRaiseAction`
      on the window. Activation is cooperative on macOS 14+ and may be
      declined, so check return codes, wait about 300 ms, confirm with
      `NSWorkspace.frontmostApplication`, and retry once.
   2. Post `mouseMoved` events to `.cghidEventTap`. A `CGWarpMouseCursorPosition`
      alone generates no event, so every move is a posted `CGEvent`:
      - If the cursor is already inside the window frame, jiggle around the
        current position.
      - Otherwise post a move to the window center first.
      - Jiggle pattern: +d, then -d, where d is 5 px, with ~40 ms between
        events. The cursor ends inside the window.
   3. If the "Also press a key" setting is on, post an F15 key down and up
      (a key Windows ignores) after the moves.
5. If the "Return focus after jiggle" setting is on (default), re-activate the
   remembered app about 300 ms after the last event so Windows App has
   processed the input. When the user returns, their previous app is in front.
6. Record the burst start and end timestamps for the idle bookkeeping.

The first cycle runs as soon as the engine enters `away`. `Jiggle now` in the
menu runs one cycle in any state and is the diagnostic for whether input
reaches the remote.

### Session window selection

`SessionWindowSelector.select(from windows: [WindowInfo]) -> [WindowInfo]`
is a pure function so it can be unit tested against the real inventory from
`scout-findings.md`. Rules, in order:

1. Drop windows that are not on screen or have an empty title.
2. Drop windows whose title is exactly `Windows App` (Connection Center) or
   that match other known non-session titles (`Devices`, `Apps`, `Settings`,
   `Connection Center`, `Preferences`).
3. Prefer windows whose title ends with `Desktop` (case-insensitive). If none
   match, fall back to the remaining titled windows, because a user can rename
   a connection.
4. Sort by area, largest first.

### Keep the Mac awake

While enabled, hold an `IOPMAssertion` of type
`PreventUserIdleSystemSleep`, and when the "Keep display awake" setting is on
also `PreventUserIdleDisplaySleep`. A sleeping Mac drops the connection, and a
locked screen means synthetic input never reaches Windows App. Both are on by
default; the display one can be turned off.

## Architecture

Swift Package Manager, no Xcode project. Three targets:

```
Sources/
  KeepAliveCore/          library: all logic, testable
    Engine/KeepAliveEngine.swift     state machine + idle bookkeeping (pure)
    Engine/Clock.swift               Clock protocol, SystemClock
    Engine/Settings.swift            UserDefaults-backed settings
    Windows/WindowInfo.swift         value type: id, title, frame, isOnScreen
    Windows/SessionWindowSelector.swift   pure selection rules
    Windows/AXWindowSource.swift     Accessibility enumeration of Windows App
    Windows/WindowActivator.swift    activate app, AXRaise, set main
    Input/IdleSource.swift           protocol + CGEventSource implementation
    Input/MousePoster.swift          protocol + CGEvent implementation
    System/SleepAssertion.swift      IOPMAssertion wrapper
    System/Permissions.swift         AXIsProcessTrusted, prompt, open Settings
    System/LoginItem.swift           SMAppService wrapper
  RemoteKeepAliver/       executable: AppKit shell
    main.swift                       NSApplication bootstrap (no @main)
    AppDelegate.swift                wires engine, timer, status menu
    StatusMenuController.swift       NSStatusItem + NSMenu
Tests/
  KeepAliveCoreTests/
    SessionWindowSelectorTests.swift
    KeepAliveEngineTests.swift
Packaging/
  Info.plist                         LSUIElement=true, bundle id, min OS 14
  RemoteKeepAliver.entitlements      (none needed; kept for clarity)
Makefile
```

Why a library plus a thin executable: `swift test` can import
`KeepAliveCore`, while an executable target that uses `@main` cannot be
imported by tests.

Why AppKit `NSStatusItem` rather than SwiftUI `MenuBarExtra`: the menu needs
disabled status lines, submenus with check marks, and dynamic titles, which
`NSMenu` does directly.

### Protocols for testability

```swift
public protocol Clock { var now: Date { get } }
public protocol IdleSource { func secondsSinceLastInput() -> TimeInterval }
public protocol WindowSource { func sessionCandidates() -> [WindowInfo] }   // all Windows App windows
public protocol WindowActivating { func activateAndRaise(_ window: WindowInfo) }
public protocol MousePosting { func jiggle(in frame: CGRect, pressKey: Bool) -> (start: Date, end: Date) }
public protocol FocusRestoring { func currentFrontmost() -> FrontmostApp?; func restore(_ app: FrontmostApp) }
```

`KeepAliveEngine` takes all five plus a `Settings` value, exposes
`state`, `lastTarget`, `tick()`, and a `onStateChange` callback. The
`AppDelegate` drives `tick()` from a 5 s `Timer` on the main run loop.

### Menu

```
RemoteKeepAliver            (menu bar icon: cursorarrow.motionlines SF Symbol)
──────────────────────────
Status: Watching (idle 0:42)         disabled item, updates every tick
Target: Australia Desktop            disabled item, or "No session window"
──────────────────────────
✓ Enabled                            toggle
Start after idle    ▸ 1 min / 2 min ✓ / 5 min / 10 min
Jiggle every        ▸ 30 s / 1 min ✓ / 2 min / 4 min
✓ Keep Mac awake
✓ Keep display awake
✓ Return focus after jiggle
  Also press a key (F15)
  Launch at login
──────────────────────────
Jiggle now                           manual test, works in any state
Grant Accessibility access…          shown only when trust is missing
──────────────────────────
Quit
```

Default jiggle interval is 1 min. Teams flips to Away after 5 min without
input and the shortest RDS idle limit is 1 min, so 1 min keeps both satisfied
with margin.

## Permissions and packaging

- Accessibility trust is required to post events and to read window titles
  through AX. On first launch the app calls `AXIsProcessTrustedWithOptions`
  with the prompt option. TCC remembers the grant per bundle id and code
  signature, so the app must run as a `.app` bundle signed with a stable
  identity. Ad-hoc signing (`codesign -s -`) is fine for personal use.
- Screen Recording is not required because window titles come from AX, not
  from `CGWindowListCopyWindowInfo`.
- `Info.plist` sets `LSUIElement` to true so there is no Dock icon and
  `NSAccessibilityUsageDescription` to explain the prompt.
- macOS evaluates the post-event permission at launch, so the app must be
  relaunched after the grant. The menu says so while trust is missing.
- `make bundle` assembles `build/RemoteKeepAliver.app`; `make install` copies
  it to `/Applications`; `make run` launches it with `open`.

## Diagnostic command-line flags

The executable accepts flags so behavior can be checked from a terminal
without the menu:

| Flag | Effect |
|---|---|
| `--list-windows` | Print every Windows App window seen through AX with title, frame, on-screen flag, and whether `SessionWindowSelector` picked it. Exit. |
| `--jiggle-once` | Run one away-mode cycle (activate, raise, jiggle, return focus) and exit. |
| `--idle` | Print measured idle every second for 15 s. Exit. |

The `.app` bundle's binary can be invoked directly:
`build/RemoteKeepAliver.app/Contents/MacOS/RemoteKeepAliver --list-windows`.

## Logging

`os.Logger(subsystem: "com.ryanlowe.RemoteKeepAliver", category: ...)` for
state changes, target selection, and each jiggle. View with:

```
log stream --predicate 'subsystem == "com.ryanlowe.RemoteKeepAliver"' --level info
```

## Open questions to verify after the first build

- Does Windows App forward a 5 px synthetic move to the remote when its window
  was just raised? The 300 ms settle delay is a guess; tune it.
- Does mouse-only motion keep Teams Available on the remote, or is the F15
  option needed?
- Does returning focus 300 ms after the pulse ever cause Windows App to drop
  the queued events?
- Does a full-screen session window (separate Space) need extra handling? AX
  raise should switch Spaces, but verify.
- Whether `IOHIDSystem` `HIDIdleTime` ignores synthetic posts. If it does, it
  could replace the bookkeeping, but the bookkeeping is kept because it needs
  no assumptions.
