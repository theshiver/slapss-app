<div align="center">

<img src="docs/app-icon.png" width="84" alt="Slapss app icon">

# Slapss

### Never miss a meeting on Mac.

A free, open-source full-screen meeting reminder for Mac. Quiet notification banners vanish during deep focus. Slapss takes over every display when a meeting starts, with one-click Join for Zoom, Teams, and Google Meet.

**[Download Free on Mac App Store](https://apps.apple.com/app/id6767488326)** · [Try Live Preview](https://slapss-app.com) · [☕ Buy me a coffee](https://buymeacoffee.com/cancetin) · [Changelog](CHANGELOG.md) · [Support](https://slapss-app.com/support)

<sub>★ 4.9 on Mac App Store · Free forever, no limits · Apache 2.0 · Zero tracking · macOS 15+</sub>

<br>

<img src="docs/demo.gif" width="740" alt="Slapss demo: the next meeting in the menu bar, then a full-screen alert with Join, Snooze and Dismiss">

</div>

### Install

```bash
brew install --cask theshiver/tap/slapss
```

Or install directly from the [Mac App Store](https://apps.apple.com/app/id6767488326).

## Why Slapss

| Built-in macOS Banners | Paid & Capped Apps | Slapss |
|---|---|---|
| Quiet corner pop-up vanishes in seconds, easy to miss on wide or multi-display setups. | Daily alert caps, single-calendar free tiers, or subscriptions for snooze and multi-display alerts. | **Every meeting on every display**, one-click Join, and direct Google & Microsoft 365 sign-in. **Free and open source forever.** |

See the [full side-by-side comparison](https://slapss-app.com/meeting-reminder-apps-mac-compared).

## Built for back-to-back calendars

| | |
|---|---|
| **Direct Calendar Sync & Deduplication**<br>Use Apple Calendar (iCloud, Google, Outlook, Exchange) or sign in directly to **Google Calendar** (`authuser` Meet routing) and **Microsoft 365** with read-only OAuth. Automatic cross-source deduplication prevents double alerts. ([Outlook](https://slapss-app.com/outlook-meeting-reminder-mac) · [Google Calendar](https://slapss-app.com/google-calendar-reminder-mac)) | **One-Click Join (7 Platforms)**<br>Detects links for **Zoom, Microsoft Teams, Google Meet, Webex, Whereby, Around, and Yandex Telemost**. Unwraps Microsoft Safe Links, Proofpoint, and Barracuda locally on your Mac. ([Teams](https://slapss-app.com/teams-meeting-reminder-mac) · [Zoom](https://slapss-app.com/zoom-meeting-reminder-mac)) |
| **Presenting Now & Smart Filters**<br>Pause full-screen alerts while sharing your screen. Filter to accepted meetings only, or skip titles by keyword like `"Lunch"` or `"PTO"`. | **macOS Reminders Overlay**<br>Give time-sensitive Apple Reminders the same unmissable full-screen alert, with one-tap completion straight from the card. |
| **Flexible Timing, Themes & 8 Languages**<br>Alert at start, 10s–30s early, or 1–15m ahead. Snooze from 1m to 1h or until end. Sunset, Ocean, and Forest themes, plus **English, Turkish, Spanish, German, Italian, French, Japanese, and Ukrainian**. ([Hyperfocus & ADHD](https://slapss-app.com/adhd-meeting-reminder)) | **Native & Accessible**<br>Built with SwiftUI and AppKit for macOS 15+. Press `Return` to join or `Esc` to dismiss, with VoiceOver labels and Reduce Motion / Reduce Transparency support. |

<p align="center">
  <img src="https://slapss-app.com/menubar.jpg" width="49%" alt="The Slapss menu bar agenda showing the day's meetings">
  <img src="https://slapss-app.com/calendars.jpg" width="49%" alt="Slapss setup: language, theme and calendar access">
</p>

## Private by architecture, verifiable in code

There is no Slapss server, no analytics, no crash reporting, no accounts, and no third-party dependencies. Local calendars stay on your Mac; optional Google Calendar and Microsoft 365 sign-ins use read-only OAuth with tokens stored in your macOS Keychain.

Inspect the installed app's sandbox entitlements yourself:

```bash
codesign -d --entitlements :- /Applications/slapss.app
```

Read the full breakdown in [DEVELOPMENT.md](DEVELOPMENT.md#privacy-details) and the [Privacy policy](https://slapss-app.com/privacy).

## Questions & contributing

<details>
<summary>Which calendars work?</summary>

Any calendar in the macOS Calendar app (iCloud, Google, Outlook, Exchange), plus direct read-only sign-in inside Slapss for both Google Calendar and Microsoft 365 without needing Calendar.app. Automatic deduplication prevents duplicate meetings and double alerts if the same account is connected in both places.

</details>

<details>
<summary>How is Slapss different from MeetingBar?</summary>

Both are free and open source under Apache 2.0. MeetingBar is a menu bar calendar with full-screen alerts as an option. Slapss is built around the full-screen alert: every meeting, every display, with direct Google Calendar and Microsoft 365 sign-in, automatic deduplication, and Presenting Now. See the [full comparison](https://slapss-app.com/meeting-reminder-apps-mac-compared).

</details>

<details>
<summary>How do I build from source or contribute?</summary>

Requires macOS 15 or later and zero third-party dependencies. Start with [DEVELOPMENT.md](DEVELOPMENT.md) and [CONTRIBUTING.md](CONTRIBUTING.md). Found a security issue? See [SECURITY.md](SECURITY.md). Licensed under the [Apache License 2.0](LICENSE).

</details>

---

<sub>The Slapss name, app icon, menu bar mark, and logo are trademarks and not covered by the code license; a fork needs its own name and icon, see [TRADEMARK.md](TRADEMARK.md). Official builds come only from the [Mac App Store](https://apps.apple.com/app/id6767488326) and the `theshiver/tap` Homebrew cask.</sub>

<div align="center">

[Outlook](https://slapss-app.com/outlook-meeting-reminder-mac) · [Google Calendar](https://slapss-app.com/google-calendar-reminder-mac) · [Teams](https://slapss-app.com/teams-meeting-reminder-mac) · [Zoom](https://slapss-app.com/zoom-meeting-reminder-mac) · [ADHD](https://slapss-app.com/adhd-meeting-reminder) · [Compare](https://slapss-app.com/meeting-reminder-apps-mac-compared) · [☕ Buy me a coffee](https://buymeacoffee.com/cancetin)

Made by [Can Çetin](https://cancetin.com/).

</div>
