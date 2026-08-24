# Thoughtbox direct beta release

Thoughtbox ships as an unlisted direct download. A beta user downloads the app, moves it to Applications, and runs it without an App Store account, Thoughtbox account, invitation, license, or payment. Gatekeeper trust comes from Developer ID signing and Apple notarization; update authenticity comes from Developer ID plus Sparkle EdDSA signatures.

## Security contract

- Sparkle is pinned to 2.9.2 through Swift Package Manager.
- `Resources/Info.plist` uses the production HTTPS feed at `https://raw.githubusercontent.com/guillermo-rebolledo/scratchpad/main/appcast.xml`, embeds the public EdDSA key, enables automatic checks and the installer launcher, and explicitly disables profile reporting.
- The private Sparkle key is stored under the `com.memoji.Thoughtbox` account in the release owner's Keychain. CI receives an exported seed only through the protected `SPARKLE_PRIVATE_KEY` secret. Never commit or attach that seed.
- Release entitlements are an allowlist: App Sandbox, user-selected read/write export, outbound network access, and the two Sparkle installer Mach service names. Incoming networking, broad file access, automation, microphone, camera, location, contacts, profiling, and `get-task-allow` are forbidden.
- Release configuration requires hardened runtime, a timestamped Developer ID Application signature, strict verification of every nested code bundle, accepted notarization, a stapled ticket, and successful Gatekeeper assessment.
- Capture Selection uses the mutually authenticated, on-demand `ThoughtboxSelectionHelper.xpc`. The main app remains sandboxed; the narrowly scoped helper is unsandboxed because cross-application Accessibility inspection is incompatible with App Sandbox. The helper has no extra entitlements and selected text is never logged or persisted by the helper. See [ADR 0003](adr/0003-isolate-selection-access-in-an-xpc-helper.md).

## Responsibilities

| Area | Responsible role | Required action |
| --- | --- | --- |
| Developer ID | Apple Developer Account Holder | Renew/revoke the Developer ID Application certificate and protect its P12/password. |
| Notarization | Release owner | Maintain the least-privilege App Store Connect notary API key and inspect rejected submission logs. |
| Sparkle signing | Security owner | Back up and rotate the `com.memoji.Thoughtbox` EdDSA seed; update the embedded public key only through a planned channel migration. |
| Appcast hosting | Release owner | Keep the public repository and `main/appcast.xml` available over HTTPS; publish an appcast only after its archive URL is final. |
| Release approval | QA owner | Perform the clean-Mac install/update check and approve the draft release. |
| Rollback | Release owner + security owner | Remove a bad appcast item, restore the last known-good signed appcast, and publish a higher build number containing the fix. Never reuse or decrement a build number. |

No secret value belongs in source, workflow YAML, build logs, Linear, release notes, or artifacts. GitHub secret scanning and branch protection must cover `main`; release credentials are limited to the manual release environment.

## Protected CI secrets

Configure these only in the protected GitHub release environment:

- `DEVELOPER_ID_APPLICATION`: full certificate identity string.
- `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD`: Developer ID certificate material.
- `APPLE_TEAM_ID`: Apple Developer team identifier.
- `NOTARY_PRIVATE_KEY`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`: notarization API credentials.
- `SPARKLE_PRIVATE_KEY`: the base64 Ed25519 seed exported from Sparkle `generate_keys`.

The workflow creates a temporary keychain and credential directory, never enables shell tracing, and deletes them in its final step. GitHub-hosted runners are ephemeral. The workflow job names the `release` environment and also rejects every ref except `refs/heads/main`; configure the environment's deployment-branch rule to allow only protected `main`, and limit approval to the responsible roles above.

## Build and notarize

1. Make sure `main` is clean, all tests pass, and `appcast.xml` contains the currently published channel.
2. Choose a SemVer marketing version and an integer build number greater than every `sparkle:version` already in the appcast.
3. Run the manual **Secure Thoughtbox release** workflow from `main`. It resolves the pinned dependencies; runs unit tests and the complete real-app journey suite; verifies localization-catalog completeness plus the privacy, logging, motion, color, copy, and dependency boundaries; archives with the release identity; verifies the entitlement allowlist and nested signatures; submits to notarytool; staples and assesses the app; creates the update ZIP; generates EdDSA metadata; signs the appcast; and retains the evidence for review. Before retaining artifacts, it builds a lower signed fixture, serves the candidate over a temporary trusted local HTTPS channel, and runs the real Sparkle install/relaunch XCUITest.
4. Download the retained archive, appcast, `source-commit.txt`, and `notary.json`. Confirm the latter says `Accepted` and record its submission ID in the release issue. `source-commit.txt` binds the artifacts to the exact reviewed workflow commit.
5. Confirm `docs/releases/VERSION.md` contains the reviewed user-facing notes, then create the draft GitHub release with `Scripts/release/publish.sh VERSION UPDATE_ZIP APPCAST SOURCE_COMMIT_FILE`. The script verifies the notes and recorded commit locally and on GitHub, uses those exact notes, creates the tag at that exact commit even if `main` has advanced, and deliberately stops at a draft.
6. Publish the approved draft, confirm its archive URL works without authentication, then commit the already verified generated appcast to `main`. A feed must never advertise an unavailable archive.

Capture Selection additionally requires every row in the [release qualification matrix](releases/MEM-189-selection-capture-verification.md). The signed helper and app are one notarized Sparkle payload: never replace, re-sign, or roll back the helper independently of its containing app.

Local invocation uses the same `Scripts/release/build-and-notarize.sh` gates. Supply credential file paths and release values through environment variables; do not pass secrets as command-line values.

## Clean install and update acceptance

Before publishing any update after the first beta, use a clean macOS user or ephemeral CI runner:

1. Verify the previous ZIP and candidate appcast are served over HTTPS from the intended staging locations.
2. Run `Scripts/release/verify-staged-update.sh PREVIOUS_ZIP STAGED_APPCAST EXPECTED_VERSION` on that clean Mac with Developer Mode enabled for XCUITest.
3. The acceptance test installs the previous app in Applications, creates an Inbox Thought, a Project Thought, a trashed Thought, a Draft with a Project destination, and non-default Settings; invokes the native Check for Updates command by accessibility; installs and relaunches; then verifies the version and every data category.
4. Manually repeat from a quarantined browser download. Confirm Gatekeeper opens the app without override, the updater and its failures are keyboard operable, and VoiceOver announces the native Sparkle status/error text.

The unit-level `UpdatePreservationTests` runs on every release build as an earlier compatibility gate. It reopens the same on-disk SwiftData store and defaults suite and checks Draft, Projects, Inbox and Project Thoughts, Trash restoration metadata, and Settings. It supplements rather than replaces the clean-Mac Sparkle exercise.

## Rollback

If a release has not been advertised, delete the draft and keep the current appcast. If it has been advertised, immediately restore the last known-good signed appcast, remove the bad archive from the download surface, and prepare a fixed build with a strictly higher build number. Preserve the rejected or withdrawn notary ID and checksums for incident review; never rewrite a previously approved archive in place.
