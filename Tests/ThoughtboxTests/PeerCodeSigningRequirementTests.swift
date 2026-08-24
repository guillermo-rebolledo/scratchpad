import Testing
import ThoughtboxSelectionSupport

struct PeerCodeSigningRequirementTests {
    @Test("Release peer requirements bind the bundle identifier to the expected team")
    func teamRequirement() {
        let requirement = PeerCodeSigningRequirement.make(
            bundleIdentifier: "com.memoji.Thoughtbox.SelectionHelper",
            teamIdentifier: "LY8CA9554J",
            permitsIdentifierOnly: false
        )

        #expect(requirement.contains("anchor apple generic"))
        #expect(requirement.contains("com.memoji.Thoughtbox.SelectionHelper"))
        #expect(requirement.contains("LY8CA9554J"))
    }

    @Test("Missing production identity fails closed while explicit ad-hoc development stays usable")
    func missingIdentityBehavior() {
        #expect(PeerCodeSigningRequirement.make(
            bundleIdentifier: "com.memoji.Thoughtbox",
            teamIdentifier: nil,
            permitsIdentifierOnly: false
        ) == "never")
        #expect(PeerCodeSigningRequirement.make(
            bundleIdentifier: "com.memoji.Thoughtbox",
            teamIdentifier: nil,
            permitsIdentifierOnly: true
        ) == "identifier \"com.memoji.Thoughtbox\"")
    }
}
