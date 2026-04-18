@testable import DarwinVZNixLib
import Foundation
import Testing

@Suite("Constants", .tags(.unit))
struct ConstantsTests {
    @Test("nixStoreTag has expected string value")
    func nixStoreTagValue() {
        #expect(Constants.nixStoreTag == "nix-store")
    }

    @Test("rosettaTag has expected string value")
    func rosettaTagValue() {
        #expect(Constants.rosettaTag == "rosetta")
    }

    @Test("sshKeysTag has expected string value")
    func sshKeysTagValue() {
        #expect(Constants.sshKeysTag == "ssh-keys")
    }

    @Test("defaultGuestHostname has expected value")
    func defaultGuestHostnameValue() {
        #expect(Constants.defaultGuestHostname == "darwin-vz-guest")
    }

    @Test("shared directory config tag has expected string value")
    func sharedDirectoryConfigTagValue() {
        #expect(Constants.sharedDirectoryConfigTag == "shared-dir-config")
    }

    @Test("shared directory tags are generated deterministically")
    func sharedDirectoryTagValue() {
        #expect(Constants.sharedDirectoryTag(for: 0) == "shared-dir-1")
        #expect(Constants.sharedDirectoryTag(for: 1) == "shared-dir-2")
    }

    @Test("MAC address matches valid format")
    func macAddressFormat() throws {
        let pattern = #"^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(Constants.macAddressString.startIndex..., in: Constants.macAddressString)
        let match = regex.firstMatch(in: Constants.macAddressString, range: range)
        #expect(match != nil, "MAC address '\(Constants.macAddressString)' does not match expected format")
    }
}
