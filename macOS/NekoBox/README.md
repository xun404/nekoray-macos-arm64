# NekoBox Native for macOS

This directory contains the sole macOS application target. NekoBox is built
with SwiftUI and AppKit for Apple Silicon Macs running macOS 13 or later.

## Current vertical slice

- Native macOS 13+ SwiftUI application using `NavigationSplitView`, `Table`,
  app-menu commands, and a dedicated Settings scene.
- Read-only import of legacy profile/group JSON at
  `~/Library/Preferences/nekoray/config`. Set `NEKOBOX_LEGACY_CONFIG` to test
  against another configuration directory.
- An explicit `CoreService` boundary for the existing local `nekobox_core`
  gRPC process. It intentionally reports as unavailable until generated Swift
  gRPC bindings and the native configuration generator are added.

## Build

```shell
cd macOS/NekoBox
swift build
./Support/build-app.sh
```

The app bundle is ad-hoc signed at `.build/NekoBox.app` by default.

## Remaining native work

1. Complete profile parsing, editing, links, subscriptions, routing, and
   sing-box configuration generation in Swift.
2. Generate Swift gRPC types from `go/grpc_server/gen/libcore.proto`; implement
   authenticated local-core launch, start/stop, tests, traffic, and connections.
3. Add native system-proxy, VPN/network-extension, Launch at Login, import/export,
   updater, and keychain integrations.
4. Add a one-time backup and migration workflow before modifying legacy data.
