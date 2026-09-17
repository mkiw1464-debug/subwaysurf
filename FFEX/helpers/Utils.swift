import Foundation
import UIKit
import Darwin
import Combine

// MARK: - XOR decode

private let _k: UInt8 = 0x5A
func _xd(_ b: [UInt8]) -> String {
    String(bytes: b.map { $0 ^ _k }, encoding: .utf8) ?? ""
}

// MARK: - Logger

class AppLog: ObservableObject {
    static let shared = AppLog()
    @Published var entries: [String] = []
    func append(_ msg: String) {
        DispatchQueue.main.async { self.entries.append(msg) }
    }
}

private let _lp: String = _xd([0x1c,0x1c,0x3f,0x22,0x06])  // "FFEX"

func log(_ msg: String) { AppLog.shared.append("[\(_lp)] \(msg)") }

private var _logPipe: Pipe?

func setupLogCapture() {
    guard _logPipe == nil else { return }
    let pipe = Pipe()
    _logPipe = pipe
    setvbuf(stdout, nil, _IONBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
    let wfd = pipe.fileHandleForWriting.fileDescriptor
    guard dup2(wfd, STDOUT_FILENO) >= 0, dup2(wfd, STDERR_FILENO) >= 0 else {
        _logPipe = nil; return
    }
    pipe.fileHandleForReading.readabilityHandler = { h in
        let d = h.availableData
        guard !d.isEmpty, let t = String(data: d, encoding: .utf8) else { return }
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { DispatchQueue.main.async { AppLog.shared.append(s) } }
    }
}

// MARK: - AppInfo

enum AppInfo {
    static var iOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion, v.patchVersion)
    }
    static var osBuild: String {
        var size: size_t = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
        var val = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &val, &size, nil, 0) == 0 else { return "Unknown" }
        return String(cString: val)
    }
    static var machineID: String {
        var s = utsname(); uname(&s)
        return Mirror(reflecting: s.machine).children.reduce("") { acc, e in
            guard let v = e.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(v)))
        }
    }
    static var iPhoneModel: String {
        let id = machineID
        let map: [String: String] = [
            "iPhone18,1":"iPhone 16e",
            "iPhone17,1":"iPhone 16 Pro Max","iPhone17,2":"iPhone 16 Pro",
            "iPhone17,3":"iPhone 16 Plus","iPhone17,4":"iPhone 16",
            "iPhone16,1":"iPhone 15 Pro Max","iPhone16,2":"iPhone 15 Pro",
            "iPhone15,4":"iPhone 15 Plus","iPhone15,5":"iPhone 15",
            "iPhone15,2":"iPhone 14 Pro Max","iPhone15,3":"iPhone 14 Pro",
            "iPhone14,7":"iPhone 14 Plus","iPhone14,8":"iPhone 14",
            "iPhone14,2":"iPhone 13 Pro","iPhone14,3":"iPhone 13 Pro Max",
            "iPhone14,4":"iPhone 13 Mini","iPhone14,5":"iPhone 13",
            "iPhone13,1":"iPhone 12 Mini","iPhone13,2":"iPhone 12",
            "iPhone13,3":"iPhone 12 Pro","iPhone13,4":"iPhone 12 Pro Max",
            "iPhone12,1":"iPhone 11","iPhone12,3":"iPhone 11 Pro","iPhone12,5":"iPhone 11 Pro Max",
            "arm64":"Simulator","x86_64":"Simulator",
        ]
        return map[id] ?? id
    }
    static var deviceName: String { UIDevice.current.name }
}

// MARK: - Exploit status

enum ExploitStatus: Equatable {
    case notStarted
    case success(method: String)
    case failed(method: String, code: Int64)
    case unsupported(String)

    var isSuccess: Bool { if case .success = self { return true }; return false }
    var displayText: String {
        switch self {
        case .notStarted:               return "Not attempted"
        case .success(let m):           return "OK via \(m)"
        case .failed(let m, let c):     return "FAILED \(m) (\(c))"
        case .unsupported(let m):       return "Unsupported: \(m)"
        }
    }
}
