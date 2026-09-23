# Changelog

All notable user-facing changes to Slapss.

This file is the source of truth for release notes. The public web changelog and
GitHub Releases are generated from it.

## Unreleased

- Join Yandex Telemost meetings directly from links in calendar event descriptions and locations.

## v2.2.0 — September 23, 2026

A release about how Slapss looks and feels.

- A new app icon: the same Slapss hand, now on the warm sunset colors of the new look, with the proper rounded macOS shape. The menu bar icon was redrawn to match.

- The full-screen alert now glides in and fades out instead of snapping on and off. The card rises into place and its contents follow one after another.
- The status at the top of the alert changes with the meeting: a clock while it's still a few minutes away, a ringing bell in the last minute, green once it has started, orange when you're late. The countdown numbers roll instead of jumping.
- The background comes alive as the meeting gets closer. Once it's about to start, a glow runs around the edge of the card and a sweep of light crosses the Join button.
- If you're running late, the card gives a small shake to get your attention.
- The Snooze menu springs open, with its options cascading in.
- Pressing Return now visibly presses the Join button, the same as clicking it.
- The menu bar popup has a new look to match the alert. The next-meeting card now carries the same colors as your full-screen alert and comes alive as the meeting gets close: in the five minutes around the start, a glow runs around it and its Join button catches the light. The countdown rolls from minute to minute, and the Join button opens the meeting straight away.
- Meetings in the list show their calendar's color, and the popup's cards and buttons share one cleaner style.
- The welcome window now names the right step when it asks you to allow calendar access (it always said step 1, but that step moved to 3 when language and theme were added in front of it). Fixed in all seven languages.
- The welcome window and Settings follow the same look. The theme picker now shows a preview of each theme's actual full-screen alert, and Settings → About has a small brand card.
- Fixed: after you opened the menu bar popup once, its animations kept running in the background after it closed, using battery for nothing. They now stop as soon as the popup closes.
- The full-screen alert keeps its dark look even when your Mac is in light mode, so the text on it stays easy to read.
- All of this motion switches off when Reduce Motion is on in System Settings.
- Slapss now needs macOS 15 Sequoia or later. On macOS 14, the App Store keeps offering version 2.1.1.

## v2.1.1 — September 11, 2026

- Fixed: for some Zoom invitations the **Join** button opened a small Zoom logo image instead of the meeting. Zoom's Outlook add-in puts that logo above the join link in the invitation, and Slapss was picking up the first Zoom address it saw. It now skips images and other page assets and finds the actual join link.
- Snooze now offers **30 minutes** and **1 hour** on top of 1, 5, 10 and 15 minutes.
- Fixed: the snooze menu on the full-screen alert was cut off at the top of the card, hiding the shorter options.
- Fixed: when two meetings overlap, the menu bar agenda showed only one of them. The other was neither "later" nor "earlier", so it dropped out of the list entirely. Meetings running right now that aren't the highlighted one are listed under Later today.
- Fixed: a reminder you hadn't completed dropped into Earlier today once its time passed, greyed out and drawn as if it were done. It now stays at the top of the list, marked with how long ago it was due, until you complete it. Earlier today is for finished meetings only.
- Every meeting in the agenda that has an online link now has a small Join button on its row, so you can jump into a meeting that is running in parallel, or one that starts later, without expanding it first. Finished meetings don't get one.
- Slapss now speaks Japanese. Contributed by [@satotakumi](https://github.com/satotakumi), the first outside contribution since the app went open source.

## v2.1.0 — September 7, 2026

- The menu bar can now show your next meeting further ahead than 15 minutes. Until now a meeting 35 minutes away showed nothing but the icon.
- New setting for it: Settings → Menu bar → **Show the next meeting**. Pick **Off** for just the icon, **When it's close** to follow your lead-time setting (at least 15 minutes ahead), or **Anytime today** to always see the next meeting you have left today.
- Meetings more than an hour away show their start time instead of a countdown, so you get "Standup · 11:30" rather than "Standup · in 690m".
- If you liked the old behaviour, you keep it: **When it's close** is the default. The one difference is that it now respects your lead-time setting, so if you had asked for a 30 minute heads-up you will see meetings 30 minutes out instead of 15.

## v2.0.1 — August 25, 2026

- Fixed: if you use Slapss with a Microsoft 365 account and haven't given it access to the macOS Calendar app, the menu bar showed your next meeting but opening it said "Calendar access denied" instead of showing your agenda. Your agenda now appears whenever a Microsoft 365 account is signed in. Access to the macOS Calendar app is optional, and always was.
- Fixed: Microsoft 365 calendars could stop refreshing in the background — while a menu was open, or after macOS put Slapss to sleep. New and changed meetings now arrive on time.
- Slapss no longer asks macOS for read-only access to files you pick yourself. Nothing in the app ever used it. What's left is the sandbox itself, calendar access, and outbound network for Microsoft 365 — and you can check that on your own copy: `codesign -d --entitlements :- /Applications/slapss.app`

## v2.0.0 — August 21, 2026

Slapss is now open source.

- The full source code is published at <https://github.com/theshiver/slapss-app> under the Apache 2.0 licence. Slapss has always claimed that it reads your calendar locally and sends it nowhere. That was a promise you had to take on faith. Now you can read the code and check.
- Settings → About has a new **Source Code** link.
- Fixed: a repeating meeting would stop showing its full-screen alert after you dismissed it once. Every occurrence of a repeating event was being treated as the same event, so dismissing Monday's alert also dismissed every following week's — while the menu bar countdown kept working normally, which made it look like only the first meeting of the day was affected. Snoozing and hiding from the menu bar were leaking across occurrences the same way, and are fixed too.

Same app, same features, still free, still no accounts and no tracking. The Mac App Store remains the only official build.

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
