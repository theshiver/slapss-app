# Slapss — Claude Project Context

macOS menu bar app (SwiftUI + AppKit hybrid). Shows meetings from macOS Calendar / Exchange and fires a full-screen overlay alert at meeting start. Distributed via App Store.

Two repos:
- `slapss-app` — macOS app (this repo). **Public**, Apache-2.0. See `CONTRIBUTING.md`.
- `slapss-web` — marketing site on Cloudflare. **Private repo**; a push to its `main` deploys the live site. The user-facing changelog is served from it at <https://slapss-app.com/changelog.html>.

`CHANGELOG.md` in this repo is the source of truth for user-facing release notes; `changelog.html` and GitHub Releases are copied from it. `ENGINEERING-LOG.md` is the separate engineering record — different audience, keep both.

---

## Rules

- **Never bump version numbers without asking Can first.** He decides the version.
- **Release process is in `RELEASING.md`.** Follow it in order; the ordering is what keeps the App Store, the tag, the GitHub Release, and the marketing site in step.
- **After every user-visible change, update `CHANGELOG.md` first**, then mirror it into `slapss-web/changelog.html` (separate private repo). Record the engineering detail in `ENGINEERING-LOG.md`.
- Touch `slapss-web` only for the changelog, or when a change alters privacy, support, or feature copy (see the impact map in the workspace `CLAUDE.md`).

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
- Use `PopoverVisibilityMonitor.isVisible` instead. It must watch **occlusion**: the hidden window never sends `willClose` either, and until 2.2.0 the monitor relied on it, so `isVisible` stuck at true after the first open.
- Gating isn't enough on its own. A `.repeatForever` curve also loops on the way *back* (value → false), so give the "off" direction a finite animation; and a `repeatForever` rotation survived opacity 0 and a nil animation, so remove such a view from the hierarchy when inactive (`GlowRing` does). Check with the demo mode: open and close the popover and read `ps -o %cpu`, which should drop to 0.

### Color.clear flips NSView coordinate system on macOS
In a `ZStack` on macOS, `Color.clear`'s NSView backing can leak a flipped coordinate context into sibling views, mirroring glyphs. Always use `.frame(maxWidth: .infinity, maxHeight: .infinity)` to expand a transparent area. Never use `Color.clear` as a spacer in a ZStack.

### Timer.scheduledTimer is App Nap-vulnerable
Menu-bar apps are aggressively enrolled in App Nap. `.scheduledTimer` is added to `.default` runloop mode, which the OS throttles or suspends. Always use `Timer(...) + RunLoop.main.add(timer, forMode: .common)`. `GraphSource.startPollTimer` was the last holdout in the codebase and was converted in 2.0.1 — it matters most there, because a Microsoft 365-only user never starts EventKit's 30-second poll (it is gated on calendar permission), so the Graph timer is their only refresh path.

### refreshEventKitOnly must cancel its previous Task
Any async Task started on a repeating timer must store its handle and cancel before starting a new one. If EventKit is slow, tasks accumulate and each completion triggers a full Combine cascade, growing CPU unboundedly over days.

### AppKit-hosted views don't inherit SwiftUI environment
`OverlayWindowController` builds `NSHostingView` directly. SwiftUI `environmentObject` values are not propagated automatically — must be passed explicitly: `rootView.environmentObject(lm)`.

### OverlayWindow must become key for ESC to work
A borderless `NSWindow` (`.borderless` style) cannot become key by default. `OverlayWindow` overrides `canBecomeKey` and `canBecomeMain` to `true`, and `slapssApp.activate(ignoringOtherApps: true)` is called before `makeKeyAndOrderFront`. On dismiss, the previously frontmost app is reactivated.

