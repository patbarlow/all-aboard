# All Aboard — Agent Operating Guide

This file defines the default workflow for agents making changes in this repo.

## Branch strategy
- `main` = stable production release lane.
- `work` (or active feature branch) = integration lane for frequent task delivery.
- Optional short-lived branches per task can merge into `work` first, then into `main` once approved.

## Release channels
All Aboard supports two Sparkle update channels:

1. **Stable channel**
   - Feed file: `appcast.xml`
   - Feed URL: `https://raw.githubusercontent.com/patbarlow/all-aboard/main/appcast.xml`
   - Intended for production users.

2. **Beta channel**
   - Feed file: `appcast-beta.xml`
   - Feed URL: `https://raw.githubusercontent.com/patbarlow/all-aboard/main/appcast-beta.xml`
   - Intended for internal/testing users.

In-app channel selection is controlled by settings in `TripCreationView` and runtime feed delegation in `AllAboardApp`.

## Feature flag policy
- New or risky functionality should be behind a flag by default.
- Current user-defaults keys:
  - `release-channel` (`stable` or `beta`)
  - `enable-beta-features` (`true` / `false`)
- Do not remove existing flags without explicit request.
- For incomplete work, merge code with flag OFF by default.

## Build and publish workflow
### Stable release
From the repo root with a clean working tree on `main`:
```
./scripts/release.sh 1.5.0
```
This bumps the version in `project.pbxproj`, builds + signs + notarizes the DMG,
generates `appcast.xml` with an EdDSA signature, commits, tags, pushes, and creates
the GitHub release with the DMG attached. ~3 minutes end to end.

### Beta release
1. Merge desired features to the beta/integration branch.
2. Run:
   - `./scripts/publish-update.sh --channel beta`
3. Commit updated `appcast-beta.xml`.
4. Upload the DMG as `All Aboard Beta.dmg` to GitHub release tag `beta`.

### One-time machine setup (stable releases)
- Developer ID Application cert for `Pat Barlow (T544U3WVL6)` in Keychain
- Notarytool credentials: `xcrun notarytool store-credentials "allaboard-notary" --apple-id ... --team-id T544U3WVL6 --password <app-specific-password>`
- Sparkle EdDSA private key in Keychain (matches `SUPublicEDKey` in Info.plist)
- `gh` CLI authenticated

## Task delivery process (Linear → Codex)
1. Implement task on integration branch.
2. If behavior is not production-ready, gate behind feature flag.
3. Ship to **beta channel** for user testing.
4. Promote only approved features to `main` and stable channel.

## Safety checks before merging to stable
- Stable channel feed remains functional.
- Beta-only functionality is disabled by default for stable users.
- App launches with existing license state.
- Manual "Check for Updates…" path still works.

## Notes
- Keep this document updated when release workflow, channel URLs, script behavior, or flag keys change.
