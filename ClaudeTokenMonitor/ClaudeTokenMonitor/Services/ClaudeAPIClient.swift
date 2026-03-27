import Foundation
import Security
import CommonCrypto
import SQLite3

// MARK: - API Response Models

struct UsageResponse: Codable {
    let five_hour: WindowResponse
    let seven_day: WindowResponse
    let extra_usage: ExtraUsageResponse
}

struct WindowResponse: Codable {
    let utilization: Int  // 0-100 integer
    let resets_at: String // ISO 8601 date
}

struct ExtraUsageResponse: Codable {
    let is_enabled: Bool
    let used_credits: Int        // cents
    let monthly_limit: Int?      // cents, null if unlimited
}

struct PrepaidCreditsResponse: Codable {
    let amount: Int              // cents
    let currency: String
    let auto_reload_settings: AutoReloadSettings?
}

struct AutoReloadSettings: Codable {
    // Placeholder — fields vary by account type
}

struct OverageSpendResponse: Codable {
    let is_enabled: Bool
    let monthly_credit_limit: Int?  // cents
    let currency: String?
    let used_credits: Int           // cents
    let disabled_reason: String?
    let out_of_credits: Bool?
}

struct ClaudeAPIData {
    let usage: UsageResponse?
    let prepaidCredits: PrepaidCreditsResponse?
    let overage: OverageSpendResponse?
    let fetchedAt: Date
}

// MARK: - ClaudeAPIClient

@MainActor
final class ClaudeAPIClient: ObservableObject {
    @Published var latestData: ClaudeAPIData?

