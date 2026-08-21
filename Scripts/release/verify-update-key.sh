#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' "Usage: $0 PATH_TO_THOUGHTBOX_APP PRIVATE_KEY" >&2
    exit 64
fi

app_path="$1"
private_key_path="$2"
info_path="$app_path/Contents/Info.plist"
[ -f "$info_path" ] || {
    printf '%s\n' "Archived app Info.plist not found: $info_path" >&2
    exit 66
}
[ -f "$private_key_path" ] || {
    printf '%s\n' "Protected Sparkle private key not found: $private_key_path" >&2
    exit 66
}

xcrun swift - "$private_key_path" "$info_path" <<'SWIFT'
import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let privateKeyPath = CommandLine.arguments[1]
let infoPath = CommandLine.arguments[2]
let encodedSeed: String
do {
    encodedSeed = try String(contentsOfFile: privateKeyPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
} catch {
    fail("Could not read the protected Sparkle private key.")
}
guard let seed = Data(base64Encoded: encodedSeed), seed.count == 32 else {
    fail("The protected Sparkle private key must be a base64-encoded 32-byte seed.")
}
guard
    let infoData = FileManager.default.contents(atPath: infoPath),
    let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
    let encodedPublicKey = info["SUPublicEDKey"] as? String,
    let embeddedPublicKey = Data(base64Encoded: encodedPublicKey),
    embeddedPublicKey.count == 32
else {
    fail("The archived app has no valid SUPublicEDKey.")
}

let privateKey: Curve25519.Signing.PrivateKey
do {
    privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
} catch {
    fail("The protected Sparkle private key is invalid.")
}
guard privateKey.publicKey.rawRepresentation == embeddedPublicKey else {
    fail("The protected Sparkle private key does not match SUPublicEDKey in the archived app.")
}

print("Protected Sparkle key matches the archived app.")
SWIFT
