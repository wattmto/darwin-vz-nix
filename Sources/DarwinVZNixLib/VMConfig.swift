import Foundation

enum VMConfigError: LocalizedError {
    case invalidCoreCount(Int)
    case insufficientMemory(UInt64)
    case kernelNotFound(URL, hint: String?)
    case initrdNotFound(URL, hint: String?)
    case invalidDiskSize(String)
    case invalidGuestHostname(String)
    case invalidSharedDirectorySpec(String)
    case sharedDirectoryHostPathNotFound(URL)
    case sharedDirectoryMountPointNotAbsolute(String)
    case sharedDirectoryMountPointReserved(String)
    case duplicateSharedDirectoryMountPoint(String)
    case stateDirectoryCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidCoreCount(count):
            return "Invalid CPU core count: \(count). Must be at least 1."
        case let .insufficientMemory(mb):
            return "Insufficient memory: \(mb) MB. Must be at least 512 MB."
        case let .kernelNotFound(url, hint):
            var msg = "Kernel image not found at: \(url.path)"
            if let hint { msg += "\nHint: \(hint)" }
            return msg
        case let .initrdNotFound(url, hint):
            var msg = "Initrd image not found at: \(url.path)"
            if let hint { msg += "\nHint: \(hint)" }
            return msg
        case let .invalidDiskSize(size):
            return "Invalid disk size format: '\(size)'. Use format like '100G', '512M', or bytes."
        case let .invalidGuestHostname(hostname):
            return "Invalid guest hostname: '\(hostname)'. Use only letters, numbers, and hyphens."
        case let .invalidSharedDirectorySpec(spec):
            return "Invalid shared directory specification: '\(spec)'. Use hostPath=/path,mountPoint=/guest/path[,readOnly=true] or JSON."
        case let .sharedDirectoryHostPathNotFound(url):
            return "Shared directory host path does not exist or is not a directory: \(url.path)"
        case let .sharedDirectoryMountPointNotAbsolute(mountPoint):
            return "Shared directory mount point must be an absolute path: \(mountPoint)"
        case let .sharedDirectoryMountPointReserved(mountPoint):
            return "Shared directory mount point collides with a reserved guest path: \(mountPoint)"
        case let .duplicateSharedDirectoryMountPoint(mountPoint):
            return "Duplicate shared directory mount point: \(mountPoint)"
        case let .stateDirectoryCreationFailed(path):
            return "Failed to create state directory at: \(path)"
        }
    }
}

struct SharedDirectory: Codable, Equatable {
    let hostPath: URL
    let mountPoint: String
    let readOnly: Bool

    private enum CodingKeys: String, CodingKey {
        case hostPath
        case mountPoint
        case readOnly
    }

    init(hostPath: URL, mountPoint: String, readOnly: Bool = false) {
        self.hostPath = hostPath.resolvingSymlinksInPath()
        self.mountPoint = mountPoint
        self.readOnly = readOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hostPath: URL(fileURLWithPath: try container.decode(String.self, forKey: .hostPath)),
            mountPoint: try container.decode(String.self, forKey: .mountPoint),
            readOnly: try container.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hostPath.path, forKey: .hostPath)
        try container.encode(mountPoint, forKey: .mountPoint)
        try container.encode(readOnly, forKey: .readOnly)
    }

    static func parse(_ specification: String) throws -> SharedDirectory {
        if let data = specification.data(using: .utf8),
           let directory = try? JSONDecoder().decode(SharedDirectory.self, from: data)
        {
            return directory
        }

        var values: [String: String] = [:]
        for rawPair in specification.split(separator: ",", omittingEmptySubsequences: true) {
            let pair = rawPair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else {
                throw VMConfigError.invalidSharedDirectorySpec(specification)
            }
            values[String(pair[0]).trimmingCharacters(in: .whitespaces)] = String(pair[1]).trimmingCharacters(in: .whitespaces)
        }

        guard let hostPath = values["hostPath"], !hostPath.isEmpty,
              let mountPoint = values["mountPoint"], !mountPoint.isEmpty
        else {
            throw VMConfigError.invalidSharedDirectorySpec(specification)
        }

        let readOnly: Bool
        switch values["readOnly"]?.lowercased() {
        case nil, "", "false":
            readOnly = false
        case "true":
            readOnly = true
        default:
            throw VMConfigError.invalidSharedDirectorySpec(specification)
        }

        return SharedDirectory(
            hostPath: URL(fileURLWithPath: hostPath),
            mountPoint: mountPoint,
            readOnly: readOnly
        )
    }
}

