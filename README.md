# Dynalist for macOS

A tiny native macOS wrapper for [dynalist.io](https://dynalist.io), built with
[tao](https://github.com/tauri-apps/tao) + [wry](https://github.com/tauri-apps/wry)
(Tauri's windowing/WebView core, without the Tauri toolchain). ~1.4 MB app.

## Install

Download the latest `Dynalist-x.y.z.dmg` from
[Releases](https://github.com/JiasenL/mac.dynalist/releases), open it, and drag
**Dynalist** into **Applications**.

> Release builds are ad-hoc signed (not notarized). On first launch, right-click
> the app → **Open**, or run `xattr -dr com.apple.quarantine /Applications/Dynalist.app`.

## Build locally

```sh
make deliver          # build, sign (Local Dev CLI), install to /Applications, open
make dev              # debug bundle in dist/
make run              # cargo run with devtools
make dmg UNIVERSAL=1  # dist/Dynalist-<version>.dmg (arm64 + x86_64)
```

Override the signing identity with `CODESIGN_IDENTITY="..."` (use `-` for ad-hoc).

## Release

```sh
# bump version in Cargo.toml, then
git tag v0.1.0 && git push origin v0.1.0
```

GitHub Actions ([release.yml](.github/workflows/release.yml)) builds a universal
DMG and attaches it to a GitHub Release.

### Optional: Developer ID signing + notarization

Add these repository secrets and the workflow will sign with your Developer ID and
notarize the DMG automatically (no Gatekeeper warning):

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE` | `base64 -i DeveloperID.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PWD` | password of the .p12 |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | 10-char team ID |
| `APPLE_APP_PASSWORD` | app-specific password from appleid.apple.com |

## Keyboard shortcuts

⌘R reload · ⌘⇧H home · ⌘[ / ⌘] back/forward · ⌘= / ⌘- / ⌘0 zoom · ⌃⌘F full screen
