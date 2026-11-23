# Security policy

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Email <info@slapss-app.com> with:

- What the issue is and what an attacker could achieve.
- Steps to reproduce, or a proof of concept.
- The Slapss version and macOS version you tested on.

You'll get an acknowledgement. Slapss is maintained by one person alongside a
full-time job, so please allow reasonable time for a fix before disclosing
publicly. Credit in the release notes if you'd like it.

## Supported versions

Only the current release receives fixes. There are no maintained
older branches.

## Scope notes

Slapss is a sandboxed macOS app with no server component. Its attack surface is
small and worth stating plainly:

- **Entitlements** are limited to the exact 3 entitlements in
  `slapss/slapss.entitlements`: app sandbox (`com.apple.security.app-sandbox`),
  outbound network client (`com.apple.security.network.client`), and calendar
  access (`com.apple.security.personal-information.calendars`). Adding direct
  Google Calendar support does not add any new entitlements (no `network.server`
  or extra access). Verify against a shipped build with
  `codesign -d --entitlements :- /Applications/slapss.app`. Builds up to 2.0.0
  additionally carried user-selected read-only file access, injected by the
  `ENABLE_USER_SELECTED_FILES` build setting and used by no code path; 2.0.1
  removes it. A locally built copy also carries `com.apple.security.get-task-allow`
  (debugger attach), which App Store builds do not.
- **Network egress** goes only to the calendar provider endpoints for accounts
  the user explicitly chooses to connect: Microsoft Graph and Microsoft identity
  endpoints (`graph.microsoft.com`, `login.microsoftonline.com`) for Microsoft 365,
  and Google OAuth and Calendar API endpoints (`accounts.google.com`,
  `oauth2.googleapis.com`, `www.googleapis.com`) for optional direct read-only
  Google Calendar access.
- **Credentials.** Microsoft and Google OAuth tokens are stored locally in the
  system keychain. Both flows use authorization code + PKCE via
  `ASWebAuthenticationSession`; there is no client secret in the app, by design.
- **Calendar data** never leaves the device. There is no backend to send it to.
- The Azure application (client) ID in `slapss/Auth/MSALConfig.swift` and the
  Google OAuth iOS client ID in `slapss/Auth/GoogleOAuthConfig.swift` are public
  client identifiers. They are not secrets: both are designed to be embedded in
  a distributed binary and are extractable from any shipped copy of the app.

Things that are **not** vulnerabilities: reporting either client ID as a "leaked
secret"; reporting the Apple development team ID in the Xcode project; reporting
that a locally-modified build can read your own calendar.
