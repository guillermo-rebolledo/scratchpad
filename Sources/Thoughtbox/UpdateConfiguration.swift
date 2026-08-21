import Foundation

struct UpdateConfiguration: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        case invalidFeedURL
        case invalidPublicKey
        case automaticChecksDisabled
        case installerLauncherDisabled
        case profileInformationEnabled
    }

    let feedURL: URL
    let publicKey: Data
    let automaticallyChecksForUpdates: Bool
    let usesInstallerLauncherService: Bool
    let sendsProfileInformation: Bool

    init(info: [String: Any]) throws {
        guard
            let feed = info["SUFeedURL"] as? String,
            let feedURL = URL(string: feed),
            feedURL.scheme?.lowercased() == "https",
            feedURL.host != nil
        else {
            throw Error.invalidFeedURL
        }
        guard
            let encodedKey = info["SUPublicEDKey"] as? String,
            let publicKey = Data(base64Encoded: encodedKey),
            publicKey.count == 32
        else {
            throw Error.invalidPublicKey
        }
        guard info["SUEnableAutomaticChecks"] as? Bool == true else {
            throw Error.automaticChecksDisabled
        }
        guard info["SUEnableInstallerLauncherService"] as? Bool == true else {
            throw Error.installerLauncherDisabled
        }
        guard info["SUSendProfileInfo"] as? Bool != true else {
            throw Error.profileInformationEnabled
        }

        self.feedURL = feedURL
        self.publicKey = publicKey
        automaticallyChecksForUpdates = true
        usesInstallerLauncherService = true
        sendsProfileInformation = false
    }
}
