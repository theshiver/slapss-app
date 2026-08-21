# Releasing Slapss

The maintainer's checklist. Slapss ships through the Mac App Store; this
repository is the public source mirror of what shipped. Both have to stay in
step, and the order below is what keeps them there.

**Working copy:** `~/Projects/slapss/slapss-public` → `theshiver/slapss-app` (public).

> The old repository `~/Projects/slapss/slapss-app` is a **read-only archive** of
> the pre-open-source history. It still contains commits authored from a
> corporate email address. Its push remote has been deliberately broken so a
> reflexive `git push` there fails loudly. Don't develop in it, and don't
> re-point its remote.

---

## Before you start

Decide the version number. Nothing else in this document works until you have
it. Two values, both in `slapss.xcodeproj/project.pbxproj`, each appearing twice
(Debug and Release) — **all four must be updated together**:

| Setting | Meaning | Example |
|---|---|---|
| `MARKETING_VERSION` | User-visible version | `1.8.3` |
| `CURRENT_PROJECT_VERSION` | Build number, must increase for every App Store upload | `16` |

CI enforces that Debug and Release agree, and that the git tag matches
`MARKETING_VERSION`. It cannot tell you the number is *right* — that's on you.

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

This is the part that was already your normal routine. It is unchanged, with one
caveat below.

1. Xcode Cloud builds from the tagged commit.
2. App Store Connect → select the build → submit for review.
3. Wait for approval, then release.

> ### ⚠️ Verify this once, before the next release
>
> Xcode Cloud was connected to `theshiver/slapss-app` while that name pointed at
> the **old private repository**. That repository has since been renamed to
> `slapss-app-archive`, and a **different, new repository** now sits at the
> original name.
>
> Which one Xcode Cloud is now attached to depends on whether it tracks the
> repository by ID (→ follows the rename, still building the archive) or by URL
> (→ now building the public repo). **Do not assume.**
>
> Check in App Store Connect → your app → **Xcode Cloud** → **Settings** →
> **Repositories**, and confirm it points at the public `theshiver/slapss-app`.
> If it points at `slapss-app-archive`, re-point it and re-authorize GitHub
> access. Symptom of getting this wrong: pushes to the public repo silently stop
> triggering builds, or Xcode Cloud builds a version of the code that no longer
> matches what's published.

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
(privacy, system requirements, feature copy). Then deploy.

---

## The short version

```
edit → bump 4 version values → CHANGELOG.md → CLAUDE.md → push
  → Build green
  → tag + push tag → Release check green
  → Xcode Cloud build → App Store Connect → submit → live
  → GitHub Release (tag, title, changelog body, label None, no binaries)
  → slapss-web/changelog.html → deploy
```

## Things that go wrong

**Tag pushed before the version bump.** Release check catches it. Delete the
tag, bump, re-tag.

**Build number not incremented.** App Store Connect rejects the upload. Only
`CURRENT_PROJECT_VERSION` has to increase; `MARKETING_VERSION` can stay the same
for a resubmission.

**Shipping under the current version.** Sometimes the right call for a small
fix. Then don't invent a new version: amend the existing `CHANGELOG.md` entry
and the existing GitHub Release rather than creating new ones, and record the
decision in `CLAUDE.md`.

**Building from source is Xcode 26+.** The project sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Older Xcode ignores it silently and
fails with a wall of actor-isolation errors. See the gotchas in `CLAUDE.md`.

**Accidentally working in the archive.** Check `git remote -v`. The archive's
push remote is `no-push://archive-read-only` and will fail on purpose.