    private let baseURL = "https://claude.ai"
    private let cookieDBPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Claude/Cookies"
    }()

    // Cookie cache — invalidate after 5 minutes
    private var cachedCookies: [String: String]?
    private var cookieCacheTime: Date?
    private let cookieCacheTTL: TimeInterval = 5 * 60

    // MARK: - Public API

    func fetchAll() async {
        guard let cookies = loadCookies() else {
            print("[ClaudeAPIClient] Could not load cookies, skipping fetch")
            return
        }

        guard let orgId = cookies["lastActiveOrg"], !orgId.isEmpty else {
            print("[ClaudeAPIClient] No orgId found in cookies")
            return
        }

        async let usageFetch = fetchUsage(orgId: orgId, cookies: cookies)
        async let creditsFetch = fetchPrepaidCredits(orgId: orgId, cookies: cookies)
        async let overageFetch = fetchOverageSpend(orgId: orgId, cookies: cookies)

        let (usage, credits, overage) = await (usageFetch, creditsFetch, overageFetch)

        latestData = ClaudeAPIData(
            usage: usage,
            prepaidCredits: credits,
            overage: overage,
            fetchedAt: Date()
        )
    }

    // MARK: - Individual Endpoint Fetches

    private func fetchUsage(orgId: String, cookies: [String: String]) async -> UsageResponse? {
        let urlString = "\(baseURL)/api/organizations/\(orgId)/usage"
        return await fetchEndpoint(urlString: urlString, cookies: cookies)
    }

    private func fetchPrepaidCredits(orgId: String, cookies: [String: String]) async -> PrepaidCreditsResponse? {
        let urlString = "\(baseURL)/api/organizations/\(orgId)/prepaid/credits"
        return await fetchEndpoint(urlString: urlString, cookies: cookies)
    }

    private func fetchOverageSpend(orgId: String, cookies: [String: String]) async -> OverageSpendResponse? {
        let urlString = "\(baseURL)/api/organizations/\(orgId)/overage_spend_limit"
        return await fetchEndpoint(urlString: urlString, cookies: cookies)
    }

    private func fetchEndpoint<T: Decodable>(urlString: String, cookies: [String: String]) async -> T? {
        guard let url = URL(string: urlString) else {
            print("[ClaudeAPIClient] Invalid URL: \(urlString)")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36", forHTTPHeaderField: "User-Agent")

        // Build cookie header
        var cookieParts: [String] = []
        if let sessionKey = cookies["sessionKey"] {
            cookieParts.append("sessionKey=\(sessionKey)")
        }
        if let cfClearance = cookies["cf_clearance"] {
            cookieParts.append("cf_clearance=\(cfClearance)")
        }
        if !cookieParts.isEmpty {
            request.setValue(cookieParts.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    print("[ClaudeAPIClient] HTTP \(httpResponse.statusCode) for \(urlString)")
                    return nil
                }
            }

            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            print("[ClaudeAPIClient] Fetch error for \(urlString): \(error)")
            return nil
        }
    }

    // MARK: - Cookie Loading

    private func loadCookies() -> [String: String]? {
        // Return cached cookies if still fresh
        if let cached = cachedCookies,
           let cacheTime = cookieCacheTime,
           Date().timeIntervalSince(cacheTime) < cookieCacheTTL {
            return cached
        }

        guard let aesKey = deriveAESKeyFromKeychain() else {
            print("[ClaudeAPIClient] Could not derive AES key from Keychain")
            return nil
        }

        guard let cookies = readCookiesFromSQLite(aesKey: aesKey) else {
            print("[ClaudeAPIClient] Could not read cookies from SQLite")
            return nil
        }

        cachedCookies = cookies
        cookieCacheTime = Date()
        return cookies
    }

    // MARK: - Keychain + PBKDF2

    private func deriveAESKeyFromKeychain() -> [UInt8]? {
        // Query Keychain for "Claude Safe Storage" password
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Safe Storage",
            kSecAttrAccount: "Claude",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            print("[ClaudeAPIClient] Keychain query failed: \(status)")
            return nil
        }

        guard let passwordData = result as? Data,
              let passwordString = String(data: passwordData, encoding: .utf8) else {
            print("[ClaudeAPIClient] Could not decode Keychain password")
            return nil
        }

        // PBKDF2-SHA1: password=keychainPassword, salt="saltysalt", iterations=1003, keyLen=16
        let salt = Array("saltysalt".utf8)
        let password = Array(passwordString.utf8)
        var derivedKey = [UInt8](repeating: 0, count: 16)

        let pbkdfResult = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password,
            password.count,
            salt,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003,
            &derivedKey,
            derivedKey.count
        )

        guard pbkdfResult == kCCSuccess else {
            print("[ClaudeAPIClient] PBKDF2 derivation failed: \(pbkdfResult)")
            return nil
        }

        return derivedKey
    }

    // MARK: - Cookie Decryption (AES-128-CBC)

    private func decryptCookieValue(_ encryptedData: Data, aesKey: [UInt8]) -> String? {
        // encrypted_value has "v10" prefix (3 bytes to skip)
        guard encryptedData.count > 3 else { return nil }

        let ciphertext = encryptedData.dropFirst(3)
        guard ciphertext.count > 0 else { return nil }

        // IV = 16 bytes of 0x20 (space character)
        let iv = [UInt8](repeating: 0x20, count: 16)
        let ciphertextBytes = Array(ciphertext)

        var outputBuffer = [UInt8](repeating: 0, count: ciphertextBytes.count + kCCBlockSizeAES128)
        var outputLength = 0

        let cryptStatus = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            aesKey,
            kCCKeySizeAES128,
            iv,
            ciphertextBytes,
            ciphertextBytes.count,
            &outputBuffer,
            outputBuffer.count,
            &outputLength
        )

        guard cryptStatus == kCCSuccess else {
            print("[ClaudeAPIClient] AES decryption failed: \(cryptStatus)")
            return nil
        }

        let decryptedBytes = Array(outputBuffer[0..<outputLength])
        return String(bytes: decryptedBytes, encoding: .utf8)
    }

    // MARK: - SQLite Cookie Reading

    private func readCookiesFromSQLite(aesKey: [UInt8]) -> [String: String]? {
        guard FileManager.default.fileExists(atPath: cookieDBPath) else {
            print("[ClaudeAPIClient] Cookie DB not found at: \(cookieDBPath)")
            return nil
        }

        var db: OpaquePointer?
        // Use read-only immutable mode to avoid locking issues
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(cookieDBPath, &db, flags, nil) == SQLITE_OK else {
            print("[ClaudeAPIClient] Could not open Cookie DB: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let query = "SELECT name, encrypted_value, value FROM cookies WHERE host_key LIKE '%claude.ai%'"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[ClaudeAPIClient] Could not prepare SQL statement: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var cookies: [String: String] = [:]
        let targetCookies: Set<String> = ["sessionKey", "cf_clearance", "lastActiveOrg"]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(statement, 0) else { continue }
            let name = String(cString: namePtr)

            guard targetCookies.contains(name) else { continue }

            // Check the plain text value column first (some cookies aren't encrypted)
            var plainValue: String? = nil
            if let valuePtr = sqlite3_column_text(statement, 2) {
                let valueStr = String(cString: valuePtr)
                if !valueStr.isEmpty {
                    plainValue = valueStr
                }
            }

            if let plain = plainValue {
                cookies[name] = plain
                continue
            }

            // Try decrypting encrypted_value
            let encryptedLength = sqlite3_column_bytes(statement, 1)
            if encryptedLength > 0,
               let encryptedPtr = sqlite3_column_blob(statement, 1) {
                let encryptedData = Data(bytes: encryptedPtr, count: Int(encryptedLength))
                if let decrypted = decryptCookieValue(encryptedData, aesKey: aesKey) {
                    cookies[name] = decrypted
                }
            }
        }

        if cookies.isEmpty {
            print("[ClaudeAPIClient] No Claude.ai cookies found in DB")
            return nil
        }

        return cookies
    }
}
