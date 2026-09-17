import Foundation
import Darwin

enum AntiDebug {

    static func runChecks() {
        #if !targetEnvironment(simulator)
        if isBeingDebugged() || fridaDetected() || substrateDetected() || binaryTampered() {
            terminateProcess()
        }
        #endif
    }

    static func startPeriodicChecks() {
        #if !targetEnvironment(simulator)
        Thread.detachNewThread {
            while true {
                Thread.sleep(forTimeInterval: Double.random(in: 25...35))
                if isBeingDebugged() || fridaDetected() || substrateDetected() {
                    terminateProcess()
                }
            }
        }
        #endif
    }

    // MARK: - Debugger detection via sysctl

    private static func isBeingDebugged() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    // MARK: - Frida detection

    private static func fridaDetected() -> Bool {
        let fridaLibs = ["FridaGadget", "frida-agent", "frida_agent", "re.frida.Gadget"]
        for name in fridaLibs {
            if dlopen(name, RTLD_NOLOAD | RTLD_NOW) != nil { return true }
        }
        let paths = ["/tmp/frida-", "/var/mobile/Library/Preferences/frida"]
        for p in paths where FileManager.default.fileExists(atPath: p) { return true }
        if portOpen(27042) { return true }
        return false
    }

    // MARK: - Substrate detection

    private static func substrateDetected() -> Bool {
        let libs = [
            "/usr/lib/libsubstrate.dylib",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/lib/TweakInject.dylib",
            "/var/jb/usr/lib/TweakInject.dylib",
        ]
        return libs.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Binary integrity

    private static func binaryTampered() -> Bool {
        let sig = Bundle.main.bundlePath + "/_CodeSignature/CodeResources"
        return !FileManager.default.fileExists(atPath: sig)
    }

    // MARK: - Port check

    private static func portOpen(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family      = sa_family_t(AF_INET)
        addr.sin_port        = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func terminateProcess() { raise(SIGKILL) }
}
