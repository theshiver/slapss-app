# Slapss — Claude Project Context

macOS menu bar app (SwiftUI + AppKit hybrid). Shows meetings from macOS Calendar / Exchange and fires a full-screen overlay alert at meeting start. Distributed via App Store.

Two repos:
- `slapss-app` — macOS app (this repo). **Public**, Apache-2.0. See `CONTRIBUTING.md`.
- `slapss-web` — marketing site on Cloudflare. **Private**, not published. The user-facing changelog is served from it at <https://slapss-app.com/changelog.html>.

`CHANGELOG.md` in this repo is the source of truth for user-facing release notes; `changelog.html` and GitHub Releases are copied from it. The "Changelog log" at the bottom of this file is the separate engineering record — different audience, keep both.

---

## Rules

- **Never bump version numbers without asking Can first.** He decides the version.
- **Release process is in `RELEASING.md`.** Follow it in order; the ordering is what keeps the App Store, the tag, the GitHub Release, and the marketing site in step.
- **After every user-visible change, update `CHANGELOG.md` first**, then mirror it into `slapss-web/changelog.html` (separate private repo). Record the engineering detail in the Changelog log at the bottom of this file. No exceptions.
- Never touch `slapss-web` unless the change requires updating privacy/terms or the changelog.

---

## Architecture

### Entry point
`slapssApp.swift` — `@main`. Creates all `@StateObject`s and injects them as `environmentObject` into every scene.

### Core objects (all `ObservableObject`, injected via environment)
| Object | Responsibility |
|---|---|
| `CalendarAggregator` | Merges EventKit + Microsoft Graph sources, publishes `upcomingMeetings` |
| `AppSettings` | All user preferences, persisted to UserDefaults |
| `AlertScheduler` | Timers, watchdog, App Nap prevention, fires/queues overlays |
| `LocalizationManager` | Runtime language switching without restart |
| `PopoverVisibilityMonitor` | Tracks real popover open/close via NSWindow notifications |

### Key files
- `ContentView.swift` — popover UI (hero card, agenda, `BlobsBackground`, `FloatingDotsBackground`)
- `AlertView.swift` — full-screen overlay card
- `OverlayWindowController.swift` — manages the screen-saver-level `NSWindow`(s) hosting `AlertView`
- `AlertScheduler.swift` — all scheduling logic, App Nap, watchdog, missed-fire recovery
- `CalendarAggregator.swift` — merge + poll loop
- `EventKitSource.swift` — EventKit fetch (Calendar + Reminders)
- `GraphCalendarSource.swift` — Microsoft Graph fetch (Exchange)
- `AppSettings.swift` — all `@Published` preferences + UserDefaults persistence
- `PopoverVisibilityMonitor.swift` — NSWindow notification observer
- `Theme.swift` — `AppTheme` (sunset/ocean/forest) + `AppTheme.Accents` color sets + `ThemeSwatchPicker` (shared by Settings and Onboarding)

---

## Non-obvious patterns and gotchas

### The project requires Xcode 26+ — older Xcode fails with actor-isolation errors

`project.pbxproj` sets `SWIFT_APPROACHABLE_CONCURRENCY = YES` and
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 6.2 / Xcode 26 settings), with
`SWIFT_VERSION = 5.0`. Every declaration is therefore implicitly `@MainActor`,
which is why so little of this codebase carries explicit `@MainActor` annotations
despite being almost entirely UI code.

Xcode versions older than 26 do not recognise those build settings. They don't
error on the unknown setting — they **silently ignore** it, compile everything as
nonisolated, and then emit a wall of *"call to main actor-isolated instance
method ... in a synchronous nonisolated context"* errors in `MeetingEvent.swift`,
`StatusMenuController.swift`, and `AlertView.swift`. The code is not broken; the
toolchain is too old. This is what broke the first public CI run on a `macos-15`
runner (Xcode 16).

Consequences:
- CI must run on `macos-26` or newer. See `.github/workflows/build.yml`.
- Don't "fix" those errors by sprinkling `@MainActor` or `nonisolated` around.
  Check the Xcode version first.
- If the implicit-MainActor default is ever turned off, the annotations it was
  standing in for have to be added back by hand across the whole codebase.

### MenuBarExtra(.window) keeps the view graph alive permanently
`onAppear` fires once on first popover open. `onDisappear` **never fires** on popover close — the window hides, it is not destroyed. Consequences:
- Never use `onAppear/onDisappear` to gate `.repeatForever()` animations. They will run at 60 fps indefinitely with nothing on screen.
- Use `PopoverVisibilityMonitor.isVisible` instead, which listens to real `NSWindow` key/close notifications.