### Overlay controls that expand must stay inside the overlay window
The full-screen alert runs in a borderless `.screenSaver`-level `NSWindow`. SwiftUI `.popover`, `Menu`, system tooltips, and similar presentations can create separate system-managed windows that macOS may place behind or suppress relative to the overlay. Render expanded controls directly in `AlertView` with an in-window `.overlay` instead. The snooze dropdown follows this pattern; the attendee tooltip does too.

### Overlay motion: spin with Core Animation, don't redraw per frame
The overlay is full-screen, possibly on several displays, so any per-frame redraw costs real CPU. The first 2.2.0 `GlowRing` recomputed and re-blurred an `AngularGradient` inside a `TimelineView` and doubled the app's CPU in the live state; spinning a fixed gradient with a `repeatForever` rotation under a mask fixed it. `MeshBackground`'s `TimelineView` is the one deliberate per-frame redraw (20 fps, paused under Reduce Motion). Measure with the demo overlay before adding another. Also: `hide()` fades windows out *before* teardown and empties `windows` first. Keep that ordering, or a `show()` arriving during the fade gets its fresh windows torn down.

### Debug demo mode, and what an unsigned Debug build does to your settings
`DemoMode.swift` (Debug builds only) has two launch flags: `-SlapssDemoData <seconds>` replaces the calendar with a fixed demo day (hooked into `CalendarAggregator.start/performRefresh/refreshEventKitOnly`; the real scheduler runs on it, so its overlay fires too), and `-SlapssDemoOverlay <seconds>` shows the alert for a fake meeting (negative = live/late). Either flag skips onboarding. Theme and language come from UserDefaults' argument domain (`-slapss.theme forest`, `-slapss.appLanguage tr`). Numbers are parsed by hand, because the argument domain reads `-297` as the next flag.

**The popover can't be opened from inside the app.** The MenuBarExtra's `NSStatusBarButton` has no target/action, and SwiftUI ignored `performClick`, NSEvents (sent or posted), and a CGEvent posted to our own pid. It needs a real click on the icon. With demo data on, each open prints `SLAPSS_POPOVER_WINDOW <id>`, and `screencapture -o -l <id>` then captures only the popover. The app also owns several `NSStatusBarWindow`s parked off-screen at y = -33, so a status-window search has to filter on screen position.

`-SlapssDemoPopover` (with demo data) also shows the popover content in a borderless window under the menu bar, capturable with no click; its chrome is approximated. After an icon change, a Debug build may still show the old icon in the popover header and onboarding: LaunchServices caches it per bundle id. `lsregister -f <app>` on the built app fixes it.

For video, record the demo app's windows with ScreenCaptureKit (`SCContentFilter(display:including:[app])`), not `screencapture -v`: it starts before the alert window exists, so the entrance is caught, and it works with the screen locked. The tool and the store/site render scripts live in the workspace's `store-assets/<version>/tools`.

A `CODE_SIGNING_ALLOWED=NO` build runs **without the sandbox**, so it reads and writes `~/Library/Preferences/com.cancetin.slapss.plist` instead of the container: empty settings, and that plist is left behind. Delete it afterwards; the real app never reads it.

### `@Published` emits before the property changes
A `settings.$foo.sink` runs in `willSet`: inside it, `settings.foo` still holds the **old** value. `AlertScheduler`'s settings sinks call `reschedule`, which reads `settings`, so a change there applies only on the next 30-second poll. Harmless so far, but a sink that must act on the new value immediately needs the value passed in, or `.receive(on: DispatchQueue.main)` (as `$alertExcludedKeywords` has since 2.2.1).

### Testing a Debug build while another copy runs
Two running processes named `slapss` confuse System Events: it resolves both to the first pid, so AppleScript/JXA reads and clicks land in the wrong app, and ⌘, goes to whichever is frontmost. Quit the other copy first. Also: `defaults read/write com.cancetin.slapss` targets the App Store build's sandbox container once one exists, not the plist an unsigned Debug build uses; seed Debug values through the argument domain instead (`-slapss.alertExcludedKeywords '(Lunch, "Focus time")'`; quote anything with a space or the whole value silently parses as a string).

