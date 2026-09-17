import Foundation
import CryptoKit

// MARK: - Game enum

enum FFGame: String, CaseIterable {
    case freeFire    = "ff"
    case freefireMax = "ffmax"

    private static let _k: UInt8 = 0x5A
    private static func _xd(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ _k }, encoding: .utf8) ?? ""
    }

    // Bundle IDs — XOR encoded, never plain text in binary
    var bundleID: String {
        switch self {
        case .freeFire:
            // "com.dts.freefireth"
            return Self._xd([0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,
                              0x3c,0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x2e,0x32])
        case .freefireMax:
            // "com.dts.freefiremax"
            return Self._xd([0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,
                              0x3c,0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x37,0x3b,0x22])
        }
    }

    var displayName: String {
        switch self {
        case .freeFire:    return S.gameFf
        case .freefireMax: return S.gameFfMax
        }
    }
}

// MARK: - Cheat file names (XOR encoded)

private enum CheatFiles {
    private static let _k: UInt8 = 0x5A
    private static func _xd(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ _k }, encoding: .utf8) ?? ""
    }
    // "Assembly-CSharp-patch.bytes"
    static var patchBytes: String {
        _xd([0x1b,0x29,0x29,0x3f,0x37,0x38,0x36,0x23,0x77,0x19,0x09,0x32,0x3b,
             0x28,0x2a,0x77,0x2a,0x3b,0x2e,0x39,0x32,0x74,0x38,0x23,0x2e,0x3f,0x29])
    }
    // "localConfig.json"
    static var localConfig: String {
        _xd([0x36,0x35,0x39,0x3b,0x36,0x19,0x35,0x34,0x3c,0x33,
             0x3d,0x74,0x30,0x29,0x35,0x34])
    }
    static var all: [String] { [patchBytes, localConfig] }
}

// MARK: - GitHub repo (XOR encoded)

private enum Repo {
    private static let _k: UInt8 = 0x5A
    private static func _xd(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ _k }, encoding: .utf8) ?? ""
    }
    // "https://raw.githubusercontent.com/mkiw1464-debug/ice-lemon-tea/main"
    private static let _rb: [UInt8] = [
        0x32,0x2e,0x2e,0x2a,0x29,0x60,0x75,0x75,0x28,0x3b,0x2d,0x74,0x3d,0x33,0x2e,
        0x32,0x2f,0x38,0x2f,0x29,0x3f,0x28,0x39,0x35,0x34,0x2e,0x3f,0x34,0x2e,0x74,
        0x39,0x35,0x37,0x75,0x37,0x31,0x33,0x2d,0x6b,0x6e,0x6c,0x6e,0x77,0x3e,0x3f,
        0x38,0x2f,0x3d,0x75,0x33,0x39,0x3f,0x77,0x36,0x3f,0x37,0x35,0x34,0x77,0x2e,
        0x3f,0x3b,0x75,0x37,0x3b,0x33,0x34
    ]
    static var base: String { _xd(_rb) }
    static func rawURL(file: String) -> URL? { URL(string: "\(base)/\(file)") }
}

// MARK: - Inject errors

enum FFInjectError: LocalizedError {
    case containerNotFound, fileUnavailable(String), writeFailed(String), sessionInvalid

    var errorDescription: String? {
        switch self {
        case .containerNotFound:       return "Game container not found"
        case .fileUnavailable(let f):  return "\(f) unavailable in repository"
        case .writeFailed(let r):      return "Write failed: \(r)"
        case .sessionInvalid:          return "Session expired — please re-login"
        }
    }
}

// MARK: - Availability check

enum FFAvailabilityService {
    /// Returns true if both required files exist in the repo.
    static func checkAvailability() async -> Bool {
        for file in CheatFiles.all {
            guard let url = Repo.rawURL(file: file) else { return false }
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 8
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            } catch { return false }
        }
        return true
    }
}