### Color.clear flips NSView coordinate system on macOS
In a `ZStack` on macOS, `Color.clear`'s NSView backing can leak a flipped coordinate context into sibling views, mirroring glyphs. Always use `.frame(maxWidth: .infinity, maxHeight: .infinity)` to expand a transparent area. Never use `Color.clear` as a spacer in a ZStack.

### Timer.scheduledTimer is App Nap-vulnerable
Menu-bar apps are aggressively enrolled in App Nap. `.scheduledTimer` is added to `.default` runloop mode, which the OS throttles or suspends. Always use `Timer(...) + RunLoop.main.add(timer, forMode: .common)`.

### refreshEventKitOnly must cancel its previous Task
Any async Task started on a repeating timer must store its handle and cancel before starting a new one. If EventKit is slow, tasks accumulate and each completion triggers a full Combine cascade, growing CPU unboundedly over days.

### AppKit-hosted views don't inherit SwiftUI environment
`OverlayWindowController` builds `NSHostingView` directly. SwiftUI `environmentObject` values are not propagated automatically — must be passed explicitly: `rootView.environmentObject(lm)`.

### OverlayWindow must become key for ESC to work
A borderless `NSWindow` (`.borderless` style) cannot become key by default. `OverlayWindow` overrides `canBecomeKey` and `canBecomeMain` to `true`, and `slapssApp.activate(ignoringOtherApps: true)` is called before `makeKeyAndOrderFront`. On dismiss, the previously frontmost app is reactivated.

### Overlay controls that expand must stay inside the overlay window
The full-screen alert runs in a borderless `.screenSaver`-level `NSWindow`. SwiftUI `.popover`, `Menu`, system tooltips, and similar presentations can create separate system-managed windows that macOS may place behind or suppress relative to the overlay. Render expanded controls directly in `AlertView` with an in-window `.overlay` instead. The snooze dropdown follows this pattern; the attendee tooltip does too.

### Calendar filter is not auto-seeded at launch
`CalendarAggregator.start(enabledEventKitCalendars:enabledGraphCalendars:)` must receive the persisted selection from `AppSettings` to seed the source filters before the first fetch. An empty set in `EventKitSource` means "all calendars."

### MenuBarExtra window identification
`menuBarExtraWindows()` identifies the popover window by three properties: no `.titled` style mask, level above `.normal`, and top edge near the menu bar. This same heuristic is used by `PopoverVisibilityMonitor`. Don't change one without the other.

### Presenting Now is intentionally manual, not detected
v1.8 originally scoped "suppress the overlay while screen sharing" using `INFocusStatusCenter` (Focus/DND detection). Abandoned before implementation: that API requires a restricted `com.apple.developer.focus-status` entitlement that needs separate approval from Apple (like CarPlay), not a self-serve Xcode capability — too risky to gate a shipping feature on. There is also no reliable *public* API to detect "this screen is being captured by another app" on macOS (Zoom/Teams/Meet each implement capture differently). Shipped instead as `AlertScheduler.presentingModeEnabled` — a session-only (never persisted) manual toggle. Every `fireMeetingStart` call is redirected into `pendingAlerts` while it's on, using the same FIFO that handles back-to-back meetings, and drained via `togglePresentingMode()` when switched off. If Apple's Focus Status entitlement becomes self-serve in the future, revisit — it would be a strictly better UX than remembering to flip a toggle.

### StatusMenuController is localized via a borrowed weak reference
`StatusMenuController` is a plain AppKit singleton instantiated before any SwiftUI environment exists, so it can't use `@EnvironmentObject`. It holds `weak var lm: LocalizationManager?`, wired once from `MenuBarContentView.onAppear` (same pattern already used for `onOpenPreferences`). If `lm` is nil (a right-click landing before the popover's first appearance), menu strings fall back to English literals rather than crashing.

### `eventKitIdentifier` parses the `id` prefix — don't change the prefix scheme without updating it
`MeetingEvent.eventKitIdentifier` (used by "Open in Calendar") strips the `"ek:"` prefix that `EventKitSource.toMeetingEvent(_:EKEvent)` puts on the `id`. It intentionally does NOT add a new stored property for this — if `EventKitSource`'s id-prefixing convention (`"ek:"` / `"reminder:"`) ever changes, this computed property needs to change with it.

