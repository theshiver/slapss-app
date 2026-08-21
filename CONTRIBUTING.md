# Contributing to Slapss

Thanks for looking. A few things worth knowing before you spend time on a change.

## Expectations, stated up front

Slapss is maintained by one person who has a full-time job. **There is no
response-time commitment.** Issues and pull requests may sit for a while. This
isn't neglect — it's the honest operating model of the project, and saying so now
is better than leaving you guessing later.

Please open an issue to discuss anything non-trivial *before* writing the code.
It's the cheapest way to avoid work that won't be merged.

## What is likely to be merged

- **Bug fixes** with clear reproduction steps.
- **Translation corrections** for the six supported languages (see below).
- **Accessibility improvements** — VoiceOver labelling, keyboard operability,
  Reduce Motion / Reduce Transparency handling.
- **Compatibility fixes** for new macOS releases.
- **Documentation** fixes, including corrections to `CLAUDE.md`.

## What is unlikely to be merged

- **Architectural refactors.** The SwiftUI + AppKit structure is deliberate and
  documented. See `CLAUDE.md`.
- **New third-party dependencies.** The project has zero, including for the
  Microsoft OAuth flow, and that is a feature. It keeps the privacy claim
  auditable in one sitting.
- **Anything that sends data off the device.** No analytics, no crash reporting,
  no remote config, no "anonymous" usage statistics. Not negotiable — it is the
  entire point of the app.
- **Scope expansion.** New calendar providers, task management, note taking,
  team features. Slapss reminds you about meetings.
- **Replacing a documented workaround** without explaining why the original
  constraint no longer applies. `CLAUDE.md` explains each one; several look
  wrong until you know what they're working around.

## Before you open a pull request

1. **Read `CLAUDE.md`.** Especially "Non-obvious patterns and gotchas". Several
   patterns in this codebase exist to work around real macOS behaviour and will
   silently regress if reverted — `MenuBarExtra` never firing `onDisappear`,
   `Color.clear` flipping AppKit's coordinate system, App Nap throttling
   `Timer.scheduledTimer`, and others.
2. **Make sure it builds.** You need **Xcode 26 or later** — see the note in
   [`README.md`](README.md#building-from-source). Older Xcode fails with
   actor-isolation errors that are a toolchain problem, not a code problem.
   ```
   xcodebuild build -project slapss.xcodeproj -scheme slapss -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
   ```
3. **Keep the diff focused.** One concern per pull request. Don't reformat
   surrounding code.
4. **Don't change version numbers.** `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` in `slapss.xcodeproj/project.pbxproj` are set by the
   maintainer at release time.
5. **Update `CHANGELOG.md`** if the change is user-visible. Plain language, no
   implementation detail.

## Translations

All strings live in `slapss/Localization/Translations.swift` as Swift
dictionaries keyed by language — not `.strings` or `.xcstrings` files. Editing a
Swift dictionary in a pull request is a little awkward, but it works: find your
language's dictionary, fix the value, leave the key alone.

If you add a key, add it to **all six** languages. English is the fallback, so a
missing key degrades to English rather than crashing — but an incomplete
translation is still a bug.

## Licensing of contributions

By submitting a pull request you agree that your contribution is licensed under
the [Apache License 2.0](LICENSE), per § 5 of that license. There is no separate
CLA to sign.

Note that the Slapss name and icon assets are **not** covered by that license.
See [`TRADEMARK.md`](TRADEMARK.md) before publishing a fork.

## Releases

Releases are cut by the maintainer; see [`RELEASING.md`](RELEASING.md) if you're
curious about the process.

## Security issues

Do not open an issue. See [`SECURITY.md`](SECURITY.md).
