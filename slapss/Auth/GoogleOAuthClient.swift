import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

@MainActor
final class GoogleOAuthClient: NSObject {
    enum SignInError: LocalizedError {
        case notConfigured
        case userCancelled
        case invalidCallback
        case tokenExchange(String)
        case noRefreshToken
        case refreshTokenRevoked
        case keychain(OSStatus)
        case network(Error)
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Google sign-in is not configured. Set your Google client ID in GoogleOAuthConfig.swift."
            case .userCancelled:
                return "Sign-in cancelled."
            case .invalidCallback:
                return "Couldn't read the response from Google."
            case .tokenExchange(let message):
                return "Token exchange failed: \(message)"
            case .noRefreshToken:
                return "Sign-in expired. Please sign in again."
            case .refreshTokenRevoked:
                return "Google access expired or was revoked. Please sign in again."
            case .keychain(let status):
                return "Keychain error \(status)."
            case .network(let error):
                return "Network error: \(error.localizedDescription)"
            case .unknown(let message):
                return message
            }
        }
    }

    private struct Tokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
    }

    struct Account: Equatable {
        let email: String?
    }

    private(set) var account: Account?

    private var tokens: Tokens?
    private var session: ASWebAuthenticationSession?

    private let keychainService = "com.cancetin.slapss.google"
    private let keychainAccount = "tokens"
    private let emailAccount = "email"

    override init() {
        super.init()
        self.tokens = (try? loadTokens())
        if tokens != nil {
            self.account = Account(email: try? loadEmail())
        }
    }

    var isConfigured: Bool { !GoogleOAuthConfig.isPlaceholder }
    var isSignedIn: Bool { tokens != nil }

    func signIn() async throws {
        guard isConfigured else { throw SignInError.notConfigured }

        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.computeCodeChallenge(verifier: codeVerifier)

        let authURL = buildAuthorizeURL(codeChallenge: codeChallenge)
        let callbackURL = try await presentAuthSession(url: authURL)

        guard let code = extractAuthorizationCode(from: callbackURL) else {
            if let oauthError = extractOAuthError(from: callbackURL) {
                throw SignInError.tokenExchange(oauthError)
            }
            throw SignInError.invalidCallback
        }

        let result = try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
        try saveTokens(result.tokens)
        self.tokens = result.tokens

        var resolvedEmail = Self.extractEmail(fromIDToken: result.idToken)
        if resolvedEmail == nil {
            resolvedEmail = try? await fetchUserInfoEmail(accessToken: result.tokens.accessToken)
        }

        if let email = resolvedEmail {
            self.account = Account(email: email)
            try? saveEmail(email)
        } else {
            self.account = Account(email: nil)
            try? deleteEmail()
        }
    }

    func signOut() async {
        let tokenToRevoke = tokens?.refreshToken ?? tokens?.accessToken
        try? deleteTokens()
        try? deleteEmail()
        tokens = nil
        account = nil

        if let tokenToRevoke, let url = URL(string: "https://oauth2.googleapis.com/revoke") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 5
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = Self.formEncode(["token": tokenToRevoke]).data(using: .utf8)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    func acquireTokenSilently(forceRefresh: Bool = false) async throws -> String {
        guard let cached = tokens else { throw SignInError.noRefreshToken }

        if !forceRefresh, cached.expiresAt > Date().addingTimeInterval(60) {
            return cached.accessToken
        }

        guard let refreshToken = cached.refreshToken else { throw SignInError.noRefreshToken }
        let refreshed = try await refreshTokens(refreshToken: refreshToken)
        try saveTokens(refreshed)
        self.tokens = refreshed
        return refreshed.accessToken
    }

    static func classify(_ error: Error) -> SignInError {
        if let typed = error as? SignInError { return typed }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network(error)
        }
        return .unknown(nsError.localizedDescription)
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func computeCodeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private func buildAuthorizeURL(codeChallenge: String) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent"),
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

    private func presentAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleOAuthConfig.reversedClientID
            ) { callbackURL, error in
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

    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String
    ) async throws -> (tokens: Tokens, idToken: String?) {
        try await postTokenRequest(
            body: [
                "client_id": GoogleOAuthConfig.clientID,
                "code": code,
                "code_verifier": codeVerifier,
                "redirect_uri": GoogleOAuthConfig.redirectURI,
                "grant_type": "authorization_code",
            ],
            existingRefreshToken: nil,
            isRefresh: false
        )
    }

    private func refreshTokens(refreshToken: String) async throws -> Tokens {
        try await postTokenRequest(
            body: [
                "client_id": GoogleOAuthConfig.clientID,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token",
            ],
            existingRefreshToken: refreshToken,
            isRefresh: true
        ).tokens
    }

    private func postTokenRequest(
        body: [String: String],
        existingRefreshToken: String?,
        isRefresh: Bool
    ) async throws -> (tokens: Tokens, idToken: String?) {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw SignInError.unknown("Bad token URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SignInError.unknown("Bad token response")
        }
        if http.statusCode != 200 {
            struct OAuthErrorResponse: Decodable {
                let error: String?
                let error_description: String?
            }
            let oauthError = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
            let rawBody = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            if isRefresh,
               (http.statusCode == 400 || http.statusCode == 401),
               (oauthError?.error == "invalid_grant" || rawBody.contains("invalid_grant")) {
                throw SignInError.refreshTokenRevoked
            }
            if let err = oauthError?.error {
                let desc = oauthError?.error_description ?? ""
                throw SignInError.tokenExchange(desc.isEmpty ? err : "\(err): \(desc)")
            }
            throw SignInError.tokenExchange(rawBody)
        }

        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int
            let id_token: String?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        // Google omits refresh_token on refresh responses; keep the cached token.
        let tokens = Tokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? existingRefreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
        return (tokens, decoded.id_token)
    }

    private static func extractEmail(fromIDToken idToken: String?) -> String? {
        guard let idToken else { return nil }
        let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              let payloadData = Data(base64URLEncoded: String(segments[1])) else {
            return nil
        }
        struct Claims: Decodable {
            let email: String?
        }
        guard let claims = try? JSONDecoder().decode(Claims.self, from: payloadData),
              let email = claims.email, !email.isEmpty else {
            return nil
        }
        return email
    }

    private func fetchUserInfoEmail(accessToken: String) async throws -> String? {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        struct UserInfo: Decodable {
            let email: String?
        }
        let info = try JSONDecoder().decode(UserInfo.self, from: data)
        guard let email = info.email, !email.isEmpty else { return nil }
        return email
    }

    private static func formEncode(_ dict: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?")
        return dict.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

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

    private func saveEmail(_ email: String) throws {
        try keychainSet(account: emailAccount, data: Data(email.utf8))
    }

    private func loadEmail() throws -> String? {
        guard let data = try keychainGet(account: emailAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteEmail() throws {
        try keychainDelete(account: emailAccount)
    }

    // Deliberately omit kSecUseDataProtectionKeychain: on sandboxed macOS apps
    // it triggers errSecMissingEntitlement (-34018) without Keychain Sharing.
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

extension GoogleOAuthClient: ASWebAuthenticationPresentationContextProviding {
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

private extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
