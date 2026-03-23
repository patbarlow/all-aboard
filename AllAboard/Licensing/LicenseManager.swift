import Foundation
import Security

class LicenseManager {
    static let shared = LicenseManager()

    private let keychainService = "com.patbarlow.AllAboard"
    private let licenseKeyAccount = "license-key"
    private let instanceIdAccount = "instance-id"

    var isActivated: Bool {
        storedLicenseKey != nil
    }

    var storedLicenseKey: String? {
        keychainGet(account: licenseKeyAccount)
    }

    var storedInstanceId: String? {
        keychainGet(account: instanceIdAccount)
    }

    // MARK: - Activate (first time)

    func activate(key: String) async throws {
        let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "license_key": key,
            "instance_name": Host.current().localizedName ?? "Mac"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError
        }

        let result = try JSONDecoder().decode(LicenseActivationResponse.self, from: data)

        if http.statusCode == 200, result.activated == true {
            keychainSet(key, account: licenseKeyAccount)
            if let instanceId = result.instance?.id {
                keychainSet(instanceId, account: instanceIdAccount)
            }
        } else {
            throw LicenseError.invalid(result.error ?? "Invalid license key. Please check and try again.")
        }
    }

    // MARK: - Validate (silent check on launch)

    func validate() async -> Bool {
        guard let key = storedLicenseKey else { return false }

        let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var body: [String: String] = ["license_key": key]
        if let instanceId = storedInstanceId { body["instance_id"] = instanceId }
        request.httpBody = try? JSONEncoder().encode(body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let result = try? JSONDecoder().decode(LicenseValidationResponse.self, from: data)
        else {
            // On network failure, trust the stored key
            return true
        }

        if result.valid == false {
            // Key has been revoked — clear it
            deactivate()
            return false
        }

        return true
    }

    // MARK: - Deactivate

    func deactivate() {
        keychainDelete(account: licenseKeyAccount)
        keychainDelete(account: instanceIdAccount)
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
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func keychainDelete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum LicenseError: LocalizedError {
    case networkError
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .networkError: return "Network error. Please check your connection and try again."
        case .invalid(let msg): return msg
        }
    }
}

// MARK: - Response models

private struct LicenseActivationResponse: Decodable {
    let activated: Bool?
    let error: String?
    let instance: LicenseInstance?
}

private struct LicenseValidationResponse: Decodable {
    let valid: Bool?
}

private struct LicenseInstance: Decodable {
    let id: String
}
