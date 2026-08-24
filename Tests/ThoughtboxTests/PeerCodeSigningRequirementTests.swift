import Testing
import ThoughtboxSelectionSupport

struct PeerCodeSigningRequirementTests {
    @Test("Release peer requirements bind the bundle identifier to the expected team")
    func teamRequirement() {
        let requirement = PeerCodeSigningRequirement.make(
            bundleIdentifier: "com.memoji.Thoughtbox.SelectionHelper",
            teamIdentifier: "LY8CA9554J"
        )

        #expect(requirement.contains("anchor apple generic"))
        #expect(requirement.contains("com.memoji.Thoughtbox.SelectionHelper"))
        #expect(requirement.contains("LY8CA9554J"))
    }

    @Test("Missing cryptographic identity always fails closed")
    func missingIdentityFailsClosed() {
        #expect(PeerCodeSigningRequirement.make(
            bundleIdentifier: "com.memoji.Thoughtbox",
            teamIdentifier: nil
        ) == "never")
    }
}
