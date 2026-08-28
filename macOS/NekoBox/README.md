# NekoBox Native for macOS

This directory contains the sole macOS application target. NekoBox is built
with SwiftUI and AppKit for Apple Silicon Macs running macOS 13 or later.

## Current vertical slice

- Native macOS 13+ SwiftUI application using `NavigationSplitView`, `Table`,
  app-menu commands, and a dedicated Settings scene.
- Read-only import of legacy profile/group JSON at
  `~/Library/Preferences/nekoray/config`. Set `NEKOBOX_LEGACY_CONFIG` to test
  against another configuration directory.
- Native profile and group creation, editing, deletion, selection, filtering,
  endpoint copy, and activity logs. Native data is stored separately at
  `~/Library/Application Support/NekoBox/profiles.json`.
- Native Xray and sing-box Core support. The redesigned Core settings page
  persists the selected engine and shows each Core's availability, path, and
  downloaded version. It can download or update the official Apple Silicon
  release from GitHub, verify its published SHA-256 digest, and install it in
  `~/Library/Application Support/NekoBox/cores`. Manually selected, bundled,
  and common-path executables remain supported. Before launch, NekoBox
  generates and validates an engine-specific configuration with SOCKS5 and HTTP
  listeners on `127.0.0.1:10808` and `127.0.0.1:10809`. Imported VLESS and
  VMess profiles retain their transport fields, and native VLESS, VMess, Trojan,
  and Shadowsocks profiles can be configured for either supported Core.

## Build

```shell
cd macOS/NekoBox
swift build
./Support/build-app.sh
```

The app bundle is ad-hoc signed at `.build/NekoBox.app` by default.

To bundle a Core for a distribution build, place an executable Apple Silicon
`xray` or `sing-box` binary at `macOS/NekoBox/Resources/xray` or
`macOS/NekoBox/Resources/sing-box` before running the build script. The helper
downloads the official releases and verifies their SHA-256 digests:

```shell
zsh Support/download-cores.sh
./Support/build-app.sh
```

The downloaded resource files are ignored by Git. Without a bundled binary,
users can download or select the matching executable in Settings.

## GitHub Actions release package

`.github/workflows/build-macos.yml` runs only when a version tag matching `v*`
is pushed to an Apple Silicon macOS runner. It downloads and verifies both
official Core files, builds and ad-hoc signs the application, then publishes a
`NekoBox-macos-arm64.zip` archive in the GitHub Release.

## Remaining native work

1. Complete profile parsing, links, subscriptions, routing, and full Xray and
   sing-box configuration coverage in Swift.
2. Implement traffic and connection reporting through the Xray and sing-box
   APIs.
3. Add native system-proxy, VPN/network-extension, Launch at Login, import/export,
   updater, and keychain integrations.
4. Add a one-time backup and migration workflow before modifying legacy data.
