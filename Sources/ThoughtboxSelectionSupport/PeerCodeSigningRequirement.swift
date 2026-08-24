import Foundation
import Security

public enum PeerCodeSigningRequirement {
    public static func forPeer(
        bundleIdentifier: String,
        ownBundleURL: URL = Bundle.main.bundleURL
    ) -> String {
        return make(
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier(at: ownBundleURL)
        )
    }

    public static func make(
        bundleIdentifier: String,
        teamIdentifier: String?
    ) -> String {
        if let teamIdentifier, !teamIdentifier.isEmpty {
            return "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        }
        return "never"
    }

    private static func teamIdentifier(at bundleURL: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let values = information as? [CFString: Any] else {
            return nil
        }
        return values[kSecCodeInfoTeamIdentifier] as? String
    }
}
