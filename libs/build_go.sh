#!/bin/bash
set -e

source libs/env_deploy.sh
GOOS=darwin
GOARCH=arm64
DEST=$DEPLOYMENT/macos-arm64
rm -rf $DEST
mkdir -p $DEST

export CGO_ENABLED=0 GOOS GOARCH

#### Go: nekobox_core ####
pushd go/cmd/nekobox_core
go build -v -o $DEST -trimpath -ldflags "-w -s -checklinkname=0 -X github.com/matsuridayo/libneko/neko_common.Version_neko=$version_standalone" -tags "with_clash_api,with_gvisor,with_quic,with_wireguard,with_utls,with_ech"
popd
