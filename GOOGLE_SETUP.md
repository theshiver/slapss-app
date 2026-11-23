# Google setup for Google Calendar

Slapss reads macOS Calendar and Reminders with no configuration at all. If you connect Google Calendar directly in Slapss (instead of syncing it through macOS Calendar), the app talks to the Google Calendar API on behalf of the signed-in user.

**You only need this if you want to sign in with your own Google Cloud OAuth client.** Official Slapss builds already ship with a configured Google Cloud OAuth Client ID (also committed in `slapss/Auth/GoogleOAuthConfig.swift` for building and testing locally).

> **If you publish a fork, register your own OAuth client.** The upstream
> registration is named "Slapss" and that is what your users would see on the
> Google consent screen. Shipping someone else's registration is impersonation,
> and it puts quota or abuse reports on their project rather than yours.

Total time: about 10 minutes.

---

## No SDK to install

Slapss does not use the GoogleSignIn SDK. `GoogleOAuthClient` implements OAuth 2.0 + PKCE directly on `ASWebAuthenticationSession`, `URLSession`, and `CryptoKit`.

**Slapss has zero third-party dependencies.** Please keep it that way.

---

## 1. Create a Google Cloud project and enable the API

1. Go to <https://console.cloud.google.com/> and sign in with a Google account.
2. Create a new project (or select an existing one).
3. Open **APIs & Services** -> **Library**.
4. Search for **Google Calendar API**, open it, and click **Enable**.

---

## 2. Configure Google Auth Platform

1. Open **Google Auth Platform** in the Google Cloud Console.
2. **Branding**:
   - **App name:** your app's name (not "Slapss" if you are publishing a fork).
   - **User support email** and **Developer contact email:** your email address.
3. **Audience**:
   - Select **External**.
   - Leave the publishing status in **Testing** while developing locally.
   - Under **Test users**, add every Google account you want to sign in with during testing. In Testing mode, Google blocks any account not listed here.
4. **Data Access** (Scopes):
   - Add the following scopes:
     - `https://www.googleapis.com/auth/calendar.calendarlist.readonly` (`calendar.calendarlist.readonly`)
     - `https://www.googleapis.com/auth/calendar.events.readonly` (`calendar.events.readonly`)
     - `openid`
     - `email`

Read-only calendar access is deliberate. Slapss only reads your calendar list and events to show upcoming meetings and fire alerts; it never creates, edits, or deletes events.

---

## 3. Create an iOS OAuth client (not Desktop)

1. In Google Auth Platform, go to **Clients** -> **Create client**.
2. Set **Application type** to **iOS**.
3. Set **Bundle ID** to `com.cancetin.slapss` (or your own bundle ID if you changed `PRODUCT_BUNDLE_IDENTIFIER` in Xcode).
4. Click **Create**.
5. Copy the **Client ID** (formatted like `<id>.apps.googleusercontent.com`) and the **iOS URL scheme** (the reversed Client ID, formatted like `com.googleusercontent.apps.<id>`).

### Why iOS instead of Desktop

Even though Slapss is a macOS app, it intentionally uses a Google **iOS** OAuth client rather than a **Desktop** client:

- A **Desktop** client expects a `client_secret` (which cannot remain secret in an open-source client binary) and uses a `http://127.0.0.1:<port>` loopback redirect that requires the `com.apple.security.network.server` entitlement in a sandboxed Mac App Store build.
- An **iOS** client uses Authorization Code + PKCE with a custom URL scheme redirect (the reversed Client ID), requires no `client_secret`, and needs no `network.server` entitlement. `ASWebAuthenticationSession` on macOS handles the custom URL scheme callback natively.

---

## 4. Wire it into the project

Three values have to match each other. If they do not, sign-in fails.

| Value | Where |
|---|---|
| Client ID | `slapss/Auth/GoogleOAuthConfig.swift` |
| Reversed Client ID URL scheme | `CFBundleURLSchemes` in `slapss/Info.plist` |
| Bundle ID | `PRODUCT_BUNDLE_IDENTIFIER` in Xcode and the iOS client in Google Cloud |

1. Put your Client ID in `slapss/Auth/GoogleOAuthConfig.swift`.
2. In `slapss/Info.plist`, update the Google entry under `CFBundleURLTypes` -> `CFBundleURLSchemes` with your reversed Client ID (`com.googleusercontent.apps.<your-client-id-prefix>`).

If you change `PRODUCT_BUNDLE_IDENTIFIER` in Xcode (as any published fork must), make sure the Bundle ID on your Google Cloud iOS client matches it.

---

## 5. Test

1. **Cmd-R** to run.
2. Settings (**Cmd-,**) -> **Calendars**.
3. Click **Connect Google Calendar**. A system Google sign-in sheet appears via `ASWebAuthenticationSession`.
4. Sign in with an account listed under **Test users** in Google Auth Platform.
5. After consent, your Google calendars appear with toggles.

---

## Troubleshooting

**`Error 403: access_denied` ("has not completed the Google verification process")**
Your Google Auth Platform app is in **Testing** mode and the Google account you signed in with is not listed under **Audience** -> **Test users**. Add that email address as a test user and retry.

**Sign-in sheet completes in the browser or shows a redirect error instead of returning to Slapss**
Check that the reversed Client ID in `slapss/Info.plist` (`CFBundleURLSchemes`) exactly matches the Client ID in `slapss/Auth/GoogleOAuthConfig.swift`, and that the Bundle ID in your Google Cloud iOS OAuth client matches `PRODUCT_BUNDLE_IDENTIFIER` in Xcode.

**Sign-in succeeds but no calendars appear**
Confirm that **Google Calendar API** is enabled in your Google Cloud project and that both `calendar.calendarlist.readonly` and `calendar.events.readonly` are configured in Google Auth Platform -> **Data Access**.
