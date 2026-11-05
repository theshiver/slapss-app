# Developing Slapss

The technical side of the project: what the app touches, how it is put together,
and how to build it. For what Slapss is and how to get it, see the
[README](README.md).

## Why the source is public

Slapss makes one claim above all others: **it reads your calendar locally and
sends it nowhere.** In a closed-source binary that is a promise you have to take
on faith. This repository is here so you don't have to — you can read every line
that touches your calendar data.

The app you install comes from the Mac App Store or the `theshiver/tap` Homebrew
cask, built from the same source. Nothing about how you use Slapss changes.

## Privacy details

There is no Slapss server. There is nothing to have an outage.

- Calendar and reminder data is read through Apple's EventKit and stays on your Mac.
- Microsoft 365 calendars are fetched directly from Microsoft Graph by the app itself, using a read-only scope (`Calendars.Read`, `User.Read`). Tokens live in your keychain.
- No analytics, no crash reporting SDK, no telemetry, no accounts.
- The app is sandboxed, and its entitlements are the whole story — three of them, in [`slapss/slapss.entitlements`](slapss/slapss.entitlements): app sandbox, outbound network (for Microsoft Graph), and calendar access. Don't take this on faith, read them off the copy you installed:
  `codesign -d --entitlements :- /Applications/slapss.app`
  Two things you may see that aren't in that file. Builds up to 2.0.0 also carried `com.apple.security.files.user-selected.read-only`, injected by an Xcode build setting (`ENABLE_USER_SELECTED_FILES`); no code path ever used it and 2.0.1 removes it. And a copy you build yourself carries `com.apple.security.get-task-allow`, which Xcode adds to local builds so a debugger can attach — App Store builds don't have it.

## Architecture

~8,900 lines of Swift across 28 files, **no third-party dependencies** — no SPM
packages, no CocoaPods, no Carthage. Even the Microsoft sign-in flow is
hand-rolled on `ASWebAuthenticationSession` + `CryptoKit` (PKCE).

| Object | Responsibility |
|---|---|
| `CalendarAggregator` | Merges EventKit + Microsoft Graph sources, publishes `upcomingMeetings` |
| `AlertScheduler` | Timers, watchdog, App Nap prevention, fires and queues overlays |
| `AppSettings` | All user preferences, persisted to `UserDefaults` |
| `LocalizationManager` | Runtime language switching without a restart |
| `PopoverVisibilityMonitor` | Tracks real popover open/close via `NSWindow` notifications |

[`CLAUDE.md`](CLAUDE.md) documents the architecture in full, along with the
non-obvious macOS and SwiftUI constraints this app runs into — `MenuBarExtra`
never calling `onDisappear`, `Color.clear` flipping the AppKit coordinate system,
App Nap throttling scheduled timers, and more. **Read it before changing
anything.** Those workarounds look like mistakes until you know why they're there.

## Building from source

Requirements: macOS 15 or later to **run**, **Xcode 26 or later** to build.

> **Xcode 26 is a hard requirement, not a suggestion.** The project sets
> `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which makes every declaration
> implicitly `@MainActor`. Older Xcode versions don't know that build setting,
> silently ignore it, and then fail with a wall of *"call to main actor-isolated
> instance method in a synchronous nonisolated context"* errors. If you see
> those, your Xcode is too old — the code is fine.

```
git clone https://github.com/theshiver/slapss-app.git
cd slapss-app
open slapss.xcodeproj
```

Two things to change for your own build:

1. **Signing.** In Xcode, select the `slapss` target → Signing & Capabilities →
   set **Team** to your own Apple developer team. The committed value is the
   upstream team and won't work for you.
2. **Microsoft sign-in** (optional — everything else builds and runs without it).
   The committed Azure app registration is the upstream one. To sign in against
   your own, follow [`AZURE_SETUP.md`](AZURE_SETUP.md).

To check that it compiles without any signing setup at all:

```
xcodebuild build -project slapss.xcodeproj -scheme slapss -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Contributing

Bug fixes, translation corrections, and accessibility improvements are welcome.
Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) first. Found a security issue?
Don't open an issue, see [`SECURITY.md`](SECURITY.md).