### "Open in Calendar" uses an undocumented URL scheme
`MeetingURLOpener.openInCalendar` opens `ical://ekevent/<identifier>`. This is **not** a public Apple API — it's a widely-reported-working but undocumented Calendar.app URL scheme. If it silently stops working after a macOS update, this is why; there's no public alternative as of this writing.

### Themed colors go through `settings.theme.accents`, not static Tokens
The accent layer (blobs/dots, pill, hero tints, join-button fill, brand gradient) lives in `AppTheme.Accents` (Theme.swift) and is read as `settings.theme.accents.<name>` via `@EnvironmentObject var settings`. Do NOT reintroduce these as `Tokens` statics: SwiftUI skips re-rendering sub-structs whose stored inputs didn't change, so a static-token color swap doesn't reliably propagate — the ObservableObject path does. Neutral surfaces/ink stay in `Tokens` and are intentionally theme-independent; light/dark remains a separate axis handled inside each `Accents` color via dynamic NSColor providers. The full-screen overlay can't use the environment (see AppKit gotcha above), so `AlertScheduler` passes `settings?.theme ?? .sunset` by value into `OverlayWindowController.show(theme:)` at fire time — a theme change while an overlay is up applies from the next alert. The overlay mesh maps sunset→`.sunset`, ocean→`.cool`, forest→`.forest` (the latter two existed unused in `MeshBackground.Palette` since v1). Default is `.sunset`, which byte-for-byte matches the pre-theming colors — existing users see no change.

### RSVP filter is scheduler-only and fails open
`MeetingEvent.rsvp` drives the `onlyAcceptedMeetings` overlay filter in `AlertScheduler.reschedule` — not `CalendarAggregator`, so tentative/declined meetings stay visible in the popover agenda; only their overlay/lead notification is suppressed. RSVP defaults to `.unknown` and only `.tentative`/`.declined` are filtered, so anything the source can't classify (organizer, local/personal calendars, EventKit's `isCurrentUser` not matching) still fires — the filter never hides a meeting it isn't sure about. EventKit's `isCurrentUser` match is unreliable for some account types; that's the accepted tradeoff for failing open.

---

## Versioning

- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `slapss.xcodeproj/project.pbxproj` (two occurrences each — Debug + Release).
- Always bump both together. Always ask Can for the version number first.
- Current version: **1.8.2** (build 15)

---

## Changelog log

Brief record of what shipped in each version. Full user-facing changelog is in `slapss-web/changelog.html`.

