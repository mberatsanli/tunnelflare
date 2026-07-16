# Releasing Tunnelflare

This document describes how versioning works, how to cut a release, and the
one-time setup required for Sparkle in-app updates.

## Versioning

Tunnelflare uses [Semantic Versioning](https://semver.org) (`MAJOR.MINOR.PATCH`).

The single source of truth for the version is
[`Config/Base.xcconfig`](../Config/Base.xcconfig):

```
MARKETING_VERSION = 1.0.0      // CFBundleShortVersionString (the SemVer version)
CURRENT_PROJECT_VERSION = 1    // CFBundleVersion (the build number)
```

The Xcode project inherits both settings from the xcconfig — do not hardcode
them in `project.pbxproj`. Bumping the version is a one-line diff.

`AppInfo.version` / `AppInfo.buildNumber` read these values from the bundle at
runtime (`CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist`),
so the UI always reflects the build settings.

## Cutting a release

1. Bump `MARKETING_VERSION` in `Config/Base.xcconfig` and commit.
2. Tag the commit with a matching `v` prefix and push:

   ```sh
   git tag v1.2.3
   git push origin v1.2.3
   ```

3. The [release workflow](../.github/workflows/release.yml) then:
   - validates the tag is strict SemVer (`vX.Y.Z`) — anything else fails,
   - stamps the tag version into `Config/Base.xcconfig`
     (`CURRENT_PROJECT_VERSION` is derived from the SemVer components as
     `MAJOR*1000000 + MINOR*1000 + PATCH`, so build numbers stay monotonic
     with the version and reproducible across workflow re-runs),
   - builds and archives the app,
   - **fails if the built app's version does not match the tag**,
   - signs the zip with the Sparkle EdDSA key and generates `appcast.xml`,
   - publishes a GitHub Release with the zip and `appcast.xml` attached.

The app's update feed (`SUFeedURL` in `Info.plist`) points at
`https://github.com/mberatsanli/tunnelflare/releases/latest/download/appcast.xml`,
so each release automatically becomes the live appcast.

> **Note:** the Sparkle framework version is pinned exactly in the Xcode
> project (`XCRemoteSwiftPackageReference` in `project.pbxproj`) and must be
> kept in sync with `SPARKLE_VERSION` in the release workflow, which
> downloads the matching `generate_appcast` tool.

## Sparkle update signing — one-time setup

Sparkle updates are signed with an EdDSA (ed25519) key pair. The public key
ships in the app; the private key lives **only** in a GitHub Actions secret.

> **NEVER commit the private key to the repository.**

### 1. Generate the key pair

Download the [Sparkle distribution](https://github.com/sparkle-project/Sparkle/releases)
and run:

```sh
./bin/generate_keys
```

This stores the private key in your macOS Keychain and prints the public key.
To export the private key for CI:

```sh
./bin/generate_keys -x sparkle_private_key
```

### 2. Put the public key in Info.plist

Replace the `SUPublicEDKey` placeholder value
(`REPLACE_WITH_SPARKLE_ED25519_PUBLIC_KEY`) in
[`Tunnelflare/Info.plist`](../Tunnelflare/Info.plist) with the printed public
key, and commit that change.

### 3. Add the private key as a CI secret

```sh
gh secret set SPARKLE_PRIVATE_KEY < sparkle_private_key
rm sparkle_private_key
```

(Or via GitHub → Settings → Secrets and variables → Actions →
`SPARKLE_PRIVATE_KEY`.)

If the secret is missing, the workflow still publishes the release but skips
the appcast with a warning — installed apps will not be offered that update.

## Code signing requirement

Sparkle validates that an update is signed by the **same code-signing
identity** as the installed app (in addition to the EdDSA signature). The
release workflow currently produces an **ad-hoc signed** build, which is fine
for manual downloads but not a stable identity for production updates:

- For production releases, sign the app with a **Developer ID Application**
  certificate (and notarize it) so every release shares a stable identity.
- Until then, Sparkle relies on the EdDSA signature only; ad-hoc → ad-hoc
  updates may require the user to re-approve the app in Gatekeeper.

## Update UX

- **Check for Updates…** is available in the app menu, the menu bar dropdown
  footer, and Settings → General.
- Automatic background checks are on by default (`SUEnableAutomaticChecks`)
  and can be disabled with the "Automatically Check for Updates" toggle in
  Settings; Sparkle persists the choice in `UserDefaults`.
- Tunnelflare is a menu bar app (`LSUIElement`), so `UpdaterService` activates
  the app before presenting Sparkle's update window. The app is not
  sandboxed, so `SUEnableInstallerLauncherService` is not required.
