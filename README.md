<div align="center">

<img src="slapss/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="112" alt="Slapss app icon">

# Slapss

**A full-screen meeting reminder for Mac.**

Slapss lives in your menu bar, watches your calendar, and puts an unmissable
full-screen card on your display the moment a meeting starts.

[**Download on the Mac App Store**](https://apps.apple.com/app/id6767488326) · [slapss-app.com](https://slapss-app.com) · [Changelog](CHANGELOG.md)

*Free forever. No subscription, no in-app purchase, no account, no tracking.*

</div>

---

## Why this repository exists

Slapss makes one claim above all others: **it reads your calendar locally and
sends it nowhere.** In a closed-source binary that is a promise you have to take
on faith. This repository is here so you don't have to — you can read every line
that touches your calendar data.

The app you install is still the one on the Mac App Store. Nothing about how you
use Slapss changes.

## What it does

- **Menu bar status item** with the next meeting's title and a live countdown.
- **Full-screen alert** at meeting start, with Join, Snooze, and Dismiss. Shows on one display or all of them.
- **Calendar sources:** macOS Calendar and Reminders (EventKit) and Microsoft 365 / Exchange (Microsoft Graph).
- **Presenting Now** — a one-click toggle that queues alerts instead of firing them while you're screen sharing.
- **Themes:** Sunset, Ocean, Forest.
- **Six languages:** English, Turkish, Spanish, German, Italian, French.
- **Accessibility:** full VoiceOver labelling, keyboard-operable alert, and Reduce Motion / Reduce Transparency support.

## Privacy

There is no Slapss server. There is nothing to have an outage.

- Calendar and reminder data is read through Apple's EventKit and stays on your Mac.
- Microsoft 365 calendars are fetched directly from Microsoft Graph by the app itself, using a read-only scope (`Calendars.Read`, `User.Read`). Tokens live in your keychain.
- No analytics, no crash reporting SDK, no telemetry, no accounts.
- The app is sandboxed. Its entitlements are the whole story — three of them, in [`slapss/slapss.entitlements`](slapss/slapss.entitlements): app sandbox, outbound network (for Microsoft Graph), and calendar access.

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

Requirements: macOS 14.6 or later to **run**, **Xcode 26 or later** to build.

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
Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) first — it says what gets merged,
what doesn't, and how long you should expect to wait.

Found a security issue? Don't open an issue. See [`SECURITY.md`](SECURITY.md).

## License

Code is licensed under the [Apache License 2.0](LICENSE).

**The Slapss name, app icon, menu bar mark, and logo are not covered by that
license.** They are trademarks and copyrighted assets, all rights reserved. If
you publish a fork, it must use its own name and its own icon. See
[`TRADEMARK.md`](TRADEMARK.md).

The only official build of Slapss is the one distributed from
[the Mac App Store listing above](https://apps.apple.com/app/id6767488326).
