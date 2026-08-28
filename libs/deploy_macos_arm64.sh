#!/bin/bash
set -e

source libs/env_deploy.sh
DEST=$DEPLOYMENT/macos-arm64
APP=$DEST/NekoBox.app
rm -rf $APP
mkdir -p $DEST

#### copy app bundle (built by cmake: build/nekobox.app) ####
cp -R $BUILD/nekobox.app $APP

#### strip runtime files if the app was run inside the build tree ####
rm -rf $APP/Contents/MacOS/config $APP/Contents/MacOS/temp \
       $APP/Contents/MacOS/neko.log $APP/Contents/MacOS/*.json $APP/Contents/MacOS/vpn-run-root.sh

#### deploy qt runtime into bundle ####
macdeployqt $APP -verbose=1

#### copy core ####
cp $DEST/nekobox_core $APP/Contents/MacOS/

#### ad-hoc sign so the bundle launches locally ####
codesign --force --deep --sign - $APP

echo "Deployed: $APP"
