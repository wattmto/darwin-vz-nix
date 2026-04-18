@testable import DarwinVZNixLib
import Foundation
import Testing

@Suite("Networking Integration", .tags(.integration))
struct NetworkingIntegrationTests {
    // MARK: - Guest hostname roundtrip

    @Test("writeGuestHostname then readGuestHostname returns same hostname")
    func guestHostnameRoundtrip() throws {
        let tempDir = TestHelpers.createTempDirectory()
        defer { TestHelpers.removeTempItem(at: tempDir) }

        let manager = NetworkManager(stateDirectory: tempDir)
        try manager.writeGuestHostname("custom-guest")
        let hostname = manager.readGuestHostname()
        #expect(hostname == "custom-guest")
    }

    @Test("readGuestHostname returns default for non-existent file")
    func readGuestHostnameNonExistent() throws {
        let tempDir = TestHelpers.createTempDirectory()
        defer { TestHelpers.removeTempItem(at: tempDir) }

        let manager = NetworkManager(stateDirectory: tempDir)
        #expect(manager.readGuestHostname() == Constants.defaultGuestHostname)
    }

    // MARK: - SSH Key Generation

    @Test("ensureSSHKeys creates key pair files")
    func ensureSSHKeysCreatesKeyPair() throws {
        let tempDir = TestHelpers.createTempDirectory()
        defer { TestHelpers.removeTempItem(at: tempDir) }

        let manager = NetworkManager(stateDirectory: tempDir)
        try manager.ensureSSHKeys()

        let privateKeyPath = VMConfig.sshKeyURL(for: tempDir).path
        let publicKeyPath = privateKeyPath + ".pub"
        #expect(FileManager.default.fileExists(atPath: privateKeyPath))
        #expect(FileManager.default.fileExists(atPath: publicKeyPath))
    }

    @Test("ensureSSHKeys is idempotent and does not overwrite existing keys")
    func ensureSSHKeysIdempotent() throws {
        let tempDir = TestHelpers.createTempDirectory()
        defer { TestHelpers.removeTempItem(at: tempDir) }

        let manager = NetworkManager(stateDirectory: tempDir)
        try manager.ensureSSHKeys()

        let privateKeyURL = VMConfig.sshKeyURL(for: tempDir)
        let firstContent = try String(contentsOf: privateKeyURL, encoding: .utf8)

        try manager.ensureSSHKeys()

        let secondContent = try String(contentsOf: privateKeyURL, encoding: .utf8)
        #expect(firstContent == secondContent)
    }

    @Test("ensureSSHKeys generates ed25519 public key")
    func ensureSSHKeysKeyFormat() throws {
        let tempDir = TestHelpers.createTempDirectory()
        defer { TestHelpers.removeTempItem(at: tempDir) }

        let manager = NetworkManager(stateDirectory: tempDir)
        try manager.ensureSSHKeys()

        let publicKeyPath = VMConfig.sshKeyURL(for: tempDir).path + ".pub"
        let publicKey = try String(contentsOfFile: publicKeyPath, encoding: .utf8)
        #expect(publicKey.hasPrefix("ssh-ed25519"))
    }
}