- **v1.8.2** — Fixed the full-screen alert's Snooze button appearing to do nothing on macOS 27 beta 3. The duration picker no longer uses SwiftUI `.popover` (a separate system-managed window that can be suppressed behind the app's borderless `.screenSaver`-level overlay); it is now an in-window dropdown rendered inside `AlertView`. Snooze scheduling behavior is unchanged. Fixed the macOS calendar catalog staying stale after a Calendar account was removed and re-added while Slapss remained open: `CalendarAggregator` now fingerprints and refreshes the EventKit catalog on store-change notifications, the 30-second safety-net, Settings appearance, and app reactivation. Permission changes are re-read on the same paths. Calendar-selection persistence is intentionally untouched: empty still means all calendars, while an explicit non-empty ID set remains explicit even if an account re-add changes identifiers, so newly discovered calendars are not silently enabled. Catalog publishing remains deduplicated to avoid unnecessary SwiftUI/scheduler work; the repeating safety-net timer now runs in `.common` mode.
- **v1.8.1 (UX review pass, Can's call: stays on 1.8.1, no version bump)** — Design-critique fixes across all four surfaces. **Popover:** agenda area now scrolls — `regularView` wraps the permission/agenda switch in a `ScrollView` whose height tracks measured content via `.onGeometryChange` (requires Xcode 16 SDK; back-deploys fine) up to `MenuBarContentView.agendaMaxHeight = 560pt`, header/footer stay pinned; short days render identically to the old intrinsic layout. `AgendaRow.expanded` lifted from local `@State` to `MenuBarContentView.expandedEventIDs: Set<String>` (binding via `expandedBinding(for:)`) so the reworked `NoUpNextLine` — now a real Button with hover fill + rotating chevron — can toggle the referenced meeting's row. `HideReminderBar` moved from above the hero into `agendaSections` below the hero (secondary action, shouldn't own the top slot). Reminder-complete button hit area widened to ~24pt with the `.padding(6).contentShape(Rectangle()).padding(-6)` trick (no layout shift). Header date now uses `setLocalizedDateFormatFromTemplate("EEEMMMd")` so element order follows the locale (TR: "13 Tem Pzt"). `TickClock` switched off `Timer.scheduledTimer` to the `.common`-mode pattern (per the App Nap gotcha — the menu bar counter froze while menus were open). **Overlay:** Join/Complete CTA is now themed — `AppTheme.Accents` gained `overlayCtaTop/Bottom` (sunset orange 0xE8732A→0xC2571F, ocean blue, forest green; was hardcoded green 0x2da14a for all themes — note sunset users see orange now, Can approved). New `keyboardHint` line under the actions ("↩ Join · esc Dismiss", reuses existing action-label keys, ↩ half hidden when no primary button). Status pill now says MEETING for calendar events (new `alert.status.meeting` key ×6 languages); REMINDER only for EKReminders. **Settings:** caption rows added under the lead-time picker, the overlay slider, and `onlyAcceptedMeetings` (new keys `settings.leadTime.caption`, `settings.alert.showEarly.caption`, `settings.alert.onlyAccepted.caption` ×6); Calendars tab no longer dead-ends without permission — mirrors the popover's notDetermined/denied states with request/System Settings buttons. **Onboarding:** step badge numbers computed from `visibleSteps` (`StepID` enum) instead of hardcoded — previously showed gaps (1,2,3,4,6,7,8) when the Microsoft or calendar-picker step was hidden; `MicrosoftStep` now takes `number:` as a param. Numbers renumber live when a gated step appears — intended. Overlay `timeString` intentionally stays on the system locale (12/24h preference); only date *words* follow `lm.language`. **Post-review fix:** Settings window opened BEHIND other apps' windows — since macOS 14 `NSApp.activate(ignoringOtherApps:)` is *cooperative* (may be deferred/ignored) and nothing else forces an accessory app's new window front. `MenuBarContentView.bringSettingsWindowToFront()` runs one tick after `openSettings()` (when the window is registered in `NSApp.windows`), finds it by identifier `contains("Settings")` — the observed-but-undocumented `com_apple_SwiftUI_Settings` — with a titled-visible-non-onboarding structural fallback, then `makeKeyAndOrderFront` + `orderFrontRegardless`. The right-click context menu's Preferences item now routes through the same `openPreferences()` instead of duplicating the open logic.
- **v1.8.1** — Overlay lead time rebuilt as a **discrete slider** (fourth design; Can rejected the TextField+unit-Picker version on UX grounds after it briefly landed — the three earlier iterations were an extended dropdown, a preset-list+stepper, and the field+unit picker, all in git history). The "Show alert:" row in `SettingsView` (Alert section) is a `LabeledContent` containing a right-aligned `VStack`: a live secondary-text label ("30 seconds before" / "5 minutes before" / "At meeting start") above a 200pt `Slider`. The slider has 17 evenly spaced detents — `SettingsView.overlayLeadSteps = [0, 30] + (1...15).map { $0 * 60 }` — i.e. at start, 30 s, then 1–15 whole minutes (15 min is Can's cap for the full-screen alert). Key design point: the `Binding<Double>` maps slider position to a step *index*, not seconds, so detents stay uniform even though the value space isn't linear. Still backed by the same `overlayLeadTimeSeconds: Int` setting, so `AlertScheduler.scheduleStart` needed no change. Legacy stored values that don't fall on a detent (e.g. 45 s free-typed in the short-lived field design) snap to the *nearest* step on read (`overlayLeadStepIndex`) — derive-on-read, no migration. The live label doubles as `accessibilityValue` on both the slider and the row, satisfying Can's standing requirement that a number is never shown or announced without its unit. Localization: the slider reuses the existing `settings.alert.early.{0,secondsFormat,minutesFormat}` keys; the now-unused `early.{secondsUnit,minutesUnit}` keys were removed from all 6 languages. Onboarding untouched — it only has the *notification* lead picker (`leadTimeMinutes`), not the overlay one. Originally prompted by user feedback: someone needed a longer walk-to-room lead than the old 1-min max.
- **v1.8** — Theme support (Can's call: ships as part of 1.8, no version bump): `AppTheme` (sunset = original look and default, ocean, forest) persisted as `AppSettings.theme`; accent tokens moved from static `Tokens` to `AppTheme.Accents` consumed via `settings.theme.accents` (see gotcha); overlay `MeshBackground` palette now theme-driven (previously hardcoded `.sunset` in the removed `AlertState.palette`), passed by value through `OverlayWindowController.show(theme:)`; `ThemeSwatchPicker` in Settings (new Theme section under Language) and onboarding (new step 2, later steps renumbered 3–8); theme names + picker strings localized in all 6 languages; onboarding `NumberBadge`'s hardcoded brown ink replaced with themed `pillInk` (same value in sunset). Plus UX pass (13 items): manual "Presenting Now" toggle (`AlertScheduler.presentingModeEnabled`, footer + status-menu item) suppresses/queues the overlay instead of Focus-based detection (entitlement risk, see gotcha above); lead-time notifications gained a localized "Join" `UNNotificationAction` (`NotificationManager.registerCategories`, handled in `AppDelegate`); overlay responds to Return/Enter via `OverlayWindow.onPrimaryAction`; permission-denied states (popover + onboarding + settings) got a one-click "Open System Settings" button (`SystemSettingsOpener`); onboarding's Get Started no longer requires EventKit permission when Microsoft 365/Exchange is signed in; `StatusMenuController` and `NotificationManager` fully localized (previously hardcoded English); agenda row expand/collapse rebuilt as a real `Button` sibling to the reminder-complete button (was nested inside an `onTapGesture`, invisible to VoiceOver/keyboard) plus a cursor fix; popover header date now locks its `DateFormatter` to `lm.language` instead of system locale; Settings split "About" into its own tab; overlay glass card respects Reduce Transparency; new "Open in Calendar" button on agenda rows (`MeetingEvent.eventKitIdentifier`, `MeetingURLOpener.openInCalendar` — undocumented URL scheme, see gotcha); empty-agenda state redesigned with icon + subtitle; duration strings ("30m" / "1h 15m") localized — `MeetingEvent.durationString` changed from a computed property to `durationString(lm:)` since the model has no environment access, using new `duration.hoursMinutes` / `duration.hoursOnly` / `duration.minutesOnly` format keys (`relativeStartString` is unused elsewhere and was left as-is). Post-release addition (Can's call: stays on 1.8, no version bump): menu bar icon now uses the Slapss brand mark (fist + motion lines) instead of the SF Symbol bell fallback — added `MenuBarIcon.imageset` (1x/2x PNG, `template-rendering-intent: template` in Contents.json) to `Assets.xcassets`, generated as a monochrome silhouette cropped from `AppIcon.appiconset/icon_512x512.png`. No Swift changes needed: `MenuBarLabel.menuBarLogoImage` (ContentView.swift) already looked up `NSImage(named: "MenuBarIcon")` and set `isTemplate = true`, so it was only ever missing the asset. Template rendering means macOS recolors it automatically for light/dark menu bars — no manual dark-mode handling required.
- **v1.7** — `onlyAcceptedMeetings` setting (default off): overlay filter that skips meetings the user marked tentative/declined; `rsvp` added to `MeetingEvent`, populated from Graph `responseStatus.response` and EventKit `participantStatus` (via the `isCurrentUser` attendee); filter is scheduler-only so tentative meetings still show in the agenda. Missed-fire staleness grace: `fireMeetingStart` skips meetings whose effective start was missed by more than 10 min (fixes the morning overlay flood after overnight sleep), measured from effective start so snooze re-fires aren't suppressed.
- **v1.6** — Background CPU fix: `PopoverVisibilityMonitor` gates animations on real popover visibility; Reduced Motion accessibility support in all animated views (`BlobsBackground`, `FloatingDotsBackground`, `MeshBackground`, `PulsingDot`, hero pill); "1 minute before" option added to overlay lead time picker; About section: personal email removed, website (slapss-app.com) and support (info@slapss-app.com) added; version display shows only marketing version without build number; onboarding: language selection added as step 1, "1 minute" option added to lead time picker, all step numbers updated
- **v1.5** — Full-screen overlay for Reminders; in-app reminder completion from overlay and popover
- **v1.4** — Multi-language support (6 languages); expandable agenda rows; configurable overlay lead time; CPU leak fix in `refreshEventKitOnly`
- **v1.3** — Calendar filter seeded at launch (bug fix); hero/menu-bar consistency; Google Meet `authuser` per calendar; multi-display overlay; optional menu-bar text
- **v1.2** — Menu bar fallback icon changed from hand to bell; full-screen card layout fix; ESC to dismiss overlay
- **v1.1** — Alert scheduling reliability (App Nap, watchdog, missed-fire recovery, pending queue); mirrored text fix
- **v1.0** — Initial release