### One design language since 2.2.0, built from three shared pieces
The alert, popover, onboarding and Settings share: `meshCard(theme:cornerRadius:energy:animating:)` and `ctaFill(_:cornerRadius:enabled:)` (Theme.swift), and `glassSurface(cornerRadius:fill:)` + `Tokens.edgeTop/edgeBottom` (ContentView.swift). New surfaces should use these rather than restyling locally. The mesh appears only on "brand moment" cards (popover hero, onboarding welcome, About banner, theme swatches); lists stay calm. Settings keeps the native grouped `Form` on purpose. Every animated mesh takes an `animating` flag tied to real visibility: `PopoverVisibilityMonitor` in the popover, `controlActiveState == .key` in windows.

### The app icon is an Icon Composer file
`slapss/AppIcon.icon` (hand-written `icon.json` + `Assets/`), no `.appiconset`. Xcode 26 compiles it into a layered Liquid Glass icon for macOS 26 and flattened images for older systems, so it needs no deployment-target change. Edit it in Icon Composer (Xcode → Open Developer Tool) and rebuild; check `Assets.car` with `assetutil --info` for both `IconGroup` and `Icon Image` renditions.

### Calendar filter is not auto-seeded at launch
`CalendarAggregator.start(enabledEventKitCalendars:enabledGraphCalendars:)` must receive the persisted selection from `AppSettings` to seed the source filters before the first fetch. An empty set in `EventKitSource` means "all calendars."

### MenuBarExtra window identification
`menuBarExtraWindows()` identifies the popover window by three properties: no `.titled` style mask, level above `.normal`, and top edge near the menu bar. This same heuristic is used by `PopoverVisibilityMonitor`. Don't change one without the other.

### Presenting Now is intentionally manual, not detected
v1.8 originally scoped "suppress the overlay while screen sharing" using `INFocusStatusCenter` (Focus/DND detection). Abandoned before implementation: that API requires a restricted `com.apple.developer.focus-status` entitlement that needs separate approval from Apple (like CarPlay), not a self-serve Xcode capability — too risky to gate a shipping feature on. There is also no reliable *public* API to detect "this screen is being captured by another app" on macOS (Zoom/Teams/Meet each implement capture differently). Shipped instead as `AlertScheduler.presentingModeEnabled` — a session-only (never persisted) manual toggle. Every `fireMeetingStart` call is redirected into `pendingAlerts` while it's on, using the same FIFO that handles back-to-back meetings, and drained via `togglePresentingMode()` when switched off. If Apple's Focus Status entitlement becomes self-serve in the future, revisit — it would be a strictly better UX than remembering to flip a toggle.

### StatusMenuController is localized via a borrowed weak reference
`StatusMenuController` is a plain AppKit singleton instantiated before any SwiftUI environment exists, so it can't use `@EnvironmentObject`. It holds `weak var lm: LocalizationManager?`, wired once from `MenuBarContentView.onAppear` (same pattern already used for `onOpenPreferences`). If `lm` is nil (a right-click landing before the popover's first appearance), menu strings fall back to English literals rather than crashing.

### EventKit reuses one identifier for every occurrence of a recurring event

`EKEvent.eventIdentifier` is identical for Monday's stand-up and Tuesday's, so `toMeetingEvent` appends `"#<occurrence-start-epoch>"` to `MeetingEvent.id`. Without the suffix everything keyed by that id (`dismissedIDs`, `snoozeUntil`, `menuBarMutedIDs`, `scheduledEffectiveStart`) treats a whole series as one item: `dismissedIDs` is **insert-only and never cleared**, so dismissing one occurrence silences every future one, while the menu-bar countdown (which reads `aggregator.upcomingMeetings` with no dismissal filter) keeps looking correct. Microsoft Graph was never affected: `calendarView` expands series into per-occurrence objects with distinct ids.

