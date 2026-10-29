#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p build
swiftc -O -swift-version 5 -I Modules/MachTaskSelf -I Modules/SMCParamStruct \
  Modules/MachTaskSelf/MachTaskSelf.c \
  Libraries/SMCComm.swift Libraries/SMCComm+MagSafe.swift Tool/main.swift -o build/magled

# GUI app bundle: build/MagLED.app
app=build/MagLED.app
rm -rf $app && mkdir -p $app/Contents/MacOS $app/Contents/Resources
swiftc -O -swift-version 5 -parse-as-library App/*.swift -o $app/Contents/MacOS/MagLED
cp App/Info.plist $app/Contents/Info.plist
cp App/Resources/default-chime.m4a build/magled $app/Contents/Resources/
codesign --force --sign - $app
