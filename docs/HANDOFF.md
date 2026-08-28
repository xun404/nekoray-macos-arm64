# NekoBox macOS Handoff

## Current State

Active development continues on `main`. The GitHub default branch is intentionally `rm`, which contains only a removal notice. This keeps the repository landing page minimal; it does not make the `main` branch private or inaccessible.

Do not change the default branch, repository visibility, GitHub feature settings, or the contents of `rm` without explicit authorization.

The root README on `main` intentionally states only that NekoBox is a complete native macOS rewrite built with SwiftUI. It is a public-facing statement, not a feature-parity checklist.

## Architecture

| Layer | Location | Current role |
| --- | --- | --- |
| Native macOS app | `macOS/NekoBox` | SwiftUI application shell, native navigation, settings, profile list, and read-only legacy profile import |
| Existing desktop app | `ui`, `main`, `db`, `fmt`, `rpc` | Functional Qt/C++ implementation and behavior reference during migration |
| Local core | `go/cmd/nekobox_core`, `go/grpc_server` | Proxy engine integration and local gRPC interface |
| Legacy configuration | `db/Database.*`, `db/ConfigBuilder.*` | Existing profile/group data formats and runtime configuration generation |

The SwiftUI app targets Apple Silicon macOS 13 or later. Its `CoreService` boundary is deliberately a placeholder: connection, latency testing, traffic, connections, system proxy, VPN, and core lifecycle controls are not implemented merely because the interface displays them.

## Legacy Data Compatibility

The native app currently reads legacy profile and group JSON without writing to it. The default legacy directory is:

```
~/Library/Preferences/nekoray/config
```

Set `NEKOBOX_LEGACY_CONFIG` to use a different directory during development.

Do not enable writes to this directory until the full schema, validation, backups, rollback behavior, and a migration path are implemented. Preserve the Qt application and its data formats as the compatibility reference until native feature parity is explicitly established.

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

The bundle is written under `macOS/NekoBox/.build` and must not be committed.

Build the Qt implementation when changing shared or legacy code:

```sh
cmake -S . -B build -GNinja -DQT_VERSION_MAJOR=6 -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build
```

The Qt build requires the project dependencies documented in the existing macOS build documentation.

## Suggested Migration Order

1. Complete native Swift models, persistence, validation, and safe import/export.
2. Port configuration generation from `db/ConfigBuilder.*` with coverage for every supported proxy format.
3. Generate and integrate Swift gRPC types from `go/grpc_server/gen/libcore.proto`, then implement real core lifecycle and status updates.
4. Migrate connection testing, logs, traffic, connection inspection, routing, subscriptions, and groups.
5. Add system proxy, VPN/network-extension, launch-at-login, updater, and secure credential handling.
6. Verify behavior against the Qt application before retiring any legacy capability.

## Repository and Branch Safety

- `origin` is the upstream repository remote.
- `macos` is the personal GitHub remote.
- `main` is the active development branch.
- `rm` is the intentionally minimal GitHub default branch. Never merge normal development work into it.
- Do not commit generated bundles, `.build`, temporary build directories, or `.zcode`.
- Run `git diff --check` before committing. Select build and test commands based on the files changed.