Consequences:
- A detached instance moved to a different time gets a new id. That's intended — it's a different slot and deserves its own alert.
- `dismissedIDs` grows by roughly one entry per dismissed occurrence over long uptimes. Deliberately **not** pruned against the current meeting set: a transient EventKit fetch hiccup would resurrect an alert the user already dismissed, which is worse than a set of short strings.
- `eventIdentifier` can still be nil, in which case the id falls back to a fresh `UUID()` on every fetch. Pre-existing and untouched; only affects unsaved events.

### `eventKitIdentifier` parses the `id` prefix AND the occurrence suffix — don't change either scheme without updating it
`MeetingEvent.eventKitIdentifier` (used by "Open in Calendar") strips both the `"ek:"` prefix and the trailing `"#<occurrence-epoch>"` that `EventKitSource.toMeetingEvent(_:EKEvent)` puts on the `id`. It uses `lastIndex(of: "#")` so an identifier that itself contains `#` survives intact. It intentionally does NOT add a new stored property for this — if `EventKitSource`'s id-prefixing convention (`"ek:"` / `"reminder:"`) ever changes, this computed property needs to change with it.

### "Open in Calendar" uses an undocumented URL scheme
`MeetingURLOpener.openInCalendar` opens `ical://ekevent/<identifier>`. This is **not** a public Apple API — it's a widely-reported-working but undocumented Calendar.app URL scheme. If it silently stops working after a macOS update, this is why; there's no public alternative as of this writing.

### Themed colors go through `settings.theme.accents`, not static Tokens
The accent layer (mesh card bases, pill, hero tints, the gradient CTA) lives in `AppTheme.Accents` (Theme.swift) and is read as `settings.theme.accents.<name>` via `@EnvironmentObject var settings`. Do NOT reintroduce these as `Tokens` statics: SwiftUI skips re-rendering sub-structs whose stored inputs didn't change, so a static-token color swap doesn't reliably propagate — the ObservableObject path does. Neutral surfaces/ink stay in `Tokens` and are intentionally theme-independent; light/dark remains a separate axis handled inside each `Accents` color via dynamic NSColor providers. The full-screen overlay can't use the environment (see AppKit gotcha above), so `AlertScheduler` passes `settings?.theme ?? .sunset` by value into `OverlayWindowController.show(theme:)` at fire time — a theme change while an overlay is up applies from the next alert. The overlay mesh maps sunset→`.sunset`, ocean→`.cool`, forest→`.forest` (the latter two existed unused in `MeshBackground.Palette` since v1). Default is `.sunset`, which byte-for-byte matches the pre-theming colors — existing users see no change.

### RSVP filter is scheduler-only and fails open
`MeetingEvent.rsvp` drives the `onlyAcceptedMeetings` overlay filter in `AlertScheduler.reschedule` — not `CalendarAggregator`, so tentative/declined meetings stay visible in the popover agenda; only their overlay/lead notification is suppressed. RSVP defaults to `.unknown` and only `.tentative`/`.declined` are filtered, so anything the source can't classify (organizer, local/personal calendars, EventKit's `isCurrentUser` not matching) still fires — the filter never hides a meeting it isn't sure about. EventKit's `isCurrentUser` match is unreliable for some account types; that's the accepted tradeoff for failing open.

### `priorityMeeting` is shared by the menu bar and the popover hero — only the menu bar's horizon is user-configurable
`AlertScheduler.priorityMeeting(now:includeReminders:respectMutes:horizon:)` backs both the menu-bar label (`currentMenuBarMeeting`) and the popover's hero card (`ContentView`), so the two never disagree about which meeting is "current". Its `horizon` parameter (rule 3's upper bound) defaults to 15 minutes and **only `currentMenuBarMeeting` passes a different one**, from `AppSettings.menuBarMeetingVisibility` via `menuBarHorizon(now:)`. Don't widen the default to "fix" the hero card: the card answers "what is happening now", the menu bar answers "what is next today". Two more things that look adjustable and are not — the 5-minute floor on rule 3 is rule 1's promotion boundary (imminent meeting preempts a running one), not a visibility setting; and `.allDay` must clip at start-of-tomorrow because the aggregator's pool spans 24h ahead, so an unclipped horizon surfaces tomorrow's first meeting from a late-evening lookup.

