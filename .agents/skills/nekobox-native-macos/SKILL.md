---
name: nekobox-native-macos
description: Use when changing the SwiftUI or AppKit macOS app, or when migrating Qt UI and local-core behavior into the native NekoBox implementation. Preserve legacy data compatibility and use the Qt application as the behavior reference until feature parity is explicit.
---

# NekoBox Native macOS Migration

Read `docs/HANDOFF.md` and the relevant implementation before changing a migration boundary.

## Source Map

| Concern | Primary location |
| --- | --- |
| Native SwiftUI app | `macOS/NekoBox` |
| Current desktop behavior | `ui`, `main`, `db`, `fmt`, `rpc` |
| Local proxy core | `go/cmd/nekobox_core`, `go/grpc_server` |
| Core API contract | `go/grpc_server/gen/libcore.proto` |
| Existing runtime configuration | `db/ConfigBuilder.*` |

## Migration Rules

- Treat the Qt application as the behavior and data-format reference until native parity is proven.
- Keep legacy profile and group import read-only. Do not write legacy JSON until a validated migration workflow includes backups and rollback.
- Do not present controls as functional when their underlying core, configuration, or system-service behavior has not been implemented.
- Migrate configuration generation and gRPC behavior end to end before enabling actions that depend on them.
- Preserve macOS 13+ and Apple Silicon compatibility unless a change is explicitly approved.
- Keep new documentation, comments, UI copy, and skill content in English.

## Validation

For SwiftUI changes, build the package:

```sh
cd macOS/NekoBox
swift build
```

For app-bundle or packaging changes, also run:

```sh
cd macOS/NekoBox
./Support/build-app.sh
```

For changes that touch shared C++, Qt behavior, or build configuration, build the corresponding Qt target when its dependencies are available. Probe the active toolchain before adding test targets; do not assume a full Xcode installation or a particular test framework is present.

Before committing, run `git diff --check` and keep generated output, `.build`, and `.zcode` out of version control.
