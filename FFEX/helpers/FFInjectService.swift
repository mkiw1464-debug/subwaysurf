import Foundation
import CryptoKit
import UIKit

// MARK: - Game enum

enum FFGame: String, CaseIterable {
    case freeFire    = "ff"
    case freefireMax = "ffmax"

    private static let _k: UInt8 = 0x5A
    private static func _xd(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ _k }, encoding: .utf8) ?? ""
    }

    var bundleID: String {
        switch self {
        case .freeFire:
            return Self._xd([0x39,0x35,0x37,0x74,0x3e,0x2e,0x29,0x74,
                              0x3c,0x28,0x3f,0x3f,0x3c,0x33,0x28,0x3f,0x2e,0x32])
        case .freefireMax:
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

// MARK: - Cheat file names (XOR)

private enum CheatFiles {
    private static let _k: UInt8 = 0x5A
    private static func _xd(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ _k }, encoding: .utf8) ?? ""
    }
    static var patchBytes: String {
        _xd([0x1b,0x29,0x29,0x3f,0x37,0x38,0x36,0x23,0x77,0x19,0x09,0x32,0x3b,
             0x28,0x2a,0x77,0x2a,0x3b,0x2e,0x39,0x32,0x74,0x38,0x23,0x2e,0x3f,0x29])
    }
    static var localConfig: String {
        _xd([0x36,0x35,0x39,0x3b,0x36,0x19,0x35,0x34,0x3c,0x33,
             0x3d,0x74,0x30,0x29,0x35,0x34])
    }
    static var all: [String] { [patchBytes, localConfig] }
}

// MARK: - GitHub repo (XOR)

private enum Repo {
    private static let _k: UInt8 = 0x5A
    private static func _xd(_ b: [UInt8]) -> String {
        String(bytes: b.map { $0 ^ _k }, encoding: .utf8) ?? ""
    }
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

// MARK: - Errors

enum FFInjectError: LocalizedError {
    case containerNotFound
    case fileUnavailable(String)
    case writeFailed(String)
    case sessionInvalid
    case integrityFailed

    var errorDescription: String? {
        switch self {
        case .containerNotFound:      return "Game container not found"
        case .fileUnavailable(let f): return "\(f) unavailable in repository"
        case .writeFailed(let r):     return "Write failed: \(r)"
        case .sessionInvalid:         return "Session expired"
        case .integrityFailed:        return "File integrity check failed"
        }
    }
}

// MARK: - Availability

enum FFAvailabilityService {
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

// MARK: - InjectSession (anti-leak core)

final class InjectSession {
    let game: FFGame
    let key: String
    let sessionToken: String

    private(set) var isActive: Bool = true

    // Paths of encrypted blobs on disk — NOT the plaintext files
    private var encryptedBlobPaths: [String] = []
    // Paths of deployed plaintext files in game Documents
    private var deployedPaths: [String] = []

    // Per-session AES-GCM key — ephemeral, lives in memory only
    let encKey: SymmetricKey

    init(game: FFGame, key: String) {
        self.game  = game
        self.key   = key
        self.encKey = SymmetricKey(size: .bits256)

        // Session token = SHA256(hwid:key:timestamp) — device + time bound
        let raw    = "\(DeviceID.hwid):\(key):\(Int(Date().timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        self.sessionToken = digest.map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    func registerEncryptedBlob(_ path: String) { encryptedBlobPaths.append(path) }
    func registerDeployedPath(_ path: String)   { deployedPaths.append(path) }

    func invalidate() {
        isActive = false
        wipeAll()
    }

    private func wipeAll() {
        let fm = FileManager.default
        // Wipe deployed plaintext files first (zero-fill then delete)
        for path in deployedPaths {
            securewipe(path: path, fm: fm)
        }
        // Wipe encrypted blobs
        for path in encryptedBlobPaths {
            securewipe(path: path, fm: fm)
        }
        deployedPaths.removeAll()
        encryptedBlobPaths.removeAll()
        log("InjectSession: wiped all deployed files for \(game.bundleID)")
    }

    /// Overwrite with random bytes then delete — makes recovery harder
    private func securewipe(path: String, fm: FileManager) {
        guard fm.fileExists(atPath: path) else { return }
        if let size = try? fm.attributesOfItem(atPath: path)[.size] as? Int, size > 0 {
            let junk = Data((0..<min(size, 4096)).map { _ in UInt8.random(in: 0...255) })
            try? junk.write(to: URL(fileURLWithPath: path))
        }
        try? fm.removeItem(atPath: path)
    }
}

// MARK: - FFInjectService

enum FFInjectService {

    // MARK: - Main inject flow

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

        // Download → encrypt in memory → write encrypted blob → decrypt to final dest
        // Result: plaintext NEVER touches disk unencrypted outside final location
        // Final location is immediately wiped when session ends
        for file in CheatFiles.all {
            guard let url = Repo.rawURL(file: file) else {
                throw FFInjectError.fileUnavailable(file)
            }

            // 1. Download
            var req = URLRequest(url: url, timeoutInterval: 30)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (plainData, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw FFInjectError.fileUnavailable(file)
            }

            // 2. Verify download is non-empty
            guard !plainData.isEmpty else { throw FFInjectError.fileUnavailable(file) }

            // 3. Encrypt with session key in memory
            let sealedBox = try AES.GCM.seal(plainData, using: session.encKey)
            guard let encData = sealedBox.combined else { throw FFInjectError.integrityFailed }

            // 4. Write encrypted blob to private temp location (not game folder)
            let tmpDir  = FileManager.default.temporaryDirectory
                .appendingPathComponent("ffex_\(session.sessionToken)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let blobURL = tmpDir.appendingPathComponent("\(file).enc")
            try encData.write(to: blobURL)
            session.registerEncryptedBlob(blobURL.path)

            // 5. Decrypt back into memory and write plaintext atomically to game Documents
            let sealedBox2  = try AES.GCM.SealedBox(combined: encData)
            let decryptedData = try AES.GCM.open(sealedBox2, using: session.encKey)
            let destURL     = docsURL.appendingPathComponent(file)
            try writeAtomic(data: decryptedData, to: destURL)
            session.registerDeployedPath(destURL.path)

            log("FFInject: deployed \(file)")
        }

        log("FFInject: COMPLETE game=\(game.bundleID) token=\(session.sessionToken.prefix(8))…")
        return session
    }

    // MARK: - Terminate

    static func terminateSession(_ session: InjectSession) {
        session.invalidate()
        log("FFInject: session terminated for \(session.game.bundleID)")
    }

    // MARK: - Launch game

    static func launchGame(_ game: FFGame) {
        let bundleID = game.bundleID
        DispatchQueue.main.async {
            if let workspace = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
               let instance  = workspace.perform(Selector(("defaultWorkspace")))?.takeUnretainedValue() as? NSObject {
                _ = instance.perform(Selector(("openApplicationWithBundleID:")), with: bundleID)
                log("FFInject: launched \(bundleID)")
            }
        }
    }

    // MARK: - Atomic write

    private static func writeAtomic(data: Data, to dest: URL) throws {
        let fm  = FileManager.default
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: tmp.path, contents: data) else {
            throw FFInjectError.writeFailed("createFile: \(dest.lastPathComponent)")
        }
        guard rename(tmp.path, dest.path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw FFInjectError.writeFailed("rename errno=\(errno)")
        }
    }
}
