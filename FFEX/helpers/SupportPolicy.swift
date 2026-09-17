import Foundation

enum ExploitSupportPolicy {

    static let verifiedIOS16Range = "16.0–16.7.x"
    static let verifiedIOS17Range = "17.0–17.7.x"
    static let verifiedIOS18Range = "18.0–18.7.1"
    static let verifiedIOS26Range = "26.0–26.6.1"

    static let verifiedIOS27Builds: [(beta: Int, build: String)] = [
        (1, "24A5355q"),
        (2, "24A5370h"),
        (3, "24A5380h"),
        (4, "24A5390f"),
    ]

    static func iOS27BetaNumber(for build: String) -> Int? {
        verifiedIOS27Builds.first { $0.build == build }?.beta
    }

    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }

        if major == 16 { return minor <= 7 }
        if major == 17 { return minor <= 7 }
        if major == 18 { return minor < 7 || (minor == 7 && patch <= 1) }
        if major == 26 { return minor < 6 || (minor == 6 && patch <= 1) }

        guard major == 27, minor == 0, patch == 0 else { return false }
        return iOS27BetaNumber(for: build) != nil
    }
}
