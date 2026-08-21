//
//  MSALConfig.swift
//  slapss
//
//  Static configuration for the Microsoft Authentication Library. The values
//  here come from your Azure AD app registration. See AZURE_SETUP.md in the
//  project root for step-by-step instructions.
//

import Foundation

enum MSALConfig {
    /// Application (client) ID from your Azure AD app registration.
    /// Until this is replaced, sign-in calls will fail with a clear error.
    static let clientID = "1c52fdce-7a73-47a3-935f-67872a5cad6b"

    /// Multi-tenant authority — works with any Microsoft 365 / Entra ID tenant
    /// AND personal Microsoft accounts. If you want to restrict to a single
    /// tenant, replace "common" with your tenant ID.
    static let authorityURL: URL = {
        guard let url = URL(string: "https://login.microsoftonline.com/common") else {
            fatalError("MSALConfig: authorityURL string is malformed — this is a compile-time programming error")
        }
        return url
    }()

    /// Must match (a) the redirect URI registered in Azure AD AND
    /// (b) the CFBundleURLSchemes entry in Info.plist.
    /// Convention: msauth.<bundle-id>://auth
    static let redirectURI = "msauth.com.cancetin.slapss://auth"

    /// Delegated permissions we ask for. Read-only is sufficient for our use
    /// case and reduces consent friction with conservative IT admins.
    static let scopes = ["Calendars.Read", "User.Read"]

    /// True when the placeholder client ID hasn't been replaced.
    static var isPlaceholder: Bool {
        clientID == "REPLACE_WITH_YOUR_CLIENT_ID"
    }
}