`.off` is handled inside `currentMenuBarMeeting`, not in the view, so it also silences the right-click status menu's meeting title and the popover's "Hide from menu bar" link — both call the same accessor. Intended (there is no label left to hide from), but it differs from the pre-2.1.0 bool, which gated only the label.

---

### "Do we have calendar data?" is not the same question as "do we have EventKit permission?"
`CalendarAggregator.permissionState` mirrors EventKit only — Graph has its own `GraphSource.state`, and `performRefresh` fetches Graph regardless of the EventKit verdict. Any UI that gates on `permissionState` alone strands Microsoft 365 users who never grant Calendar.app access. `OnboardingView.canFinishOnboarding` had the right rule (`granted || isGraphSignedIn`) since 1.8; the popover did not, and until 2.0.1 it replaced a fully working M365 agenda with a red "Calendar access denied" screen while the menu bar — which reads the merged event list and has never been permission-gated — kept showing the same meeting. Reported by a user, 2026-08-25.

### A nested ObservableObject's changes don't reach views that observe only the parent
`CalendarAggregator.graph` is itself an `ObservableObject`. SwiftUI does not forward a nested object's `objectWillChange` to views that observe the parent, so a view holding only `@EnvironmentObject var aggregator` will not re-render when `graph.state` changes. `OnboardingView` works around it with child views that `@ObservedObject` the `GraphSource` directly (`MicrosoftStep`, `GraphCalendarsList`). When the parent itself needs the fact, mirror it instead: `CalendarAggregator.isGraphSignedIn` is a Combine `assign(to:)` mirror of `graph.$state`, added in 2.0.1 for the popover gate. Prefer mirroring over spreading child-view workarounds.

### Build settings can inject entitlements that aren't in the entitlements file

`slapss/slapss.entitlements` lists three, and the shipped binary must carry exactly
those three. The privacy claim is "the entitlements are the whole story", so a reader
who runs `codesign -d --entitlements :-` and counts more than the documents say has
caught the project overstating. `ENABLE_*` build settings inject entitlements at build
time: `ENABLE_USER_SELECTED_FILES` is set to an explicit `NO` in both configurations
(matching the neighbouring `ENABLE_RESOURCE_ACCESS_* = NO`) because `readonly` added
`com.apple.security.files.user-selected.read-only` to builds up to 2.0.0. After
touching capabilities, check a local Release build with `codesign`. `README.md` and
`SECURITY.md` state the count and what older builds carried.

One report that will keep coming back: a copy someone builds themselves also
carries `com.apple.security.get-task-allow`, which Xcode adds to any
non-distribution build so a debugger can attach. App Store builds don't have it.
Both documents say so, because "I built it myself and I count four" is the obvious
next message.


## Versioning

- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `slapss.xcodeproj/project.pbxproj` (two occurrences each — Debug + Release).
- **Only `MARKETING_VERSION` matters for a release.** Bump both its occurrences together, and always ask Can for the number first.
- **`CURRENT_PROJECT_VERSION` is dead weight.** Xcode Cloud assigns the build number itself, sequentially per product, and overrides whatever the project says. The committed value is knowingly behind. Don't bump it, and don't trust it — the real counter lives in App Store Connect → Xcode Cloud → Settings → Build Number.

---

## Engineering log

Per-version engineering record (the *why*, traps hit, what was validated) lives in
`ENGINEERING-LOG.md`. Add to it after every user-visible change, newest first.
