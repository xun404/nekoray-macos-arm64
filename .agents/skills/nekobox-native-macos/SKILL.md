---
name: nekobox-native-macos
description: Use when changing the SwiftUI or AppKit macOS app, or when integrating native app behavior with the NekoBox local core. Preserve legacy data compatibility while the native implementation gains feature coverage.
---

# NekoBox Native macOS Migration

Read `docs/HANDOFF.md` and the relevant implementation before changing a migration boundary.

## Source Map

| Concern | Primary location |
| --- | --- |
| Native SwiftUI app | `macOS/NekoBox` |
| Local proxy core | `go/cmd/nekobox_core`, `go/grpc_server` |
| Core API contract | `go/grpc_server/gen/libcore.proto` |
| Legacy profile data | `~/Library/Preferences/nekoray/config` |

## Migration Rules

- Treat persisted legacy profile data as a compatibility input until native persistence is complete.
- Keep legacy profile and group import read-only. Do not write legacy JSON until a validated migration workflow includes backups and rollback.
- Do not present controls as functional when their underlying core, configuration, or system-service behavior has not been implemented.
- Implement configuration generation and gRPC behavior end to end before enabling actions that depend on them.
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

For Go core or gRPC contract changes, run focused Go checks for the changed package. Probe the active toolchain before adding test targets; do not assume a full Xcode installation or a particular test framework is present.

Before committing, run `git diff --check` and keep generated output, `.build`, and `.zcode` out of version control.
