# Contributing

Keep target detection conservative: if an app's semantics are unknown, preserve its native middle click. Avoid Accessibility IPC in the event-tap callback.

## Source map

- `Core.swift`: gesture ownership, click replay decisions, target rules, and scroll-speed curve.
- `AccessibilityTarget.swift`: asynchronous hit testing and ancestor inspection, with a bounded timeout.
- `EventController.swift`: event tap, buffering, timer, cancellation, and direct scroll delivery.
- `ScrollEventFactory.swift`: retain the original click's AppKit window information while generating pixel scrolling. Posting anchor-position events globally can trap the physical cursor; preserve direct process delivery.
- `AnchorPanel.swift`: non-activating, click-through origin marker.
- `main.swift`: AppKit menu, settings, diagnostics, and permission lifecycle.

## Check a change

Run `./scripts/test.sh` and `./scripts/build.sh` on macOS. The source-configuration checks need a WindowServer session; if unavailable they are reported as skipped. Run the [physical mouse checks](docs/testing.md) after changing input handling. Test with your usual mouse remapper enabled.

Keep logs free of page text, field contents, and keystrokes. A useful bug report includes the app/version, macOS version, mouse/remapper, reproduction steps, and the last decision from Diagnostics.

## Publish a release

The app icon is generated from vector drawing code in `scripts/generate-icon.swift`. Run `./scripts/generate-icon.sh` after changing the artwork; commit both generated files in `Resources/`. Normal app builds use the committed icon and do not require regenerating it.

1. Update `VERSION` and `CHANGELOG.md`.
2. Run the automated and manual checks.
3. Run `./scripts/package.sh` and verify the bundle with `codesign --verify --strict`.
4. Commit, push, and wait for CI.
5. Tag the tested commit as `v<version>` and create a GitHub release with the ZIP and `SHA256SUMS.txt` from `dist/`.

Builds are currently ad-hoc signed. Developer ID signing and notarization are not configured. A rebuilt binary may need its Accessibility grant renewed. Do not weaken system security or alter the TCC database to avoid that step.