struct VMConfig {
    let cores: Int
    let memory: UInt64
    let diskSize: String
    let kernelURL: URL
    let initrdURL: URL
    let systemURL: URL?
    let stateDirectory: URL
    let guestHostname: String
    let rosetta: Bool
    let shareNixStore: Bool
    let sharedDirectories: [SharedDirectory]
    let idleTimeout: Int

    private static let reservedGuestMountPoints = [
        "/nix",
        "/nix/.ro-store",
        "/nix/store",
        "/run/rosetta",
        "/run/ssh-keys",
        "/run/virtiofs-config",
    ]

    static let defaultStateDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("darwin-vz-nix", isDirectory: true)
    }()

    static var defaultPIDFileURL: URL {
        defaultStateDirectory.appendingPathComponent("vm.pid")
    }

    // MARK: - Static Path Helpers

    static func sshKeyURL(for stateDirectory: URL) -> URL {
        stateDirectory
            .appendingPathComponent("ssh", isDirectory: true)
            .appendingPathComponent("id_ed25519")
    }

    static func sshDirectory(for stateDirectory: URL) -> URL {
        stateDirectory.appendingPathComponent("ssh", isDirectory: true)
    }

    static func guestHostnameFileURL(for stateDirectory: URL) -> URL {
        stateDirectory.appendingPathComponent("guest-hostname")
    }

    static func sharedDirectoryConfigDirectory(for stateDirectory: URL) -> URL {
        stateDirectory.appendingPathComponent("virtiofs-config", isDirectory: true)
    }

    static func sharedDirectoryManifestURL(for stateDirectory: URL) -> URL {
        sharedDirectoryConfigDirectory(for: stateDirectory).appendingPathComponent("shared-directories.tsv")
    }

    init(
        cores: Int = 4,
        memory: UInt64 = 8192,
        diskSize: String = "100G",
        kernelURL: URL,
        initrdURL: URL,
        systemURL: URL? = nil,
        stateDirectory: URL? = nil,
        guestHostname: String = Constants.defaultGuestHostname,
        rosetta: Bool = true,
        shareNixStore: Bool = true,
        sharedDirectories: [SharedDirectory] = [],
        idleTimeout: Int = 0
    ) {
        self.cores = cores
        self.memory = memory
        self.diskSize = diskSize
        self.kernelURL = kernelURL.resolvingSymlinksInPath()
        self.initrdURL = initrdURL.resolvingSymlinksInPath()
        self.systemURL = systemURL?.resolvingSymlinksInPath()
        self.stateDirectory = stateDirectory ?? VMConfig.defaultStateDirectory
        self.guestHostname = guestHostname
        self.rosetta = rosetta
        self.shareNixStore = shareNixStore
        self.sharedDirectories = sharedDirectories
        self.idleTimeout = idleTimeout
    }

    // MARK: - Computed Paths

    var diskImageURL: URL {
        stateDirectory.appendingPathComponent("disk.img")
    }

    var sshDirectory: URL {
        VMConfig.sshDirectory(for: stateDirectory)
    }

    var sshKeyURL: URL {
        VMConfig.sshKeyURL(for: stateDirectory)
    }

    var pidFileURL: URL {
        stateDirectory.appendingPathComponent("vm.pid")
    }

    var consoleLogURL: URL {
        stateDirectory.appendingPathComponent("console.log")
    }

    var guestHostnameFileURL: URL {
        VMConfig.guestHostnameFileURL(for: stateDirectory)
    }

    var sharedDirectoryConfigDirectory: URL {
        VMConfig.sharedDirectoryConfigDirectory(for: stateDirectory)
    }

    var sharedDirectoryManifestURL: URL {
        VMConfig.sharedDirectoryManifestURL(for: stateDirectory)
    }

    // MARK: - Validation

    func validate() throws {
        if cores < 1 {
            throw VMConfigError.invalidCoreCount(cores)
        }

        if memory < 512 {
            throw VMConfigError.insufficientMemory(memory)
        }

        if !Self.isValidHostname(guestHostname) {
            throw VMConfigError.invalidGuestHostname(guestHostname)
        }

        if !FileManager.default.fileExists(atPath: kernelURL.path) {
            let dir = kernelURL.deletingLastPathComponent()
            var hint: String?
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("initrd").path) {
                hint = "Found 'initrd' in the same directory, which is an initrd artifact.\n"
                    + "      You may have built guest-initrd instead of guest-kernel into this path."
            }
            throw VMConfigError.kernelNotFound(kernelURL, hint: hint)
        }

        if !FileManager.default.fileExists(atPath: initrdURL.path) {
            let dir = initrdURL.deletingLastPathComponent()
            var hint: String?
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Image").path) {
                hint = "Found 'Image' in the same directory, which is a kernel artifact.\n"
                    + "      You may have built guest-kernel instead of guest-initrd into this path."
            }
            throw VMConfigError.initrdNotFound(initrdURL, hint: hint)
        }

        _ = try VMConfig.parseDiskSize(diskSize)

        var mountPoints = Set<String>()
        for sharedDirectory in sharedDirectories {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sharedDirectory.hostPath.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw VMConfigError.sharedDirectoryHostPathNotFound(sharedDirectory.hostPath)
            }

            guard sharedDirectory.mountPoint.hasPrefix("/"), sharedDirectory.mountPoint != "/" else {
                throw VMConfigError.sharedDirectoryMountPointNotAbsolute(sharedDirectory.mountPoint)
            }

            if Self.reservedGuestMountPoints.contains(where: {
                sharedDirectory.mountPoint == $0 || sharedDirectory.mountPoint.hasPrefix($0 + "/")
            }) {
                throw VMConfigError.sharedDirectoryMountPointReserved(sharedDirectory.mountPoint)
            }

            if !mountPoints.insert(sharedDirectory.mountPoint).inserted {
                throw VMConfigError.duplicateSharedDirectoryMountPoint(sharedDirectory.mountPoint)
            }
        }
    }

    func ensureStateDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: stateDirectory.path) {
            do {
                try fm.createDirectory(
                    at: stateDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
            } catch {
                throw VMConfigError.stateDirectoryCreationFailed(
                    "\(stateDirectory.path): \(error.localizedDescription)"
                )
            }
        }

        if !fm.fileExists(atPath: sharedDirectoryConfigDirectory.path) {
            try fm.createDirectory(
                at: sharedDirectoryConfigDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
        }
    }

    func writeRuntimeConfiguration() throws {
        try ensureStateDirectory()

        try guestHostname.write(to: guestHostnameFileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: guestHostnameFileURL.path
        )

        let manifest = sharedDirectories.enumerated().map { index, sharedDirectory in
            "\(Constants.sharedDirectoryTag(for: index))\t\(sharedDirectory.mountPoint)\t\(sharedDirectory.readOnly)"
        }.joined(separator: "\n")
        let manifestContents = manifest.isEmpty ? "" : manifest + "\n"
        try manifestContents.write(to: sharedDirectoryManifestURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: sharedDirectoryManifestURL.path
        )
    }

    // MARK: - Disk Size Parsing

    static func parseDiskSize(_ size: String) throws -> UInt64 {
        let trimmed = size.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw VMConfigError.invalidDiskSize(size)
        }

        let suffixes: [(String, UInt64)] = [
            ("T", 1024 * 1024 * 1024 * 1024),
            ("G", 1024 * 1024 * 1024),
            ("M", 1024 * 1024),
            ("K", 1024),
        ]

        for (suffix, multiplier) in suffixes {
            if trimmed.uppercased().hasSuffix(suffix) {
                let numberPart = String(trimmed.dropLast(1))
                guard let value = UInt64(numberPart), value > 0 else {
                    throw VMConfigError.invalidDiskSize(size)
                }
                return value * multiplier
            }
        }

        guard let bytes = UInt64(trimmed), bytes > 0 else {
            throw VMConfigError.invalidDiskSize(size)
        }
        return bytes
    }

    private static func isValidHostname(_ hostname: String) -> Bool {
        guard !hostname.isEmpty, hostname.count <= 63 else {
            return false
        }
        guard hostname.first?.isLetter == true || hostname.first?.isNumber == true,
              hostname.last?.isLetter == true || hostname.last?.isNumber == true
        else {
            return false
        }

        return hostname.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-"
        }
    }
}
