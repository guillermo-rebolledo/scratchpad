#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    printf '%s\n' "Usage: $0 UPDATE_ARCHIVE EDDSA_SIGNATURE PUBLIC_KEY" >&2
    exit 64
fi

archive_path="$1"
signature="$2"
public_key="$3"
[ -f "$archive_path" ] || {
    printf '%s\n' "Update archive not found: $archive_path" >&2
    exit 66
}

xcrun swift - "$archive_path" "$signature" "$public_key" <<'SWIFT'
import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let archivePath = CommandLine.arguments[1]
guard
    let signature = Data(base64Encoded: CommandLine.arguments[2]),
    signature.count == 64,
    let publicKeyData = Data(base64Encoded: CommandLine.arguments[3]),
    publicKeyData.count == 32,
    let archive = try? Data(contentsOf: URL(fileURLWithPath: archivePath), options: .mappedIfSafe),
    let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
    publicKey.isValidSignature(signature, for: archive)
else {
    fail("The update archive does not match its Sparkle EdDSA signature.")
}

print("Update archive EdDSA signature verified.")
SWIFT
