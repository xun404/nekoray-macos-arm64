# NekoBox for macOS

NekoBox is a macOS-focused proxy configuration manager built around
[sing-box](https://sing-box.sagernet.org/). This fork targets Apple Silicon
and is transitioning from a Qt Widgets desktop interface to a native SwiftUI
and AppKit application.

> The SwiftUI application is an active migration target. The existing Qt app
> remains available while profile editing, configuration generation, and local
> core control are moved to the native implementation.

## Platform support

- macOS 13 or later
- Apple Silicon (`arm64`)
- sing-box based core (`nekobox_core`)

Windows and Linux packaging have been removed from this fork.

## Native macOS application

The new application is in [`macOS/NekoBox`](macOS/NekoBox). It uses standard
macOS navigation, tables, commands, and a Settings scene, and can read the
legacy Qt profile and group JSON without modifying it.

```shell
cd macOS/NekoBox
swift build
./Support/build-app.sh
```

The build script produces an ad-hoc signed app at
`macOS/NekoBox/.build/NekoBox.app`.

The native target currently provides the UI shell and read-only legacy data
loading. The remaining feature migration is tracked in
[`macOS/NekoBox/README.md`](macOS/NekoBox/README.md).

## Building the current Qt application

The legacy Qt application can still be built during the transition.

### Requirements

- macOS 13 or later on Apple Silicon
- Xcode Command Line Tools
- Go 1.23 or later
- Homebrew dependencies:

```shell
brew install ninja qt protobuf yaml-cpp zxing-cpp
```

### Build the core

Fetch the companion Go repositories as described by `libs/get_source.sh`, then
run:

```shell
libs/build_go.sh
```

The core binary is written to `deployment/macos-arm64/nekobox_core`.

### Build and package the app

```shell
cmake -S . -B build -GNinja -DQT_VERSION_MAJOR=6 -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build
libs/deploy_macos_arm64.sh
```

The packaged app is written to `deployment/macos-arm64/NekoBox.app`.

## Development notes

- The local core service contract is defined in
  [`go/grpc_server/gen/libcore.proto`](go/grpc_server/gen/libcore.proto).
- Existing user data is stored under the application configuration directory
  in `groups/`, `profiles/`, and route JSON files.
- The native app treats those files as read-only until the Swift data and
  configuration layers reach feature parity.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

## Credits

NekoBox is based on the upstream work of
[MatsuriDayo/nekoray](https://github.com/MatsuriDayo/nekoray),
[sing-box](https://github.com/SagerNet/sing-box), and their contributors.
