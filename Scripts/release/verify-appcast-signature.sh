#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' "Usage: $0 APPCAST PUBLIC_KEY" >&2
    exit 64
fi

appcast_path="$1"
public_key="$2"
[ -f "$appcast_path" ] || {
    printf '%s\n' "Appcast not found: $appcast_path" >&2
    exit 66
}

xcrun swift - "$appcast_path" "$public_key" <<'SWIFT'
import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let appcastURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard
    let appcast = try? Data(contentsOf: appcastURL, options: .mappedIfSafe),
    let publicKeyData = Data(base64Encoded: CommandLine.arguments[2]),
    publicKeyData.count == 32
else {
    fail("Could not read the signed appcast or its EdDSA public key.")
}

let prefix = Data("<!-- sparkle-signatures:\n".utf8)
let suffix = Data("-->".utf8)
guard
    let prefixRange = appcast.range(of: prefix, options: .backwards),
    let suffixRange = appcast.range(of: suffix, in: prefixRange.upperBound..<appcast.endIndex),
    let signingBlock = String(
        data: appcast[prefixRange.upperBound..<suffixRange.lowerBound],
        encoding: .utf8
    )
else {
    fail("The appcast does not contain a valid Sparkle signing block.")
}

var encodedSignature: String?
var expectedLength: Int?
for line in signingBlock.split(whereSeparator: \Character.isNewline) {
    if line.hasPrefix("edSignature:") {
        encodedSignature = line.dropFirst("edSignature:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    } else if line.hasPrefix("length:") {
        expectedLength = Int(
            line.dropFirst("length:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

let signedContent = Data(appcast[..<prefixRange.lowerBound])
guard
    expectedLength == signedContent.count,
    let encodedSignature,
    let signature = Data(base64Encoded: encodedSignature),
    signature.count == 64,
    let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
    key.isValidSignature(signature, for: signedContent)
else {
    fail("The appcast does not match its Sparkle EdDSA signature.")
}

print("Appcast EdDSA signature verified.")
SWIFT
