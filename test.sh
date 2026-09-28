#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library Sources/Quota.swift Tests/QuotaTests.swift -o build/QuotaTests
build/QuotaTests

xcrun swiftc -swift-version 5 -parse-as-library Sources/Quota.swift Sources/CodexClient.swift Sources/CodexLocation.swift Tests/LocationTests.swift -o build/LocationTests
build/LocationTests
