import Foundation
import UIKit

// MARK: - Models

struct LicenseResponse: Codable {
    let valid: Bool
    let status: String?
    let expiresAt: String?
    let hwid: String?

    enum CodingKeys: String, CodingKey {
        case valid, status
        case expiresAt = "expires_at"
        case hwid
    }
}

struct LicenseInfo {
    let key: String
    let expiresAt: String
    let expiryDate: Date?
    let deviceName: String
    let hwid: String
    let iOSVersion: String
    let iPhoneModel: String
}

// MARK: - Revocation reason (for UI feedback)

enum RevocationReason {
    case banned, deleted, expired, deviceMismatch, unknown

    var displayMessage: String {
        switch self {
        case .banned:         return "Key has been banned"
        case .deleted:        return "Key no longer exists"
        case .expired:        return "Key has expired"
        case .deviceMismatch: return "Key is bound to another device"
        case .unknown:        return "Session invalidated"
        }
    }
}

// MARK: - Device ID (HWID)

enum DeviceID {
    private static let _hk: [UInt8] = [0x3c,0x3c,0x3f,0x22,0x2e,0x05,0x32,0x2d,0x33,0x3e]
    private static let _hp: [UInt8] = [0x33,0x35,0x29,0x77]

    static var hwid: String {
        let key = _xd(_hk)
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let id  = _xd(_hp) + raw.prefix(16).lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
    static var deviceName: String  { AppInfo.deviceName }
    static var iPhoneModel: String { AppInfo.iPhoneModel }
    static var iOSVersion: String  { AppInfo.iOSVersion }
}

// MARK: - LicenseService

enum LicenseService {

    // XOR-encoded Vercel API endpoint
    private static let _au: [UInt8] = [
        0x32,0x2e,0x2e,0x2a,0x29,0x60,0x75,0x75,
        0x3c,0x3c,0x3f,0x22,0x22,0x22,0x22,0x74,
        0x2c,0x3f,0x28,0x39,0x3f,0x36,0x74,0x3b,
        0x2a,0x2a,0x75,0x3b,0x2a,0x33,0x75,0x36,
        0x33,0x39,0x3f,0x34,0x29,0x3f,0x29,0x75,
        0x2c,0x3b,0x36,0x33,0x3e,0x3b,0x2e,0x3f
    ]

    static var apiURL: URL { URL(string: _xd(_au))! }
    static var storageKey: String { S.licenseStorageKey }
    static var expiryKey: String  { S.licenseExpiryKey }

    // MARK: - Validate (login + revalidation)

    static func validate(key: String) async throws -> LicenseInfo {
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body: [String: Any] = ["key": key, "hwid": DeviceID.hwid]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LicenseError.networkError }

