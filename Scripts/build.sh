#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
build_dir="${RACECARD_BUILD_DIR:-$project_dir/build}"
mkdir -p "$build_dir"
xcodebuild -project RaceCard.xcodeproj -scheme RaceCard -configuration Debug \
 -destination 'platform=macOS,arch=arm64' \
 -derivedDataPath "$build_dir/DerivedData" \
 -clonedSourcePackagesDirPath "$build_dir/SourcePackages" \
 -packageCachePath "$build_dir/PackageCache" -disablePackageRepositoryCache \
 "CLANG_MODULE_CACHE_PATH=$build_dir/ModuleCache" \
 "CONFIGURATION_BUILD_DIR=$build_dir/Products" "${@:-build}"
