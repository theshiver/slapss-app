# Changelog

All notable user-facing changes to Slapss.

This file is the source of truth for release notes. The public web changelog and
GitHub Releases are generated from it.

## v2.0.0 — August 21, 2026

Slapss is now open source.

- The full source code is published at <https://github.com/theshiver/slapss-app> under the Apache 2.0 licence. Slapss has always claimed that it reads your calendar locally and sends it nowhere. That was a promise you had to take on faith. Now you can read the code and check.
- Settings → About has a new **Source Code** link.

Nothing else changed. Same app, same features, still free, still no accounts and no tracking. The Mac App Store remains the only official build.

## v1.8.2 — July 30, 2026

- Fixed: Snooze could appear to do nothing on the full-screen alert in macOS 27 beta. The snooze choices now open reliably inside the alert.
- Fixed: Calendars now reappear in Settings without restarting Slapss after you remove and re-add a macOS Calendar account.

## v1.8.1 — July 10, 2026

- Set your own lead time for the full-screen alert with a slider: at meeting start, 30 seconds, or anywhere from 1 to 15 minutes before (Settings → Alert → Show alert).
- Busy day? The agenda now scrolls instead of growing past the bottom of your screen. Short days look exactly the same as before.
- The full-screen alert's Join button now follows your color theme, and a small hint shows the keyboard shortcuts that were always there: Return to join, Esc to dismiss.
- The alert now says "Meeting" for meetings and "Reminder" for reminders — previously everything was labeled "Reminder".
- Setup steps are numbered correctly again when optional steps (like Microsoft 365) aren't shown.
- "Nothing soon" in the popover is now clickable — it opens the details of that next meeting.
- Settings got clearer: short explanations under the two lead-time options and the "accepted meetings only" filter, and the Calendars tab now offers a fix when calendar access is missing.
- Dates in the popover header now follow your language's natural word order (e.g. "13 Tem Pzt" in Turkish).
- Small polish: bigger click target for completing reminders, and the menu-bar countdown no longer freezes while a menu is open.
- Fixed: the Preferences window sometimes opened behind other windows. It now always comes to the front.

## v1.8 — July 3, 2026

- Themes! Pick between Sunset (the classic Slapss look), Ocean, and Forest in Settings or during onboarding.
- New "Presenting Now" toggle pauses the full-screen alert while you're screen sharing or presenting, so meetings never take over your screen mid-demo.
- Faster access to meetings: a Join button right in the notification banner, Return/Enter to join or dismiss the full-screen alert, and a new "Open in Calendar" button on agenda rows.
- A round of UX, accessibility, and localization improvements throughout the app, and a new menu bar icon.

## v1.7 — July 2, 2026

- New setting to only show the full-screen alert for meetings you've accepted (Settings → Alert). Tentative and declined meetings still appear in the agenda but won't trigger the overlay. Off by default.
- Alerts for meetings whose start was missed by more than 10 minutes (for example while your Mac was asleep overnight) no longer pile up when you reopen the lid.

## v1.6 — June 30, 2026

- Fixed high background CPU usage (~40%) when the popover is closed. Animations now pause when the app is idle.
- Reduced Motion: all animations (blobs, floating dots, pulsing dots, background mesh) respect the macOS Accessibility → Reduce Motion setting.
- Full-screen alert can now be shown up to 1 minute before a meeting starts (Settings → Alert → Show alert).
- About section now shows the app website and support email.
- Version number in About no longer shows the build number.
- Welcome tour: language selection is now the first step, so the rest of the setup runs in your language.
- Welcome tour: lead-time picker now includes a 1-minute option.

## v1.5 — June 23, 2026

- Reminders now trigger the full-screen overlay alert at their due time.
- Overlay shows a Complete button instead of Join for reminders.
- Complete reminders directly from the overlay or from the agenda in the popover by tapping the circle icon next to any reminder.
- New setting to turn the reminder overlay on or off (Settings → General → Alerts, default on).

## v1.4 — June 16, 2026

- Multi-language support: English, Turkish, Spanish, German, Italian, French.
- Language picker in Settings → General → Language.
- OS language auto-detected on first launch.
- All in-app text switches instantly without a restart.
- Agenda rows are now expandable. Tap any row to reveal full time range, location, attendees, and a join button.
- Show alert 0, 15, or 30 seconds before a meeting starts (Settings → General → Alert).
- Bug fix: mirrored text and icons in the popover hero card on some systems.
- Bug fix: CPU usage growing gradually over multi-day uptime (concurrent EventKit tasks accumulating).

## v1.3 — June 2, 2026

- Bug fix: calendar selection was being ignored after restart.
- Popover hero card now shows the same meeting as the menu bar.
- App icon: orange backdrop removed from popover header and welcome screen.
- New setting: optional next-meeting text in the menu bar.
- Google Meet: per-calendar Google account selector.
- New setting: show full-screen alert on all displays simultaneously.

## v1.2 — May 28, 2026

- Bug fix: full-screen alert card was pushed into the corner on notched displays.
- ESC key now dismisses the full-screen alert.
- App icon and menu bar icon updated.

## v1.1 — May 20, 2026

- Bug fix: full-screen alert sometimes never fired while the app was running.
- Bug fix: mirrored text in the popover hero card.

## v1.0

Initial release.

- Menu bar status item with next meeting title and countdown.
- Full-screen alert at meeting start (Join, Snooze, Dismiss).
- EventKit (macOS Calendar) and Microsoft 365 / Exchange calendar sources.
- Onboarding flow and Settings window.
