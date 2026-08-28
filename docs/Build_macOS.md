# 在 macOS (Apple Silicon) 下编译 Nekoray

本仓库只支持 macOS arm64，Windows / Linux 相关代码已移除。

## 环境要求

- macOS 13+ (Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`)
- Homebrew 依赖（均为当前最新版本）：

```shell
brew install ninja qt protobuf yaml-cpp zxing-cpp
```

- Go 1.23+

> 说明：GUI 与核心之间使用内置的 Qt HTTP/2 gRPC 通道通信，C++ 侧只需要 protobuf，不需要 grpc 库。

## 获取源码

```shell
git clone https://github.com/MatsuriDayo/nekoray.git --recursive
```

Go 部分需要将三个 fork 仓库克隆到 nekoray 同级目录（见 `libs/get_source.sh`）：

```shell
cd ..
git clone --depth 1 -b 1.9.7 https://github.com/MatsuriDayo/sing-box.git
git clone --depth 1 https://github.com/MatsuriDayo/libneko.git
git clone --depth 1 -b dev https://github.com/MatsuriDayo/sing-quic.git
```

## 编译 Go 核心

```shell
libs/build_go.sh
```

产物位于 `deployment/macos-arm64/nekobox_core`。

> 新版 Go 链接器默认拒绝 linkname，构建脚本已带 `-checklinkname=0`。

## 编译 GUI

```shell
mkdir build
cd build
cmake -GNinja -DQT_VERSION_MAJOR=6 -DCMAKE_PREFIX_PATH="$(brew --prefix qt)" ..
ninja
```

产物为 `build/nekobox.app`。

## 组装 App

```shell
cd ..
libs/deploy_macos_arm64.sh
```

脚本会：拷贝 `nekobox.app` → `macdeployqt` 注入 Qt 运行时 → 放入 `nekobox_core` → ad-hoc 签名。
最终产物：`deployment/macos-arm64/NekoBox.app`。

## 数据目录行为

- `.app` 放在可写目录（如下载文件夹）时保持便携模式，数据存放在 bundle 旁；
- `.app` 放入 `/Applications` 等只读位置时，自动切换到用户配置目录（`~/Library/Preferences/nekoray`）；
- 也可以用 `-appdata` 参数强制指定。

## Tun (VPN) 模式

VPN 模式通过 `osascript` 提权（会弹出管理员密码框），核心以 root 运行 utun 并自行管理路由。

## 升级 sing-box 的限制

`COMMIT_SING_BOX` 固定在 fork 的 `1.9.7` 分支头：这是仍保留 `boxapi` / `boxmain.Create` 接口的最新版本。
`def` / `1.11.x` / `1.12.x` 分支移除了该接口，升级需要重写 `go/cmd/nekobox_core` 的 wrapper 并适配新版配置 schema。
