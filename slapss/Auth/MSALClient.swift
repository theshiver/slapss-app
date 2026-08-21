//
//  MSALClient.swift
//  slapss
//
//  Microsoft OAuth client. Despite the historical name, this no longer uses
//  the MSAL SDK — MSAL's macOS broker flow requires writing into shared
//  keychain groups owned by Microsoft, which a third-party signing identity
//  can't access (entitlements get silently stripped at build time → broker
//  key write fails → MSALErrorDomain -50000).
//
//  Instead we implement OAuth 2.0 + PKCE directly:
//   - Authorization request via ASWebAuthenticationSession (Apple's blessed
//     OAuth presentation primitive).
//   - Token exchange + refresh via plain URLSession against the v2.0 endpoints.
//   - Tokens stored in the app's own keychain (no shared group, no extra
//     entitlements required for sandboxed apps).
//
//  Conditional Access, MFA, device challenges — all handled inside the
//  Microsoft login page itself; we just open the URL and capture the redirect.
//

import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

@MainActor
final class MSALClient: NSObject {
    enum SignInError: LocalizedError {
        case notConfigured
        case userCancelled
        case invalidCallback
        case tokenExchange(String)
        case noRefreshToken
        case keychain(OSStatus)
        case network(Error)
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Microsoft sign-in is not configured. Set your Azure client ID in MSALConfig.swift."
            case .userCancelled:
                return "Sign-in cancelled."
            case .invalidCallback:
                return "Couldn't read the response from Microsoft."
            case .tokenExchange(let message):
                return "Token exchange failed: \(message)"
            case .noRefreshToken:
                return "Sign-in expired. Please sign in again."
            case .keychain(let status):
                return "Keychain error \(status)."
            case .network(let error):
                return "Network error: \(error.localizedDescription)"
            case .unknown(let message):
                return message
            }
        }
    }

    /// Persisted token bundle. Stored as a single JSON blob in the keychain.
    private struct Tokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }

    /// Lightweight account descriptor returned to callers. Keeps GraphSource
    /// decoupled from the auth implementation details.
    struct Account: Equatable {
        let username: String?
    }

    private(set) var account: Account?

    private var tokens: Tokens?
    private var session: ASWebAuthenticationSession?

    private let keychainService = "com.cancetin.slapss.msauth"
    private let keychainAccount = "tokens"
    private let displayNameAccount = "username"

    override init() {
        super.init()
        // Restore cached session if any.
        self.tokens = (try? loadTokens())
        if let username = (try? loadUsername()), tokens != nil {
            self.account = Account(username: username)
        }
    }

    var isConfigured: Bool { !MSALConfig.isPlaceholder }
    var isSignedIn: Bool { tokens != nil }

    // MARK: - Sign in / out

    func signIn() async throws {
        guard isConfigured else { throw SignInError.notConfigured }

        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.computeCodeChallenge(verifier: codeVerifier)

        let authURL = buildAuthorizeURL(codeChallenge: codeChallenge)
        let callbackURL = try await presentAuthSession(url: authURL)

        guard let code = extractAuthorizationCode(from: callbackURL) else {
            // The redirect might carry an OAuth error — surface it.
            if let oauthError = extractOAuthError(from: callbackURL) {
                throw SignInError.tokenExchange(oauthError)
            }
            throw SignInError.invalidCallback
        }

        let exchanged = try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
        try saveTokens(exchanged)
        self.tokens = exchanged

        // Pull a display name for the UI.
        if let username = try? await fetchUserPrincipalName(accessToken: exchanged.accessToken) {
            self.account = Account(username: username)
            try? saveUsername(username)
        } else {
            self.account = Account(username: nil)
        }
    }

    func signOut() async throws {
        try? deleteTokens()
        try? deleteUsername()
        tokens = nil
        account = nil
    }

    // MARK: - Silent token

    /// Returns a fresh access token. If the cached token has fewer than 60s
    /// of life left, refreshes it via the refresh_token grant.
    func acquireTokenSilently() async throws -> String {
        guard let cached = tokens else { throw SignInError.noRefreshToken }

        if cached.expiresAt > Date().addingTimeInterval(60) {
            return cached.accessToken
        }

        guard let refreshToken = cached.refreshToken else { throw SignInError.noRefreshToken }
        let refreshed = try await refreshTokens(refreshToken: refreshToken)
        try saveTokens(refreshed)
        self.tokens = refreshed
        return refreshed.accessToken
    }

    // MARK: - Error classification (kept for source-compat with previous API)

    static func classify(_ error: Error) -> SignInError {
        if let typed = error as? SignInError { return typed }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network(error)
        }
        return .unknown(nsError.localizedDescription)
    }

    // MARK: - PKCE

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func computeCodeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    // MARK: - URL building

    private func buildAuthorizeURL(codeChallenge: String) -> URL {
        let endpoint = MSALConfig.authorityURL.appendingPathComponent("oauth2/v2.0/authorize")
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        // offline_access is required to receive a refresh_token for silent renewal.
        let scope = (MSALConfig.scopes + ["offline_access"]).joined(separator: " ")
        components.queryItems = [
            URLQueryItem(name: "client_id", value: MSALConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: MSALConfig.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components.url!
    }

    private func extractAuthorizationCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
    }

    private func extractOAuthError(from url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let err = items.first(where: { $0.name == "error" })?.value else {
            return nil
        }
        let desc = items.first(where: { $0.name == "error_description" })?.value ?? ""
        return desc.isEmpty ? err : "\(err): \(desc)"
    }

    // MARK: - ASWebAuthenticationSession

    private func presentAuthSession(url: URL) async throws -> URL {
        guard let scheme = URL(string: MSALConfig.redirectURI)?.scheme else {
            throw SignInError.invalidCallback
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain &&
                        nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: SignInError.userCancelled)
                    } else {
                        cont.resume(throwing: SignInError.network(error))
                    }
                    return
                }
                guard let callbackURL else {
                    cont.resume(throwing: SignInError.invalidCallback)
                    return
                }
                cont.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            if !session.start() {
                cont.resume(throwing: SignInError.unknown("Couldn't start authentication session"))
            }
        }
    }

    // MARK: - Token endpoints

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> Tokens {
        let scope = (MSALConfig.scopes + ["offline_access"]).joined(separator: " ")
        return try await postTokenRequest(body: [
            "client_id": MSALConfig.clientID,
            "scope": scope,
            "code": code,
            "redirect_uri": MSALConfig.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ])
    }

    private func refreshTokens(refreshToken: String) async throws -> Tokens {
        let scope = (MSALConfig.scopes + ["offline_access"]).joined(separator: " ")
        return try await postTokenRequest(body: [
            "client_id": MSALConfig.clientID,
            "scope": scope,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])
    }

    private func postTokenRequest(body: [String: String]) async throws -> Tokens {
        let url = MSALConfig.authorityURL.appendingPathComponent("oauth2/v2.0/token")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SignInError.unknown("Bad token response")
        }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SignInError.tokenExchange(body)
        }

        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return Tokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }

    private func fetchUserPrincipalName(accessToken: String) async throws -> String? {
        guard let meURL = URL(string: "https://graph.microsoft.com/v1.0/me") else { return nil }
        var req = URLRequest(url: meURL)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Me: Decodable {
            let userPrincipalName: String?
            let mail: String?
            let displayName: String?
        }
        let me = try JSONDecoder().decode(Me.self, from: data)
        return me.userPrincipalName ?? me.mail ?? me.displayName
    }

    private static func formEncode(_ dict: [String: String]) -> String {
        // Use a stricter character set than .urlQueryAllowed for form bodies.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")
        return dict.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    // MARK: - Keychain

    private func saveTokens(_ tokens: Tokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try keychainSet(account: keychainAccount, data: data)
    }

    private func loadTokens() throws -> Tokens? {
        guard let data = try keychainGet(account: keychainAccount) else { return nil }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }

    private func deleteTokens() throws {
        try keychainDelete(account: keychainAccount)
    }

    private func saveUsername(_ name: String) throws {
        try keychainSet(account: displayNameAccount, data: Data(name.utf8))
    }

    private func loadUsername() throws -> String? {
        guard let data = try keychainGet(account: displayNameAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteUsername() throws {
        try keychainDelete(account: displayNameAccount)
    }

    // Note: we deliberately don't use kSecUseDataProtectionKeychain. On
    // sandboxed macOS apps that flag triggers errSecMissingEntitlement
    // (-34018) unless the app has the Keychain Sharing capability — which
    // requires an access group configured in entitlements + provisioning.
    // The legacy file-backed keychain is just as secure within the sandbox
    // container and works without any extra entitlements.

    private func keychainSet(account: String, data: Data) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw SignInError.keychain(status) }
    }

    private func keychainGet(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SignInError.keychain(status) }
        return result as? Data
    }

    private func keychainDelete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw SignInError.keychain(status)
        }
    }
}

// MARK: - ASWebAuthenticationSession anchor

extension MSALClient: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Must hop to MainActor since AppKit window APIs are MainActor-isolated.
        MainActor.assumeIsolated {
            if let window = NSApp.keyWindow { return window }
            if let window = NSApp.mainWindow { return window }
            if let window = NSApp.windows.first(where: { $0.isVisible }) { return window }
            return ASPresentationAnchor()
        }
    }
}

// MARK: - Base64URL

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
