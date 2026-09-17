import Foundation

struct ContainerMetadataRecord: Equatable {
    let bundleID: String
    let displayName: String
}

enum ContainerIdentityResolver {
    static func fallbackIdentity(containerPath: String) -> ContainerMetadata {
        let identifier = (containerPath as NSString).lastPathComponent
        let shortIdentifier = String(identifier.prefix(8))
        return ContainerMetadata(
            bundleID: identifier,
            displayName: "Container \(shortIdentifier)"
        )
    }
}
