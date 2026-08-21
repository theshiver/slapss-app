# Releasing Slapss

The maintainer's checklist. Slapss ships through the Mac App Store; this
repository is the public source mirror of what shipped. Both have to stay in
step, and the order below is what keeps them there.

**Working copy:** `~/Projects/slapss/slapss-public` → `theshiver/slapss-app` (public).

> `theshiver/slapss-app-archive` is a **read-only archive** of the pre-open-source
> history, kept private because it still contains commits authored from a
> corporate email address. Its working copy was deleted from
> `~/Projects/slapss` on 2026-08-21, since a folder named `slapss-app` sitting
> next to the real one was a standing trap. Don't clone it back into that
> workspace; if you need it for a history lookup, clone it elsewhere and don't
> develop in it.

---

## Before you start

Decide the version number. Nothing else in this document works until you have
it. Two values, both in `slapss.xcodeproj/project.pbxproj`, each appearing twice
(Debug and Release) — **all four must be updated together**:

| Setting | Meaning | Example |
|---|---|---|
| `MARKETING_VERSION` | User-visible version. **This is the one you bump.** | `1.8.3` |
| `CURRENT_PROJECT_VERSION` | Ignored in practice — see below | `15` |

Both occurrences of `MARKETING_VERSION` (Debug and Release) must be updated
together. CI enforces that they agree and that the git tag matches.

**Don't bother with `CURRENT_PROJECT_VERSION`.** Xcode Cloud assigns build
numbers itself, sequentially per product, overriding the project setting. The
committed value is `15` while App Store Connect has already shipped build 17.
The live counter is at App Store Connect → Xcode Cloud → Settings → **Build
Number**, where it can also be reset if it ever needs to jump.

---

## 1. Code and docs — one commit, together

1. Make the change.
2. Bump both version settings (all four occurrences).
3. **`CHANGELOG.md`** — add a `## vX.Y.Z — Month D, YYYY` entry at the top.
   Plain user language, no implementation detail. This is the source of truth
   everything else is copied from.
4. **`CLAUDE.md`** — add the engineering record to the *Changelog log* at the
   bottom. Different audience: this one is allowed to be technical, and should
   explain *why*, not just *what*. If the change relied on a non-obvious macOS
   or SwiftUI behaviour, add it to *Non-obvious patterns and gotchas* too.
5. Commit and push to `main`.

The **Build** workflow runs on every push. Let it go green before continuing.

## 2. Tag

```bash
git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z
```

This fires the **Release check** workflow, which fails if the tag disagrees with
`MARKETING_VERSION`, if Debug and Release have drifted, or if `CHANGELOG.md` has
no matching entry.

If it fails, delete the tag, fix, and re-tag:

```bash
git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z
```

## 3. Build and submit — Xcode Cloud → App Store Connect

1. **Xcode Cloud starts automatically when the tag lands.** The *Default*
   workflow is triggered by **Tag Changes → tags beginning with `v`** — not by
   branch pushes. This is deliberate: the Archive action has *Distribution
   Preparation = App Store Connect*, so a branch trigger would attempt an App
   Store delivery on every commit, including documentation-only ones and merged
   pull requests, and each would bounce with `ITMS-90062` / `ITMS-90186`. Plain
   compile coverage is GitHub Actions' job, on every push.
2. App Store Connect → select the build → submit for review.
3. Wait for approval, then release.

Build numbers are assigned by Xcode Cloud, not by you — see *Before you start*.

> ### If pushes stop triggering builds
>
> This bit once already, on the day the repository went public, and the failure
> is silent — pushes succeed, GitHub CI goes green, and Xcode Cloud simply never
> runs.
>
> **Cause.** Xcode Cloud connects through a GitHub App installation that tracks
> the repository by **internal ID, not by URL**. When the original private
> repository was renamed to `slapss-app-archive` and a brand-new repository was
> created at the old name, the installation followed the *rename* — so it stayed
> attached to the archive. The URL shown in App Store Connect still read
> `https://github.com/theshiver/slapss-app.git` and looked correct, because it
> is stored as a plain string that happened to match the new repository's URL.
> Nothing indicated a problem.
>
> **Fix.** In App Store Connect → your app → Xcode Cloud → Settings →
> Repositories, re-enter and save the repository URL. That forces Xcode Cloud to
> re-resolve the name and bind to the new repository's ID. Builds resume
> immediately.
>
> **Check first**, at <https://github.com/settings/installations> → Xcode Cloud →
> Configure: if "Repository access" is set to *Only select repositories*, the
> public `slapss-app` has to be in that list.
>
> The same trap applies to any future rename, transfer, or recreation of the
> repository. Renaming a repo on GitHub is not a no-op for Xcode Cloud.

## 4. GitHub Release

Only after the App Store version is **live**. Releasing here first advertises a
version users can't install yet.

<https://github.com/theshiver/slapss-app/releases/new>

- **Tag:** pick the existing `vX.Y.Z` — don't create a new one.
- **Title:** `vX.Y.Z`. Nothing more; the summary belongs in the body.
- **Description:** the `CHANGELOG.md` entry, plus the App Store install link.
- **Release label:** `None`. Pre-release is only for beta/RC tags.
- **Do not attach binaries.** The only official build is the App Store one —
  see [`TRADEMARK.md`](TRADEMARK.md). An unsigned `.app` here would contradict
  that and generate Gatekeeper support mail.
- Don't use *Generate release notes*; on this history it produces nothing useful.

## 5. Marketing site — separate private repo

`~/Projects/slapss/slapss-web` (private, Cloudflare).

Copy the `CHANGELOG.md` entry into `changelog.html`, matching the existing
markup. Update other pages only if the release genuinely changed what they say
(privacy, system requirements, feature copy).

**There is no deploy step.** Cloudflare builds and publishes from the connected
repository on every push to `main`, so committing and pushing *is* the deploy.
Nothing in that repo shows this; the wiring is in the Cloudflare dashboard.

This step is numbered last but is not bound to the order above. Announcing a
release on the site before the App Store build is approved is fine, and was done
deliberately for 2.0.0. The GitHub Release is the one that has to wait, because
it reads as "this build is available".

---

## The short version

```
edit → bump 4 version values → CHANGELOG.md → CLAUDE.md → push
  → Build green
  → tag + push tag → Release check green
  → Xcode Cloud build → App Store Connect → submit → live
  → GitHub Release (tag, title, changelog body, label None, no binaries)

slapss-web/changelog.html → push to main (Cloudflare publishes it; may run ahead)
```

## Things that go wrong

**Tag pushed before the version bump.** Release check catches it. Delete the
tag, bump, re-tag.

**`ITMS-90062` / `ITMS-90186` — version already approved, train closed.** You
tried to deliver a build under a `MARKETING_VERSION` that App Store Connect has
already approved. Bump `MARKETING_VERSION` — the build number is not the
problem, Xcode Cloud already increments that on its own.

**Shipping under the current version.** Sometimes the right call for a small
fix. Then don't invent a new version: amend the existing `CHANGELOG.md` entry
and the existing GitHub Release rather than creating new ones, and record the
decision in `CLAUDE.md`.

**Building from source is Xcode 26+.** The project sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Older Xcode ignores it silently and
fails with a wall of actor-isolation errors. See the gotchas in `CLAUDE.md`.

**Accidentally working in the archive.** No longer possible by accident, since
its working copy is gone. If you do clone it again, check `git remote -v` before
committing: its push remote is `no-push://archive-read-only` and fails on
purpose, so work done there silently never ships.
