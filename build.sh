#!/bin/sh
set -e
cd "$(dirname "$0")"
swiftc -O -swift-version 5 -I Modules/MachTaskSelf -I Modules/SMCParamStruct \
  Modules/MachTaskSelf/MachTaskSelf.c \
  Libraries/SMCComm.swift Libraries/SMCComm+MagSafe.swift main.swift -o magled
