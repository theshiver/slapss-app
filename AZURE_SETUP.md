# Azure setup for Microsoft 365 / Exchange calendars

Slapss reads macOS Calendar and Reminders with no configuration at all. The
Microsoft 365 / Exchange source is the one piece that needs an external setup
step, because it talks to Microsoft Graph on behalf of the signed-in user.

**You only need this if you want to sign in with your own Azure app
registration.** The client ID committed in `slapss/Auth/MSALConfig.swift` is the
upstream one and works for building and testing locally.

> **If you publish a fork, register your own app.** The upstream registration is
> named "Slapss" and that is the name your users would see on the Microsoft
> consent screen. Shipping someone else's registration is impersonation, and it
> puts abuse reports on their account rather than yours.

Total time: about 10 minutes.

---

## No SDK to install

Earlier versions of this document told you to add the Microsoft Authentication
Library (MSAL) via Swift Package Manager. **That is no longer the case, and you
should not add it.**

MSAL's macOS broker flow needs to write into keychain access groups owned by
Microsoft, which a third-party signing identity cannot access — the entitlements
get silently stripped at build time and the broker key write fails with
`MSALErrorDomain -50000`. So `MSALClient.swift` implements OAuth 2.0 +
PKCE directly on `ASWebAuthenticationSession` and `URLSession` instead. The type
keeps the historical name; there is no Microsoft SDK behind it.

The practical upshot: **Slapss has zero third-party dependencies.** Please keep
it that way.

---

## 1. Register the app

1. Go to <https://portal.azure.com> and sign in with any Microsoft 365 account —
   personal or work, both can register apps.
2. Open **Microsoft Entra ID** (formerly Azure Active Directory).
3. **App registrations** → **+ New registration**.
4. Fill in:
   - **Name:** your app's name (not "Slapss" — see the note above).
   - **Supported account types:** *Accounts in any organizational directory
     (Any Microsoft Entra ID tenant — Multitenant) and personal Microsoft
     accounts*. This is the broadest option.
   - **Redirect URI:** platform **Public client/native (mobile & desktop)**,
     URI `msauth.<your-bundle-id>://auth` — e.g. `msauth.com.example.myapp://auth`.
5. **Register**.

Copy the **Application (client) ID** from the overview page. It's a UUID.

### API permissions

1. **API permissions** → **+ Add a permission** → **Microsoft Graph** →
   **Delegated permissions**.
2. Check `Calendars.Read` and `User.Read`.
3. **Add permissions**.

Read-only is deliberate. It's all Slapss needs, and it reduces consent friction
with conservative IT admins.

---

## 2. Wire it into the project

Three values have to agree with each other. If they don't, sign-in fails.

| Value | Where |
|---|---|
| Client ID | `MSALConfig.clientID` in `slapss/Auth/MSALConfig.swift` |
| Redirect URI | `MSALConfig.redirectURI`, **and** the Azure registration |
| URL scheme | `CFBundleURLSchemes` in `slapss/Info.plist` |

```swift
// slapss/Auth/MSALConfig.swift
static let clientID   = "your-client-id-here"
static let redirectURI = "msauth.com.example.myapp://auth"
```

The redirect URI is derived from your **bundle identifier**. If you change
`PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project — and a published fork must —
then you have to update all three places above to match. This is the single most
common way to get this wrong.

To restrict sign-in to one tenant instead of any Microsoft account, replace
`common` with your tenant ID in `MSALConfig.authorityURL`.

---

## 3. Test

1. **Cmd-R** to run.
2. Settings (**Cmd-,**) → **Calendars**.
3. **Connect Microsoft 365**. A system Microsoft sign-in sheet appears — this is
   `ASWebAuthenticationSession`, not an embedded webview.
4. After sign-in, your Microsoft calendars appear with toggles.

---

## Verified Publisher (only if you're shipping)

Many corporate tenants block end-user consent for unverified apps and route users
into an admin-approval queue. Verified Publisher status puts a checkmark on your
consent screen and makes admins far more likely to approve.

It's free and takes roughly a day:

1. Create a [Microsoft Partner Center](https://partner.microsoft.com/) account
   using the Microsoft account that owns your tenant.
2. Complete Cloud Partner Program enrollment and verify your business identity.
3. Associate your MPN ID with your Entra tenant.
4. App registration → **Branding & properties** → **Add Publisher** → enter the
   MPN ID.

Reference: <https://learn.microsoft.com/entra/identity-platform/publisher-verification-overview>

Even with verification, some tenants require explicit admin consent for any
third-party app. Slapss handles this in Settings → Calendars → "Work account
asking for IT approval?", which offers a pre-composed email to IT and a
copyable admin-consent link:

```
https://login.microsoftonline.com/organizations/adminconsent?client_id=<your-client-id>
```

---

## Troubleshooting

**`AADSTS500113: No reply address is registered for the application`**
The redirect URI in Azure doesn't exactly match `MSALConfig.redirectURI` —
including the `msauth.` prefix and the `://auth` suffix. Check all three values
in the table above.

**`AADSTS65001: The user or administrator has not consented`**
The tenant requires admin consent. Either have an admin grant it (app
registration → API permissions → Grant admin consent), or test with a personal
Microsoft account.

**`AADSTS50158` / Conditional Access errors**
The tenant has Conditional Access policies blocking sign-in, e.g. "compliant
device required". This is expected and is a documented limitation — tenant
security policy can only be changed by that tenant's admins.

**Sign-in succeeds but no calendars appear**
Check that `Calendars.Read` is present under API permissions.

**`MSALErrorDomain -50000`**
You added the MSAL SDK. Remove it — see "No SDK to install" above.
