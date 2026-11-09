//
//  SupabaseAuth.swift
//  plant-alert
//

import Foundation
import Security

/// A signed-in Supabase user's tokens.
struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
}

/// Anonymous Supabase Auth, so every phone is a real user the row policies can
/// check.
///
/// Anonymous sign-in needs no email or password: the phone gets its own user
/// on first sync and keeps it in the Keychain. Membership of a household, which
/// is what the policies actually check, comes from `join_household` after.
enum SupabaseAuth {
    /// Refresh this long before expiry so a token can't lapse mid-sync.
    private static let refreshMargin: TimeInterval = 60
    private static let keychainService = "plant-alert.supabase-session"

    /// A session with a usable access token, signing in or refreshing as needed.
    ///
    /// Calls must not overlap: refresh tokens are single-use, so two concurrent
    /// refreshes would sign one of them out. `SyncEngine` runs one sync at a
    /// time, which is what guarantees that.
    static func session(
        for credentials: SupabaseCredentials,
        urlSession: URLSession = .shared
    ) async throws -> SupabaseSession {
        // Keyed by project, so pointing the app at another project signs in
        // there rather than reusing a token it would reject.
        let account = credentials.baseURL.absoluteString

        if let stored = load(account: account) {
            if stored.expiresAt.timeIntervalSinceNow > refreshMargin { return stored }
            do {
                let refreshed = try await requestSession(
                    path: "token",
                    query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                    body: ["refresh_token": stored.refreshToken],
                    credentials: credentials,
                    urlSession: urlSession
                )
                save(refreshed, account: account)
                return refreshed
            } catch SupabaseError.http(let status, _) where (400..<500).contains(status) {
                // The refresh token is dead (revoked, or the user was deleted).
                // Start over as a new user; the sync rejoins the household with
                // the stored code, so nothing is lost.
            }
        }

        let fresh = try await requestSession(
            path: "signup",
            query: [],
            body: ["data": [String: String]()],
            credentials: credentials,
            urlSession: urlSession
        )
        save(fresh, account: account)
        return fresh
    }

    // MARK: - Requests

    private struct TokenResponse: Decodable {
        struct User: Decodable { let id: String }
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User
    }

    private static func requestSession(
        path: String,
        query: [URLQueryItem],
        body: [String: Any],
        credentials: SupabaseCredentials,
        urlSession: URLSession
    ) async throws -> SupabaseSession {
        var components = URLComponents(
            url: credentials.baseURL.appending(path: "auth/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw SupabaseError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(credentials.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await SupabaseClient.send(request, session: urlSession)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SupabaseSession(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: Date().addingTimeInterval(token.expires_in),
            userID: token.user.id
        )
    }

    // MARK: - Keychain

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
    }

    private static func load(account: String) -> SupabaseSession? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    private static func save(_ session: SupabaseSession, account: String) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query = query(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
