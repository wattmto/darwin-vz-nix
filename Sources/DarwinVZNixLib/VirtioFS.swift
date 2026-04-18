import Foundation
@preconcurrency import Virtualization

enum VirtioFSError: LocalizedError {
    case rosettaNotAvailable
    case rosettaNotInstalled
    case sharedDirectoryFailed(String)

    var errorDescription: String? {
        switch self {
        case .rosettaNotAvailable:
            return "Rosetta is not available on this platform (requires Apple Silicon)."
        case .rosettaNotInstalled:
            return "Rosetta is not installed. Install with: softwareupdate --install-rosetta"
        case let .sharedDirectoryFailed(reason):
            return "Failed to configure shared directory: \(reason)"
        }
    }
}

enum VirtioFSManager {
    /// Configure VirtioFS share for host's /nix/store (read-only)
    static func createNixStoreShare() throws -> VZVirtioFileSystemDeviceConfiguration {
        let nixStorePath = URL(fileURLWithPath: "/nix/store")
        guard FileManager.default.fileExists(atPath: nixStorePath.path) else {
            throw VirtioFSError.sharedDirectoryFailed("/nix/store does not exist on host")
        }

        return try createDirectoryShare(url: nixStorePath, tag: Constants.nixStoreTag, readOnly: true)
    }

    /// Configure Rosetta directory share (if available)
    /// Returns nil if Rosetta is not available (graceful degradation)
    static func createRosettaShare(required: Bool = false) throws -> VZVirtioFileSystemDeviceConfiguration? {
        // Check availability
        let availability = VZLinuxRosettaDirectoryShare.availability

        switch availability {
        case .notSupported:
            if required {
                throw VirtioFSError.rosettaNotAvailable
            }
            DaemonLogger.vm.warning("Rosetta is not supported on this platform. x86_64 builds will not be available.")
            return nil

        case .notInstalled:
            if required {
                throw VirtioFSError.rosettaNotInstalled
            }
            DaemonLogger.vm.warning("Rosetta is not installed. x86_64 builds will not be available.")
            DaemonLogger.vm.info("Install with: softwareupdate --install-rosetta")
            return nil

        case .installed:
            let rosettaShare = try VZLinuxRosettaDirectoryShare()
            let fsConfig = VZVirtioFileSystemDeviceConfiguration(tag: Constants.rosettaTag)
            fsConfig.share = rosettaShare
            DaemonLogger.vm.info("Rosetta 2 enabled for x86_64 binary execution.")
            return fsConfig

        @unknown default:
            DaemonLogger.vm.warning("Unknown Rosetta availability status. Skipping.")
            return nil
        }
    }

    /// Configure VirtioFS share for SSH keys (so guest can read host's public key)
    static func createSSHKeysShare(sshDirectory: URL) throws -> VZVirtioFileSystemDeviceConfiguration {
        guard FileManager.default.fileExists(atPath: sshDirectory.path) else {
            throw VirtioFSError.sharedDirectoryFailed("SSH directory does not exist: \(sshDirectory.path)")
        }

        return try createDirectoryShare(url: sshDirectory, tag: Constants.sshKeysTag, readOnly: true)
    }

    static func createSharedDirectoryConfigShare(configDirectory: URL) throws -> VZVirtioFileSystemDeviceConfiguration {
        guard FileManager.default.fileExists(atPath: configDirectory.path) else {
            throw VirtioFSError.sharedDirectoryFailed("Shared directory config directory does not exist: \(configDirectory.path)")
        }

        return try createDirectoryShare(url: configDirectory, tag: Constants.sharedDirectoryConfigTag, readOnly: true)
    }

    static func createSharedDirectoryShare(_ sharedDirectory: SharedDirectory, index: Int) throws -> VZVirtioFileSystemDeviceConfiguration {
        guard FileManager.default.fileExists(atPath: sharedDirectory.hostPath.path) else {
            throw VirtioFSError.sharedDirectoryFailed("Shared directory host path does not exist: \(sharedDirectory.hostPath.path)")
        }

        return try createDirectoryShare(
            url: sharedDirectory.hostPath,
            tag: Constants.sharedDirectoryTag(for: index),
            readOnly: sharedDirectory.readOnly
        )
    }

    private static func createDirectoryShare(url: URL, tag: String, readOnly: Bool) throws -> VZVirtioFileSystemDeviceConfiguration {
        let sharedDir = VZSharedDirectory(url: url, readOnly: readOnly)
        let share = VZSingleDirectoryShare(directory: sharedDir)
        let fsConfig = VZVirtioFileSystemDeviceConfiguration(tag: tag)
        fsConfig.share = share
        return fsConfig
    }
}
