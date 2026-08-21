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

Only the current App Store release receives fixes. There are no maintained
older branches.

## Scope notes

Slapss is a sandboxed macOS app with no server component. Its attack surface is
small and worth stating plainly:

- **Entitlements** are limited to app sandbox, outbound network client, and
  calendar access (`slapss/slapss.entitlements`).
- **Network egress** goes to Microsoft Graph and Microsoft identity endpoints
  only, and only when the user has signed in to a Microsoft 365 account.
- **Credentials.** Microsoft OAuth tokens are stored in the system keychain. The
  flow is authorization code + PKCE via `ASWebAuthenticationSession`; there is no
  client secret in the app, by design.
- **Calendar data** never leaves the device. There is no backend to send it to.
- The Azure application (client) ID in `slapss/Auth/MSALConfig.swift` is a public
  client identifier. It is not a secret — it is designed to be embedded in a
  distributed binary and is extractable from any shipped copy of the app.

Things that are **not** vulnerabilities: reporting the client ID as a "leaked
secret"; reporting the Apple development team ID in the Xcode project; reporting
that a locally-modified build can read your own calendar.
