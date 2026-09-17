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

// MARK: - Repo (XOR)

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
        case .fileUnavailable(let f): return "\(f) unavailable"
        case .writeFailed(let r):     return "Write failed: \(r)"
        case .sessionInvalid:         return "Session expired"
        case .integrityFailed:        return "Integrity check failed"
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

// MARK: - InjectSession

final class InjectSession {
    let game: FFGame
    let key: String
    let sessionToken: String

    private(set) var isActive: Bool = true

    private var encryptedBlobPaths: [String] = []
    private var deployedPaths: [String] = []

    let encKey: SymmetricKey

    // Monitor task — watches FF running state
    private var monitorTask: Task<Void, Never>?

    // Called when FF exits — external handler set by MainMenuView
    var onGameExited: (() -> Void)?

    init(game: FFGame, key: String) {
        self.game   = game
        self.key    = key
        self.encKey = SymmetricKey(size: .bits256)

        let raw    = "\(DeviceID.hwid):\(key):\(Int(Date().timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        self.sessionToken = digest.map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    func registerEncryptedBlob(_ path: String) { encryptedBlobPaths.append(path) }
    func registerDeployedPath(_ path: String)   { deployedPaths.append(path) }

    // MARK: - Game monitor

    /// Start watching if FF is still in foreground.
    /// iOS doesn't let us query other apps' state directly, so we use two signals:
    /// 1. FFEX becomes active again (user switched back) → FF exited or user left
    /// 2. Poll runningApplications every 2s via LSApplicationWorkspace
    func startMonitoring() {
        monitorTask = Task { [weak self] in
            // Give FF ~2s to actually launch before we start monitoring
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.isActive else { break }

                let running = await Self.isGameRunning(bundleID: self.game.bundleID)
                if !running {
                    log("InjectSession: \(self.game.bundleID) no longer running — wiping")
                    await MainActor.run {
                        self.onGameExited?()
                    }
                    break
                }
            }
        }
    }

    /// Check via LSApplicationWorkspace if the game is in running apps list
    private static func isGameRunning(bundleID: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard
                    let ws = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
                    let instance = ws.perform(Selector(("defaultWorkspace")))?.takeUnretainedValue() as? NSObject,
                    let apps = instance.perform(Selector(("runningApplications")))?.takeUnretainedValue() as? [NSObject]
                else {
                    // Can't query — assume still running, don't wipe aggressively
                    continuation.resume(returning: true)
                    return
                }
                let running = apps.contains { app in
                    let bid = app.perform(Selector(("bundleIdentifier")))?.takeUnretainedValue() as? String
                    return bid == bundleID
                }
                continuation.resume(returning: running)
            }
        }
    }

    // MARK: - Invalidate

    func invalidate() {
        guard isActive else { return }
        isActive = false
        monitorTask?.cancel()
        monitorTask = nil
        wipeAll()
    }

    private func wipeAll() {
        let fm = FileManager.default
        for path in deployedPaths    { securewipe(path: path, fm: fm) }
        for path in encryptedBlobPaths { securewipe(path: path, fm: fm) }
        deployedPaths.removeAll()
        encryptedBlobPaths.removeAll()
        log("InjectSession: wiped all files for \(game.bundleID)")
    }

    private func securewipe(path: String, fm: FileManager) {
        guard fm.fileExists(atPath: path) else { return }
        // Overwrite with zeros then random, then delete
        if let size = try? fm.attributesOfItem(atPath: path)[.size] as? Int, size > 0 {
            let zeros = Data(repeating: 0, count: min(size, 65536))
            try? zeros.write(to: URL(fileURLWithPath: path))
            let junk = Data((0..<min(size, 65536)).map { _ in UInt8.random(in: 0...255) })
            try? junk.write(to: URL(fileURLWithPath: path))
        }
        try? fm.removeItem(atPath: path)
    }

    deinit {
        if isActive { wipeAll() }
    }
}

// MARK: - FFInjectService

enum FFInjectService {

    static func inject(game: FFGame, key: String) async throws -> InjectSession {
        let session = InjectSession(game: game, key: key)

        guard let containerPath = ContainerStore.resolveAppContainerPath(bundleID: game.bundleID) else {
            throw FFInjectError.containerNotFound
        }

        let handle = ContainerStore.grantContainerAccess(containerPath)
        defer { if handle >= 0 { bad_query_release(handle) } }

        let docsURL = URL(fileURLWithPath: containerPath)
            .appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffex_\(session.sessionToken)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        for file in CheatFiles.all {
            guard let url = Repo.rawURL(file: file) else {
                throw FFInjectError.fileUnavailable(file)
            }

            var req = URLRequest(url: url, timeoutInterval: 30)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (rawData, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, !rawData.isEmpty else {
                throw FFInjectError.fileUnavailable(file)
            }

            // For localConfig.json: stamp with session token + HWID
            // This makes copied files useless — they carry a device-bound token
            // that the original game session validates against FFEX server
            let plainData: Data
            if file == CheatFiles.localConfig {
                plainData = stampLocalConfig(data: rawData, session: session)
            } else {
                plainData = rawData
            }

            // Encrypt → temp blob → decrypt → atomic write to game folder
            let sealed = try AES.GCM.seal(plainData, using: session.encKey)
            guard let encData = sealed.combined else { throw FFInjectError.integrityFailed }

            let blobURL = tmpDir.appendingPathComponent("\(file).enc")
            try encData.write(to: blobURL)
            session.registerEncryptedBlob(blobURL.path)

            let box2 = try AES.GCM.SealedBox(combined: encData)
            let decrypted = try AES.GCM.open(box2, using: session.encKey)
            let destURL = docsURL.appendingPathComponent(file)
            try writeAtomic(data: decrypted, to: destURL)
            session.registerDeployedPath(destURL.path)

            log("FFInject: deployed \(file)")
        }

        log("FFInject: COMPLETE \(game.bundleID)")
        return session
    }

    // MARK: - Stamp localConfig with session token (anti-copy)

    private static func stampLocalConfig(data: Data, session: InjectSession) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        // Inject session binding — FF reads this file but ignores unknown keys
        // Copied file carries wrong token = server can detect unauthorised use
        json["_ffex_token"] = session.sessionToken
        json["_ffex_hwid"]  = DeviceID.hwid
        json["_ffex_ts"]    = Int(Date().timeIntervalSince1970)
        let stamped = (try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)) ?? data
        return stamped
    }

    // MARK: - Launch

    static func launchGame(_ game: FFGame) {
        let bundleID = game.bundleID
        DispatchQueue.main.async {
            guard
                let ws = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
                let instance = ws.perform(Selector(("defaultWorkspace")))?.takeUnretainedValue() as? NSObject
            else { return }
            _ = instance.perform(Selector(("openApplicationWithBundleID:")), with: bundleID)
            log("FFInject: launched \(bundleID)")
        }
    }

    // MARK: - Terminate

    static func terminateSession(_ session: InjectSession) {
        session.invalidate()
        log("FFInject: session terminated \(session.game.bundleID)")
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
