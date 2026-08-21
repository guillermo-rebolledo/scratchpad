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

## Distribution evidence to attach before completion

- Exact source commit and workflow run URL.
- Accepted Apple notarization submission ID.
- Stapled and Gatekeeper-approved application verification output.
- Signed update ZIP and appcast signature verification output.
- Successful clean install and staged Sparkle update run.
- Runtime network observation showing only the documented Sparkle feed and release-download hosts.
- Public, authentication-free download URL for the free unlisted beta.

MEM-177 must remain open until every item above is attached to the Linear issue and the download has been tested without a signed-in account.
