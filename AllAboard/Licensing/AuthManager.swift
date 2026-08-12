import Foundation
import Security

struct AuthUser: Codable {
    let id: String
    let email: String
    let plan: String
}

class AuthManager {
    static let shared = AuthManager()

    private let keychainService = "com.allaboard.app"
    private let sessionTokenAccount = "session-token"
    private let cachedUserAccount = "cached-user"

    var isSignedIn: Bool { sessionToken != nil }

    var sessionToken: String? {
        keychainGet(account: sessionTokenAccount)
    }

    var cachedUser: AuthUser? {
        guard let data = keychainGet(account: cachedUserAccount)?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    private static let baseURL = "https://trainboard-api.pat-barlow.workers.dev"

    // MARK: - Request OTP

    func requestCode(email: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/auth/email/start")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }

        if http.statusCode == 429 {
            if let body = try? JSONDecoder().decode([String: Int].self, from: data),
               let retryAfter = body["retry_after"] {
                throw AuthError.rateLimited(retryAfter)
            }
            throw AuthError.rateLimited(30)
        }
        if http.statusCode != 200 {
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Unknown error"
            throw AuthError.server(detail)
        }
    }

    // MARK: - Verify OTP → session

    struct VerifyResult {
        let session: String
        let user: AuthUser
    }

    func verify(email: String, code: String) async throws -> VerifyResult {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/auth/email/verify")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "code": code])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }

        if http.statusCode != 200 {
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Invalid code"
            throw AuthError.server(authErrorMessage(for: detail))
        }

        struct VerifyResponse: Decodable { let session: String; let user: AuthUser }
        let body = try JSONDecoder().decode(VerifyResponse.self, from: data)
        persistSession(token: body.session, user: body.user)
        return VerifyResult(session: body.session, user: body.user)
    }

    // MARK: - Refresh from server

    func refresh() async -> AuthUser? {
        guard let token = sessionToken else { return nil }
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return cachedUser  // network failure → trust cache
        }

        if http.statusCode == 401 {
            signOut()
            return nil
        }

        guard let user = try? JSONDecoder().decode(AuthUser.self, from: data) else { return cachedUser }
        cacheUser(user)
        return user
    }

    // MARK: - Sign out

    func signOut() {
        keychainDelete(account: sessionTokenAccount)
        keychainDelete(account: cachedUserAccount)
    }

    // MARK: - Persistence

    private func persistSession(token: String, user: AuthUser) {
        keychainSet(token, account: sessionTokenAccount)
        cacheUser(user)
    }

    private func cacheUser(_ user: AuthUser) {
        if let data = try? JSONEncoder().encode(user), let str = String(data: data, encoding: .utf8) {
            keychainSet(str, account: cachedUserAccount)
        }
    }

    private func authErrorMessage(for code: String) -> String {
        switch code {
        case "invalid_code": return "Incorrect code. Please check your email and try again."
        case "code_expired": return "That code has expired. Please request a new one."
        case "too_many_attempts": return "Too many attempts. Please request a new code."
        case "no_code": return "No code found for this email. Please request a new one."
        default: return "Something went wrong. Please try again."
        }
    }

    // MARK: - Keychain

    private func keychainGet(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainSet(_ value: String, account: String) {
        let data = value.data(using: .utf8)!
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: account]
        if SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData] = data
            newItem[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func keychainDelete(account: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case networkError
    case notSignedIn
    case rateLimited(Int)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .networkError: return "Network error. Please check your connection and try again."
        case .notSignedIn: return "You are not signed in."
        case .rateLimited(let s): return "Please wait \(s) seconds before requesting another code."
        case .server(let msg): return msg
        }
    }
}
