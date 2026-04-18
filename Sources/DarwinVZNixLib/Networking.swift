import Foundation

enum NetworkError: LocalizedError {
    case sshKeyGenerationFailed(Int32)
    case sshConnectionFailed(Int32)
    case sshKeyNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .sshKeyGenerationFailed(status):
            return "SSH key generation failed with exit code: \(status)"
        case let .sshConnectionFailed(status):
            return "SSH connection failed with exit code: \(status)"
        case let .sshKeyNotFound(path):
            return "SSH key not found at: \(path)"
        }
    }
}

struct NetworkManager {
    let stateDirectory: URL

    var sshKeyPath: URL {
        VMConfig.sshKeyURL(for: stateDirectory)
    }

    func ensureSSHKeys() throws {
        let sshDir = VMConfig.sshDirectory(for: stateDirectory)

        try FileManager.default.createDirectory(
            at: sshDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        if FileManager.default.fileExists(atPath: sshKeyPath.path) {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = [
            "-q",
            "-f", sshKeyPath.path,
            "-t", "ed25519",
            "-N", "",
            "-C", "builder@darwin-vz-nix",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NetworkError.sshKeyGenerationFailed(process.terminationStatus)
        }
    }

    func guestAddress(hostname: String) -> String {
        "\(hostname).local"
    }

    func readGuestHostname() -> String {
        let guestHostnameFileURL = VMConfig.guestHostnameFileURL(for: stateDirectory)
        guard let content = try? String(contentsOf: guestHostnameFileURL, encoding: .utf8) else {
            return Constants.defaultGuestHostname
        }

        let hostname = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return hostname.isEmpty ? Constants.defaultGuestHostname : hostname
    }

    func writeGuestHostname(_ hostname: String) throws {
        let guestHostnameFileURL = VMConfig.guestHostnameFileURL(for: stateDirectory)
        try hostname.write(to: guestHostnameFileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: guestHostnameFileURL.path
        )
    }

    // MARK: - SSH Connection

    func connectSSH(hostname: String, extraArgs: [String] = []) throws {
        guard FileManager.default.fileExists(atPath: sshKeyPath.path) else {
            throw NetworkError.sshKeyNotFound(sshKeyPath.path)
        }

        let guestAddress = guestAddress(hostname: hostname)

        let arguments = [
            "/usr/bin/ssh",
            "-i", sshKeyPath.path,
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=\(stateDirectory.appendingPathComponent("ssh/known_hosts").path)",
            "-o", "LogLevel=ERROR",
            "builder@\(guestAddress)",
        ] + extraArgs

        // Use execv to replace the current process with ssh.
        // Process() doesn't transfer terminal control to the child,
        // which prevents the login shell from starting interactively.
        let cArgs = arguments.map { strdup($0) } + [nil]
        execv("/usr/bin/ssh", cArgs)

        // execv only returns on failure
        throw NetworkError.sshConnectionFailed(errno)
    }
}