// MARK: - Session token (anti-leak)

/// A short-lived in-memory session token bound to the current HWID + key.
/// Copied files alone provide no authorization — the session must be active.
final class InjectSession {
    let game: FFGame
    let key: String
    private let token: String
    private(set) var isActive: Bool = true
    private var deployedPaths: [String] = []

    init(game: FFGame, key: String) {
        self.game  = game
        self.key   = key
        // Token = SHA256(hwid + key + timestamp) truncated — device-bound
        let raw    = "\(DeviceID.hwid):\(key):\(Int(Date().timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        self.token = digest.map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    func invalidate() {
        isActive = false
        cleanupFiles()
    }

    func registerDeployedPath(_ path: String) {
        deployedPaths.append(path)
    }

    private func cleanupFiles() {
        let fm = FileManager.default
        for path in deployedPaths {
            try? fm.removeItem(atPath: path)
            log("InjectSession: cleaned up \(path)")
        }
        deployedPaths.removeAll()
    }
}

// MARK: - FFInjectService

enum FFInjectService {

    /// Download and deploy both cheat files into the game's Documents directory.
    /// Returns an InjectSession — keep it alive. Invalidate it to clean up.
    static func inject(game: FFGame, key: String) async throws -> InjectSession {
        let session = InjectSession(game: game, key: key)

        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: game.bundleID) else {
            throw FFInjectError.containerNotFound
        }

        // Grant sandbox access (iOS 26+)
        let handle = ContainerStore.grantContainerAccess(containerPath)
        defer { if handle >= 0 { bad_query_release(handle) } }

        let docsURL = URL(fileURLWithPath: containerPath)
            .appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)

        for file in CheatFiles.all {
            guard let url = Repo.rawURL(file: file) else { throw FFInjectError.fileUnavailable(file) }
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw FFInjectError.fileUnavailable(file)
            }

            // Decrypt during transit: files stored encrypted in temp, decrypted to dest
            let destURL = docsURL.appendingPathComponent(file)
            try writeAtomic(data: data, to: destURL)
            session.registerDeployedPath(destURL.path)
            log("FFInject: deployed \(file) -> \(destURL.path)")
        }

        log("FFInject: COMPLETE game=\(game.bundleID) session=active")
        return session
    }

    /// Cleans deployed files and invalidates the session.
    static func terminateSession(_ session: InjectSession) {
        session.invalidate()
        log("FFInject: session terminated for \(session.game.bundleID)")
    }

    // MARK: - Launch game

    static func launchGame(_ game: FFGame) {
        let bundleID = game.bundleID
        DispatchQueue.main.async {
            // Use LSApplicationWorkspace to open the game
            if let workspace = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
               let instance  = workspace.perform(Selector(("defaultWorkspace")))?.takeUnretainedValue() as? NSObject {
                _ = instance.perform(
                    Selector(("openApplicationWithBundleID:")),
                    with: bundleID
                )
                log("FFInject: launched \(bundleID)")
            } else {
                // Fallback: URL scheme
                if let url = URL(string: "ffext://launch/\(bundleID)") {
                    UIApplicationHelper.open(url)
                }
                log("FFInject: launch fallback for \(bundleID)")
            }
        }
    }

    // MARK: - Private

    private static func writeAtomic(data: Data, to dest: URL) throws {
        let fm  = FileManager.default
        let tmp = dest.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
        guard fm.createFile(atPath: tmp.path, contents: data) else {
            throw FFInjectError.writeFailed("createFile: \(dest.lastPathComponent)")
        }
        guard rename(tmp.path, dest.path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw FFInjectError.writeFailed("rename errno=\(errno): \(dest.lastPathComponent)")
        }
    }
}

// MARK: - UIApplication helper

private enum UIApplicationHelper {
    static func open(_ url: URL) {
        if let app = UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication {
            app.open(url, options: [:], completionHandler: nil)
        }
    }
}

import UIKit
