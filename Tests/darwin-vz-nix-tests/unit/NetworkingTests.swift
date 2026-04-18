@testable import DarwinVZNixLib
import Foundation
import Testing

@Suite("Networking", .tags(.unit))
struct NetworkingTests {
    @Test("guestAddress appends .local suffix")
    func guestAddressUsesLocalSuffix() {
        let manager = NetworkManager(stateDirectory: URL(fileURLWithPath: "/tmp/test-state"))
        #expect(manager.guestAddress(hostname: "darwin-vz-guest") == "darwin-vz-guest.local")
    }

    @Test("readGuestHostname falls back to default when state file is missing")
    func readGuestHostnameUsesDefault() {
        let manager = NetworkManager(stateDirectory: URL(fileURLWithPath: "/tmp/nonexistent-state"))
        #expect(manager.readGuestHostname() == Constants.defaultGuestHostname)
    }

    @Test("sshKeyGenerationFailed error description is non-nil and contains exit code")
    func errorDescriptionSSHKeyGenerationFailed() throws {
        let error = NetworkError.sshKeyGenerationFailed(1)
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(try #require(desc?.contains("1")))
        #expect(try #require(desc?.contains("key generation")))
    }

    @Test("sshConnectionFailed error description is non-nil and contains exit code")
    func errorDescriptionSSHConnectionFailed() throws {
        let error = NetworkError.sshConnectionFailed(255)
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(try #require(desc?.contains("255")))
        #expect(try #require(desc?.contains("connection")))
    }

    @Test("sshKeyNotFound error description is non-nil and contains path")
    func errorDescriptionSSHKeyNotFound() throws {
        let error = NetworkError.sshKeyNotFound("/some/path/id_ed25519")
        let desc = error.errorDescription
        #expect(desc != nil)
        #expect(try #require(desc?.contains("/some/path/id_ed25519")))
    }
}
