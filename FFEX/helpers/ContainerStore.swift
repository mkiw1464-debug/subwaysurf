import Foundation
import Darwin

enum ContainerStore {
    static let appDataRoot = "/var/mobile/Containers/Data/Application"

    private static var shouldUseBadQuery: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    // MARK: - Public

    static func resolveAppContainerPath(bundleID: String) -> String? {
        var lookupError: NSString?
        if let path = MCMActivateContainerPath(2, bundleID, false, &lookupError),
           isApplicationContainerPath(path) {
            log("ContainerStore: MCM resolved \(bundleID) -> \(path)")
            return path
        }
        log("ContainerStore: MCM failed, metadata scan")
        return resolveByMetadataScan(bundleID: bundleID)
    }

    static func isApplicationContainerPath(_ path: String) -> Bool {
        let root = canonical(appDataRoot)
        let p    = canonical(path)
        guard p.hasPrefix(root + "/") else { return false }
        return UUID(uuidString: (p as NSString).lastPathComponent) != nil
    }

    static func grantContainerAccess(_ containerPath: String) -> Int64 {
        guard shouldUseBadQuery else { return -1 }
        let clean  = containerPath.hasSuffix("/") ? String(containerPath.dropLast()) : containerPath
        var pathC  = clean.utf8CString.map { Int8($0) }
        return bad_query(&pathC, true, nil, false)
    }

    static func enumerateDirectories(path: String) -> [String] {
        let clean = path.hasSuffix("/") ? String(path.dropLast()) : path
        if let names = try? FileManager.default.contentsOfDirectory(atPath: clean), !names.isEmpty {
            return names.map { (clean as NSString).appendingPathComponent($0) }
        }
        var pathC = clean.utf8CString.map { Int8($0) }
        guard let result = bad_query_list(&pathC, 2_000_000) else { return [] }
        defer { free(result) }
        return String(cString: result).components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - Private

    private static func canonical(_ rawPath: String) -> String {
        var path = (rawPath as NSString).standardizingPath
        if path == "/var" || path.hasPrefix("/var/") { path = "/private" + path }
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func resolveByMetadataScan(bundleID: String) -> String? {
        if KernelExploit.requiresSandboxEscape, !KernelExploit.hasSandboxAccess() {
            log("ContainerStore: scan skipped — no sandbox access")
            return nil
        }
        for dir in enumerateDirectories(path: appDataRoot) {
            guard UUID(uuidString: (dir as NSString).lastPathComponent) != nil else { continue }
            guard let meta = readContainerMetadata(containerPath: dir),
                  meta.bundleID == bundleID else { continue }
            let path = canonical(dir)
            guard isApplicationContainerPath(path) else { continue }
            log("ContainerStore: scan resolved \(bundleID) -> \(path)")
            return path
        }
        return nil
    }

    private static func readContainerMetadata(containerPath: String) -> ContainerMetadata? {
        let metaPath = (containerPath as NSString)
            .appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
        var data: Data?
        if let fd = fopen(metaPath, "r") {
            var buf   = [UInt8](repeating: 0, count: 65536)
            var bytes = [UInt8]()
            while true {
                let n = fread(&buf, 1, buf.count, fd)
                if n <= 0 { break }
                bytes.append(contentsOf: buf[0..<n])
            }
            fclose(fd)
            if !bytes.isEmpty { data = Data(bytes) }
        }
        if data == nil { data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)) }
        guard let d = data,
              let pl = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any]
        else { return nil }
        let bundleID    = pl["MCMMetadataIdentifier"] as? String ?? ""
        let displayName = (pl["MCMMetadataInfo"] as? [String: Any])
            .flatMap { ($0["CFBundleDisplayName"] ?? $0["CFBundleName"]) as? String } ?? ""
        return ContainerMetadata(bundleID: bundleID, displayName: displayName)
    }
}
