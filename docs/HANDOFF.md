# NekoBox macOS Handoff

## Current State

Active development continues on `main`. The GitHub default branch is intentionally `rm`, which contains only a removal notice. This keeps the repository landing page minimal; it does not make the `main` branch private or inaccessible.

Do not change the default branch, repository visibility, GitHub feature settings, or the contents of `rm` without explicit authorization.

The root README on `main` intentionally states only that NekoBox is a complete native macOS rewrite built with SwiftUI. It is a public-facing statement, not a feature-parity checklist.

## Architecture

| Layer | Location | Current role |
| --- | --- | --- |
| Native macOS app | `macOS/NekoBox` | SwiftUI application, native profile/group management, selectable Core lifecycle, activity logs, and read-only legacy profile import |
| Xray Core | Official GitHub download, user-selected, bundled, or common-path `xray` executable | Generated local SOCKS5/HTTP configuration for supported outbound profiles |
| sing-box Core | Official GitHub download, user-selected, bundled, or common-path `sing-box` executable | Generated local SOCKS5/HTTP configuration for supported outbound profiles |
| Legacy local core | `go/cmd/nekobox_core`, `go/grpc_server` | Existing sing-box proxy engine integration and local gRPC interface; not used by the SwiftUI app |
| Legacy configuration | `~/Library/Preferences/nekoray/config` | Read-only compatibility input for profile and group JSON |
| Native configuration | `~/Library/Application Support/NekoBox/profiles.json` | Writable native profile, group, and selection state |

The SwiftUI app targets Apple Silicon macOS 13 or later. Its selected `CoreService` locates an executable, writes and validates an engine-specific local configuration, and starts or stops the process. The Core settings page persists a choice of Xray or sing-box, prevents switching while either process is running, and downloads the compatible official GitHub release on demand. The app verifies the SHA-256 digest published in the GitHub Release API before installing downloads at `~/Library/Application Support/NekoBox/cores`. Both engines support VLESS, VMess, Trojan, and Shadowsocks outbounds. Xray supports TCP, WebSocket, gRPC, XHTTP, and HTTPUpgrade transport settings; sing-box supports TCP, WebSocket, gRPC, and HTTPUpgrade, while rejecting XHTTP rather than emitting an invalid configuration. The app does not configure the system proxy, VPN, traffic reporting, or active-connection inspection.

## Legacy Data Compatibility

The native app currently reads legacy profile and group JSON without writing to it. New or editable copies are stored separately in Application Support. The default legacy directory is:

```
~/Library/Preferences/nekoray/config
```

Set `NEKOBOX_LEGACY_CONFIG` to use a different directory during development.

Do not enable writes to this directory until the full schema, validation, backups, rollback behavior, and a migration path are implemented.

## Build and Packaging

Build the SwiftUI package:

```sh
cd macOS/NekoBox
swift build
```

Build an ad-hoc signed app bundle:

```sh
cd macOS/NekoBox
./Support/build-app.sh
```

To prepare a bundle containing both official Apple Silicon cores:

```sh
cd macOS/NekoBox
zsh Support/download-cores.sh
./Support/build-app.sh
```

The helper and `.github/workflows/build-macos.yml` select the official Xray and
sing-box GitHub Release assets, verify their published SHA-256 digests, and
place them in `Resources` before the app bundle is signed. The downloaded Core
files must remain untracked.

The bundle is written under `macOS/NekoBox/.build` and must not be committed.

## Suggested Migration Order

1. Add safe native import/export and complete support for all proxy configuration fields.
2. Add Xray and sing-box API integration for latency testing, traffic, and connection inspection.
4. Migrate routing and subscriptions.
5. Add system proxy, VPN/network-extension, launch-at-login, updater, and secure credential handling.

## Repository and Branch Safety

- `origin` is the upstream repository remote.
- `macos` is the personal GitHub remote.
- `main` is the active development branch.
- `rm` is the intentionally minimal GitHub default branch. Never merge normal development work into it.
- Do not commit generated bundles, `.build`, temporary build directories, or `.zcode`.
- Run `git diff --check` before committing. Select build and test commands based on the files changed.
