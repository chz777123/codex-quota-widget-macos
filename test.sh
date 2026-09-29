#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library Sources/Quota.swift Sources/DailyUsage.swift Tests/QuotaTests.swift -o build/QuotaTests
build/QuotaTests

xcrun swiftc -swift-version 5 -parse-as-library Sources/Quota.swift Sources/DailyUsage.swift Sources/CodexClient.swift Sources/CodexLocation.swift Tests/LocationTests.swift -o build/LocationTests
build/LocationTests

xcrun swiftc -swift-version 5 -parse-as-library Sources/Quota.swift Sources/DailyUsage.swift Sources/UsageReader.swift Tests/UsageTests.swift -o build/UsageTests
build/UsageTests

xcrun swiftc -swift-version 5 -parse-as-library Sources/Quota.swift Sources/DailyUsage.swift Sources/UsageReader.swift Sources/CodexClient.swift Sources/CodexLocation.swift Sources/LocalQuotaServer.swift Sources/QuotaModel.swift Tests/ModelTests.swift -o build/ModelTests
build/ModelTests
