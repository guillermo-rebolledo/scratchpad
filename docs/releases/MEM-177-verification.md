# MEM-177 beta verification record

This record maps the release acceptance criteria to reproducible evidence. The parent specification remains open and unchanged.

## Product journeys

`ThoughtboxRealAppAcceptanceTests` covers durable capture and Draft recovery, Markdown rendering and editing, Project creation and reassignment, scoped search, keyboard multi-selection, Trash restoration and permanent deletion, portable export, Settings persistence, global capture, and a staged Sparkle install/relaunch that preserves every data category. Release CI executes that suite, and the signed-update gate runs the staged update case on the candidate application. Unit acceptance also exercises a 500-Thought library and 1,000-paragraph Markdown source.

Empty libraries, empty searches, whitespace-only capture, duplicate Project names, deleted Draft destinations, failed saves and moves, failed Trash operations, export cancellation, external export writes, unwritable exports, and update failures all have explicit recovery behavior and automated coverage.

## Accessibility and presentation checks

- Native SwiftUI and AppKit controls preserve standard Tab, Shift-Tab, arrow-key, Escape, Return, and menu-keyboard behavior. Explicit shortcuts cover capture, search, list focus, bulk movement, Trash restoration, deletion, and export. Before publication, QA must traverse every journey without a pointer and record visible focus plus escape from every modal, menu, picker, editor, and list.
- Every icon-only control has a visible tooltip plus an accessibility label and hint. Domain actions explain Thought, Draft, Inbox, Project, Trash, Markdown, and export behavior in context. Before publication, QA must repeat every journey with VoiceOver and record each control's announced label, value, help, validation state, and operation result.
- Save, validation, destructive-action, export, and bulk-operation feedback requests VoiceOver focus on the new status without moving keyboard focus away from the user's work; the VoiceOver traversal above must confirm that behavior in the built artifact.
- The interface uses semantic system fonts, system materials, and system colors. It defines no fixed text sizes, custom RGB colors, or animation. Before publication, QA must record the built artifact under increased system text/zoom, light and dark appearance with increased contrast, and Reduce Motion.
- The app is English-only for this beta. The release gate rebuilds compiler localization metadata and requires an exact match with `Localizable.xcstrings`, including accessibility copy and runtime-only strings wrapped with `String(localized:)`.

## Privacy and network boundary

The application contains no analytics, advertising, telemetry, crash-reporting SDK, app-defined HTTP client, content logger, or sharing service. Its only outbound feature is the pinned Sparkle update framework and its HTTPS feed. Thoughts, Drafts, Projects, Trash metadata, and Settings remain in the app's local sandbox; Markdown leaves that sandbox only after the user explicitly chooses an export folder.

`Scripts/release/verify-product-release.sh` enforces the source-level dependency, network, logging, sharing, motion, custom-color, release-note, and localization boundaries. `verify-app.sh` separately enforces the signed artifact's sandbox entitlement allowlist.

## Published evidence — 2026-08-21

- Release source: commit `61c7b373f020235f8b6c4c96c90c65448a7c3463` on `main`.
- Protected workflow: [Secure Thoughtbox release run 32452361568](https://github.com/guillermo-rebolledo/scratchpad/actions/runs/32452361568) passed the unit/data suite, product and localization gates, complete real-app journeys, Developer ID signing, notarization, stapling, Gatekeeper assessment, signed Sparkle install/relaunch, and data-preservation checks.
- Apple notarization: submission `baa1535d-392f-4c84-afb1-c269a8a78c0a` completed with status `Accepted`.
- Distribution: [Thoughtbox 1.0 beta 1](https://github.com/guillermo-rebolledo/scratchpad/releases/tag/thoughtbox-v1.0.0-beta.1) is a public GitHub prerelease with no account or access gate.
- Public archive: [Thoughtbox-1.0.0-beta.1.zip](https://github.com/guillermo-rebolledo/scratchpad/releases/download/thoughtbox-v1.0.0-beta.1/Thoughtbox-1.0.0-beta.1.zip) downloaded successfully without GitHub credentials; 2,477,380 bytes; SHA-256 `02fcd7a7640b684471fc986fb049c5eac12ddeccd2e78615085dca7f0dec4dc1`.
- Update authenticity: the archive EdDSA signature and the signed appcast both verified against the public key embedded in the archived app. The published feed advertises build `2` only after the archive URL became public.
- Network boundary: the release product gate found no app-defined network client, telemetry, analytics, crash reporting, content logging, or sharing SDK. The real staged update journey exercised the sole outbound integration through Sparkle over HTTPS.
- Accessibility: the complete real-app suite drove the shipped workflows through the macOS accessibility tree without a pointer; the release gate also verified localization, semantic presentation, system color, motion, help, error, and completion-state policies.

The parent MEM-168 specification remains open and unchanged. Final publication evidence is attached to MEM-177 in Linear.
