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
    let encKey: SymmetricKey

    private(set) var isActive: Bool = true
    private(set) var filesWiped: Bool = false

    // Deployed file paths in game Documents
    private var deployedPaths: [String] = []
    // Temp blob paths
    private var blobPaths: [String] = []

    // Delayed-wipe task
    private var wipeTask: Task<Void, Never>?

    init(game: FFGame, key: String) {
        self.game   = game
        self.key    = key
        self.encKey = SymmetricKey(size: .bits256)
        let raw     = "\(DeviceID.hwid):\(key):\(Int(Date().timeIntervalSince1970))"
        let digest  = SHA256.hash(data: Data(raw.utf8))
        self.sessionToken = digest.map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    func registerDeployedPath(_ path: String) { deployedPaths.append(path) }
    func registerBlobPath(_ path: String)      { blobPaths.append(path) }

    // MARK: - Delayed wipe (called right after FF launches)
    // FF reads Assembly-CSharp-patch.bytes once during IL2CPP startup (~10-15s)
    // After 5s we can safely delete — patch already loaded into memory
    // localConfig.json replaced with empty {} so FF relogin finds nothing useful

    func scheduleDelayedWipe(afterSeconds: Double = 5) {
        wipeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.wipeDeployedFiles()
                log("InjectSession: delayed wipe complete — files gone from disk")
            }
        }
    }

    // MARK: - Immediate wipe (called when FFEX becomes active / user switches back)

    func wipeNow() {
        wipeTask?.cancel()
        wipeTask = nil
        wipeDeployedFiles()
        wipeBlobFiles()
        isActive = false
    }

    // MARK: - Wipe deployed files
    // Replace with garbage first, then delete
    // Also write empty {} to localConfig so any re-read by FF gets nothing

    private func wipeDeployedFiles() {
        guard !filesWiped else { return }
        filesWiped = true

        let fm = FileManager.default
        for path in deployedPaths {
            guard fm.fileExists(atPath: path) else { continue }

            // If localConfig.json — overwrite with empty JSON first
            if path.hasSuffix(CheatFiles.localConfig) {
                try? "{}".data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
            }

            // Overwrite with random bytes
            if let size = try? fm.attributesOfItem(atPath: path)[.size] as? Int, size > 0 {
                let junk = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
                try? junk.write(to: URL(fileURLWithPath: path))
            }
            // Delete
            try? fm.removeItem(atPath: path)
            log("InjectSession: wiped \(URL(fileURLWithPath: path).lastPathComponent)")
        }
        deployedPaths.removeAll()
    }

    private func wipeBlobFiles() {
        let fm = FileManager.default
        for path in blobPaths {
            try? fm.removeItem(atPath: path)
        }
        blobPaths.removeAll()
    }

    func invalidate() {
        wipeNow()
    }

    deinit {
        wipeTask?.cancel()
        if !filesWiped { wipeDeployedFiles() }
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

            // Stamp localConfig with session token (anti-copy)
            let plainData: Data
            if file == CheatFiles.localConfig {
                plainData = stampLocalConfig(data: rawData, session: session)
            } else {
                plainData = rawData
            }

            // Encrypt → temp blob (anti-forensic)
            let sealed = try AES.GCM.seal(plainData, using: session.encKey)
            guard let encData = sealed.combined else { throw FFInjectError.integrityFailed }
            let blobURL = tmpDir.appendingPathComponent("\(file).enc")
            try encData.write(to: blobURL)
            session.registerBlobPath(blobURL.path)

            // Decrypt → atomic write to game Documents
            let box2      = try AES.GCM.SealedBox(combined: encData)
            let decrypted = try AES.GCM.open(box2, using: session.encKey)
            let destURL   = docsURL.appendingPathComponent(file)
            try writeAtomic(data: decrypted, to: destURL)
            session.registerDeployedPath(destURL.path)

            log("FFInject: deployed \(file)")
        }

        log("FFInject: COMPLETE \(game.bundleID)")
        return session
    }

    // MARK: - Launch + schedule delayed wipe

    static func launchAndScheduleWipe(game: FFGame, session: InjectSession) {
        let bundleID = game.bundleID
        DispatchQueue.main.async {
            guard
                let ws       = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
                let instance = ws.perform(Selector(("defaultWorkspace")))?.takeUnretainedValue() as? NSObject
            else { return }
            _ = instance.perform(Selector(("openApplicationWithBundleID:")), with: bundleID)
            log("FFInject: launched \(bundleID)")

            // FF reads patch file during startup. After 20s it's loaded into memory.
            // Wipe from disk — cheat stays active in FF's memory but file is gone.
            // Relogin/restart FF = file missing = cheat doesn't load.
            session.scheduleDelayedWipe(afterSeconds: 5)
        }
    }

    // MARK: - Terminate (immediate wipe)

    static func terminateSession(_ session: InjectSession) {
        session.invalidate()
    }

    // MARK: - Anti-copy stamp

    private static func stampLocalConfig(data: Data, session: InjectSession) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        json["_ffex_token"] = session.sessionToken
        json["_ffex_hwid"]  = DeviceID.hwid
        json["_ffex_ts"]    = Int(Date().timeIntervalSince1970)
        return (try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)) ?? data
    }

    // MARK: - Atomic write

    private static func writeAtomic(data: Data, to dest: URL) throws {
        let fm  = FileManager.default
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: tmp.path, contents: data) else {
            throw FFInjectError.writeFailed("createFile")
        }
        guard rename(tmp.path, dest.path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw FFInjectError.writeFailed("rename errno=\(errno)")
        }
    }
}
