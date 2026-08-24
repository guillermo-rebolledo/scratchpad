import Foundation
import Security

public enum PeerCodeSigningRequirement {
    // CS_ADHOC from the Security framework's code-signing flags.
    private static let adHocSignatureFlag: UInt32 = 0x0000_0002
    public static func forPeer(
        bundleIdentifier: String,
        ownBundleURL: URL = Bundle.main.bundleURL
    ) -> String {
        let identity = signingIdentity(at: ownBundleURL)
#if DEBUG
        let permitsIdentifierOnly = identity?.isAdHoc == true
#else
        let permitsIdentifierOnly = false
#endif
        return make(
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: identity?.teamIdentifier,
            permitsIdentifierOnly: permitsIdentifierOnly
        )
    }

    public static func make(
        bundleIdentifier: String,
        teamIdentifier: String?,
        permitsIdentifierOnly: Bool
    ) -> String {
        if let teamIdentifier, !teamIdentifier.isEmpty {
            return "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        }
        if permitsIdentifierOnly {
            return "identifier \"\(bundleIdentifier)\""
        }
        return "never"
    }

    private static func signingIdentity(at bundleURL: URL) -> (teamIdentifier: String?, isAdHoc: Bool)? {
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
        let rawFlags = (values[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
        return (
            values[kSecCodeInfoTeamIdentifier] as? String,
            rawFlags & adHocSignatureFlag != 0
        )
    }
}
