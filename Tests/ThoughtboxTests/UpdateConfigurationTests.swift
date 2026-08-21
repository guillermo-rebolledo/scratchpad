import Foundation
import Testing
@testable import Thoughtbox

struct UpdateConfigurationTests {
    @Test("Production update configuration requires HTTPS, EdDSA, automatic checks, and no profile telemetry")
    func validatesProductionConfiguration() throws {
        let configuration = try UpdateConfiguration(info: [
            "SUFeedURL": "https://raw.githubusercontent.com/guillermo-rebolledo/scratchpad/main/appcast.xml",
            "SUPublicEDKey": "OdMPoaRIAP7E/QFHqWwXz+5c/E7qS6XjM/VH9NlUXbY=",
            "SUEnableAutomaticChecks": true,
            "SUEnableInstallerLauncherService": true,
            "SUSendProfileInfo": false,
        ])

        #expect(configuration.feedURL.scheme == "https")
        #expect(configuration.publicKey.count == 32)
        #expect(configuration.automaticallyChecksForUpdates)
        #expect(configuration.usesInstallerLauncherService)
        #expect(!configuration.sendsProfileInformation)
    }

    @Test("Update configuration rejects an insecure or incomplete channel")
    func rejectsUnsafeConfiguration() {
        let invalidConfigurations: [[String: Any]] = [
            [
            "SUFeedURL": "http://updates.example.com/appcast.xml",
            "SUPublicEDKey": "OdMPoaRIAP7E/QFHqWwXz+5c/E7qS6XjM/VH9NlUXbY=",
            "SUEnableAutomaticChecks": true,
            "SUEnableInstallerLauncherService": true,
            "SUSendProfileInfo": false,
            ],
            [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": "not-a-key",
            "SUEnableAutomaticChecks": true,
            "SUEnableInstallerLauncherService": true,
            "SUSendProfileInfo": false,
            ],
            [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": "OdMPoaRIAP7E/QFHqWwXz+5c/E7qS6XjM/VH9NlUXbY=",
            "SUEnableAutomaticChecks": false,
            "SUEnableInstallerLauncherService": true,
            "SUSendProfileInfo": false,
            ],
            [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": "OdMPoaRIAP7E/QFHqWwXz+5c/E7qS6XjM/VH9NlUXbY=",
            "SUEnableAutomaticChecks": true,
            "SUEnableInstallerLauncherService": true,
            "SUSendProfileInfo": true,
            ],
        ]

        for info in invalidConfigurations {
            #expect(throws: UpdateConfiguration.Error.self) {
                try UpdateConfiguration(info: info)
            }
        }
    }

    @Test("Checked-in release metadata matches the production channel contract")
    func checkedInMetadata() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoData = try Data(contentsOf: repository.appendingPathComponent("Resources/Info.plist"))
        let info = try #require(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )
        _ = try UpdateConfiguration(info: info)

        let entitlementData = try Data(
            contentsOf: repository.appendingPathComponent("Resources/Thoughtbox.entitlements")
        )
        let entitlements = try #require(
            PropertyListSerialization.propertyList(from: entitlementData, format: nil) as? [String: Any]
        )
        #expect(Set(entitlements.keys) == [
            "com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.network.client",
            "com.apple.security.temporary-exception.mach-lookup.global-name",
        ])
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
        #expect(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool == true)
        #expect(entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String] == [
            "com.memoji.Thoughtbox-spks",
            "com.memoji.Thoughtbox-spki",
        ])
    }
}
