# NekoBox Native for macOS

This directory is the new SwiftUI/AppKit application target. It is deliberately
independent from the existing Qt target so the native migration can progress
without changing users' working Qt build or its data files.

## Current vertical slice

- Native macOS 13+ SwiftUI application using `NavigationSplitView`, `Table`,
  app-menu commands, and a dedicated Settings scene.
- Read-only import of the existing Qt profile/group JSON at
  `~/Library/Preferences/nekoray/config`. Set `NEKOBOX_LEGACY_CONFIG` to test
  against another configuration directory.
- An explicit `CoreService` boundary for the existing local `nekobox_core`
  gRPC process. It intentionally reports as unavailable until its generated
  Swift gRPC client and the C++ configuration builder replacement are added.

## Build

```shell
cd macOS/NekoBox
swift build
./Support/build-app.sh
```

The app bundle is ad-hoc signed at `.build/NekoBox.app` by default.

## Remaining migration work

1. Port profile parsing, editing, links, subscriptions, routing, and sing-box
   configuration generation from `fmt/` and `db/ConfigBuilder.*` to Swift.
2. Generate Swift gRPC types from `go/grpc_server/gen/libcore.proto`; implement
   authenticated local-core launch, start/stop, tests, traffic, and connections.
3. Add native system-proxy, VPN/network-extension, Launch at Login, import/export,
   updater, and keychain integrations.
4. After feature parity, remove the Qt Widgets target and migrate the legacy data
   store in place with a one-time backup.
