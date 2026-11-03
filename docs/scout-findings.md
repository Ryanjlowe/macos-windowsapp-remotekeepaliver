# Scout findings (2026-11-04)

Empirical facts gathered on the development Mac before design. These are
measurements, not research; see `RESEARCH.md` for sourced claims.

## Environment

| Item | Value |
|---|---|
| macOS | 27.0 (build 26A428), Apple silicon |
| Swift | 6.4 (Xcode 27.1) |
| Windows App | 11.4.1, bundle id `com.microsoft.rdc.macos`, `LSMinimumSystemVersion` 14.0 |

## Windows App window inventory

Captured with `CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements])`
while one remote session was open. All windows belong to a single process.

| Window | Layer | On screen | Size | Title |
|---|---|---|---|---|
| Remote session | 0 | yes | 3292 x 1410 | `Australia Desktop` |
| Connection Center | 0 | yes | 1728 x 1017 | `Windows App` |
| 8 helper windows | 0 | no | 3440 x 30 or 5120 x 30 (toolbar strips), 810 x 440, 64 x 64 | empty |

Conclusions:

- The session window is the one whose title ends with `Desktop` and is not
  exactly `Windows App`. The Connection Center is titled `Windows App`.
- Layer alone does not separate them; both are layer 0. Filter on title and
  on-screen status, then prefer the largest candidate.
- Untitled, off-screen windows must be ignored.
- Window titles were readable from a terminal process that already holds
  Screen Recording permission. The app must not assume that; it reads titles
  through the Accessibility API, which needs only Accessibility trust.

## Idle counters versus synthetic events

Script: read `CGEventSource.secondsSinceLastEventType` for `.hidSystemState`
and `.combinedSessionState` with `kCGAnyInputEventType`, then post a 1 px
`mouseMoved` there-and-back and read again.

| Post method | `.hidSystemState` | `.combinedSessionState` |
|---|---|---|
| `post(tap: .cghidEventTap)` | reset to 0 | reset to 0 |
| `post(tap: .cgSessionEventTap)` | reset to 0 | reset to 0 |
| `post(tap: .cgAnnotatedSessionEventTap)` | not reset | not reset |
| `postToPid(WindowsApp)` | reset to 0 (reading confounded by real input) | reset to 0 |

The `.hidSystemState` counter is documented as hardware-only, but a post to the
HID tap is treated as hardware. The user was at the keyboard during the second
run, so individual rows may be contaminated; the HID-tap row was reproduced
twice and is reliable.

Design consequence: the app cannot read idle time naively after it starts
jiggling. It records the timestamp of its own last synthetic event and treats
the user as returned only when measured idle is shorter than the time since
that post (minus a small tolerance). This works whichever counters a post
resets and needs no extra permission.

`AXIsProcessTrusted()` returned true for the terminal, so these experiments
ran with Accessibility trust. Posting events without it fails silently.
