#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
xcrun swiftc -swift-version 5 -parse-as-library Sources/Probe.swift Tests/ClassifierTests.swift -o build/classifier-tests
build/classifier-tests