        // 401 / 403 / 404 = key banned, deleted, or invalid — force logout
        switch http.statusCode {
        case 401: throw LicenseError.revoked(.banned)
        case 403: throw LicenseError.revoked(.banned)
        case 404: throw LicenseError.revoked(.deleted)
        case 200..<300: break
        default: throw LicenseError.serverError(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(LicenseResponse.self, from: data)

        // Check status field from server
        if let status = decoded.status?.lowercased() {
            if status.contains("ban")     { throw LicenseError.revoked(.banned) }
            if status.contains("delet")   { throw LicenseError.revoked(.deleted) }
            if status.contains("expir")   { throw LicenseError.revoked(.expired) }
            if status.contains("invalid") { throw LicenseError.revoked(.unknown) }
        }

        guard decoded.valid else { throw LicenseError.revoked(.unknown) }

        if let serverHwid = decoded.hwid, !serverHwid.isEmpty, serverHwid != DeviceID.hwid {
            throw LicenseError.revoked(.deviceMismatch)
        }

        let expiresRaw = decoded.expiresAt ?? ""
        let expiryDate = parseISODate(expiresRaw)
        if let exp = expiryDate, exp < Date() { throw LicenseError.revoked(.expired) }
        let formatted = expiryDate.map { formatDate($0) } ?? expiresRaw

        let info = LicenseInfo(
            key: key, expiresAt: formatted, expiryDate: expiryDate,
            deviceName: DeviceID.deviceName, hwid: DeviceID.hwid,
            iOSVersion: DeviceID.iOSVersion, iPhoneModel: DeviceID.iPhoneModel
        )
        store(key: key, expiryRaw: expiresRaw)
        return info
    }

    // MARK: - Restore session (async, server-confirmed)

    static func restoreSession() async -> LicenseInfo? {
        guard let key = storedKey() else { return nil }
        if let expRaw = UserDefaults.standard.string(forKey: expiryKey),
           let expDate = parseISODate(expRaw), expDate < Date() {
            logout(); return nil
        }
        do {
            return try await validate(key: key)
        } catch {
            logout(); return nil
        }
    }

    // MARK: - Restore session (local fast bootstrap)

    static func restoreSessionLocal() -> LicenseInfo? {
        guard let key    = storedKey(),
              let expRaw = UserDefaults.standard.string(forKey: expiryKey) else { return nil }
        let expiryDate = parseISODate(expRaw)
        if let exp = expiryDate, exp < Date() { logout(); return nil }
        return LicenseInfo(
            key: key,
            expiresAt: expiryDate.map { formatDate($0) } ?? expRaw,
            expiryDate: expiryDate,
            deviceName: DeviceID.deviceName, hwid: DeviceID.hwid,
            iOSVersion: DeviceID.iOSVersion, iPhoneModel: DeviceID.iPhoneModel
        )
    }

    // MARK: - Background revalidation — returns nil on network error (don't logout), revocation on auth fail

    enum RevalResult {
        case ok
        case revoked(RevocationReason)
        case networkError  // transient, don't logout
    }

    static func revalidateBackground(key: String) async -> RevalResult {
        do {
            _ = try await validate(key: key)
            return .ok
        } catch LicenseError.revoked(let reason) {
            return .revoked(reason)
        } catch LicenseError.networkError {
            return .networkError  // no internet — keep session alive
        } catch {
            return .revoked(.unknown)
        }
    }

    // MARK: - Storage

    static func storedKey() -> String? { UserDefaults.standard.string(forKey: storageKey) }

    private static func store(key: String, expiryRaw: String) {
        UserDefaults.standard.set(key,       forKey: storageKey)
        UserDefaults.standard.set(expiryRaw, forKey: expiryKey)
    }

    static func logout() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: expiryKey)
    }

    // MARK: - Helpers

    private static func parseISODate(_ raw: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: raw) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: raw)
    }

    private static func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    static func maskedKey(_ key: String) -> String {
        let parts = key.components(separatedBy: "-")
        guard parts.count >= 2 else {
            let n = key.count
            guard n > 4 else { return String(repeating: "•", count: n) }
            return key.prefix(4) + String(repeating: "•", count: n - 4)
        }
        func maskSeg(_ s: String, showStart: Int = 0, showEnd: Int = 0) -> String {
            let n = s.count
            guard n > showStart + showEnd else { return s }
            let st  = showStart > 0 ? String(s.prefix(showStart)) : ""
            let en  = showEnd   > 0 ? String(s.suffix(showEnd))   : ""
            return st + String(repeating: "•", count: n - showStart - showEnd) + en
        }
        return parts.enumerated().map { i, part in
            if i == 0 { return part }
            if i == 1 { return maskSeg(part, showStart: 2) }
            if i == parts.count - 1 { return maskSeg(part, showEnd: 2) }
            return maskSeg(part)
        }.joined(separator: "-")
    }

    static func countdownString(from expiryDate: Date) -> String {
        let now = Date()
        guard expiryDate > now else { return "Expired" }
        let diff    = expiryDate.timeIntervalSince(now)
        let days    = Int(diff) / 86400
        let hours   = (Int(diff) % 86400) / 3600
        let minutes = (Int(diff) % 3600) / 60
        let secs    = Int(diff) % 60
        if days > 0  { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m \(secs)s" }
        return "\(minutes)m \(secs)s"
    }
}

// MARK: - Errors

enum LicenseError: LocalizedError {
    case revoked(RevocationReason)
    case networkError
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .revoked(let r):       return r.displayMessage
        case .networkError:         return "Network error — check your connection"
        case .serverError(let c):   return "Server error (\(c))"
        }
    }
}
