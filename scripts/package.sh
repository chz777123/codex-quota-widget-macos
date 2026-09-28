#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Usage: package.sh /absolute/path/app /absolute/path/output.zip}"
output="${2:?Output zip is required}"
[[ "$app" = /* && "$output" = /* ]] || { echo 'Use absolute paths.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
for binary in "$app/Contents/MacOS/CodexQuota" "$app/Contents/PlugIns/CodexQuotaWidget.appex/Contents/MacOS/CodexQuotaWidget"; do
    architectures=" $(xcrun lipo -archs "$binary") "
    for required in arm64 x86_64; do
        [[ "$architectures" == *" $required "* ]] || { echo "Missing $required" >&2; exit 1; }
    done
    if otool -L "$binary" | awk '/^[[:space:]]/ {print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)' | grep -q .; then
        echo 'Unexpected non-system runtime dependency.' >&2; exit 1
    fi
done
stage=$(mktemp -d /private/tmp/quota-distribution.XXXXXX)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/CodexQuota-安装包"
ditto "$app" "$stage/CodexQuota-安装包/Codex 周额度.app"
cp 安装说明.md "$stage/CodexQuota-安装包/README.md"
cp 安装.command 刷新小组件.command "$stage/CodexQuota-安装包/"
chmod 755 "$stage/CodexQuota-安装包/"*.command
# Package only the allowlisted application and instructions, never preferences, caches or accounts.
ditto -c -k --sequesterRsrc --keepParent "$stage/CodexQuota-安装包" "$stage/package.zip"
unzip -t "$stage/package.zip" >/dev/null
mv -f "$stage/package.zip" "$output"
echo "Packaged: $output"
