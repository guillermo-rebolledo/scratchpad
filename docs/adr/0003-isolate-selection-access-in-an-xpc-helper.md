# Isolate selected-text access in an authenticated XPC helper

Thoughtbox keeps its main application in the App Sandbox. macOS does not allow a sandboxed application to inspect another application's Accessibility hierarchy, so Capture Selection runs in a minimal, embedded XPC service that is launched on demand and is not sandboxed.

The helper has one responsibility: after an explicit shortcut invocation, read `AXFocusedUIElement` and its `AXSelectedText` value. It rejects missing Accessibility trust, secure text fields, empty selections, and unavailable values. It has no network entitlement, persistence, telemetry, clipboard access, screen recording, or general automation API. Selection text exists only in memory long enough to return a single XPC response and is never logged.

The XPC boundary is mutually authenticated with code-signing requirements. The app accepts only the helper bundle identifier signed by its own team, and the helper accepts only the Thoughtbox app identifier signed by that team. Ad-hoc development builds retain identifier checks. The client applies a one-second timeout and treats interruption, invalidation, malformed replies, and authentication failures as generic capture failures without modifying the Draft.

Release verification requires the app to remain sandboxed, the helper to remain unsandboxed and free of unrelated entitlements, both bundles to have the same Developer ID authority and hardened runtime, and the complete app—including the helper—to pass strict signing, notarization, Gatekeeper, and Sparkle update checks. See [`docs/release.md`](../release.md) and the [Capture Selection qualification matrix](../releases/MEM-189-selection-capture-verification.md).
