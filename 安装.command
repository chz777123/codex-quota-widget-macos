#!/bin/bash
set -euo pipefail
package_dir="$(cd "$(dirname "$0")" && pwd)"
source_app="$package_dir/Codex 周额度.app"
target="$HOME/Applications/Codex 周额度.app"
fail() { printf '安装未完成：%s\n' "$*" >&2; exit 1; }
case "${1:-}" in ""|--check) ;; *) fail '仅支持无参数安装，或 --check 检查。' ;; esac
major=$(/usr/bin/sw_vers -productVersion)
[[ "${major%%.*}" -ge 26 ]] || fail '需要 macOS 26 或更高版本。'
case "$(/usr/bin/uname -m)" in arm64|x86_64) ;; *) fail '不支持此处理器架构。' ;; esac
[[ -d "$source_app" ]] || fail '请完整解压安装包，并将本工具与应用放在同一文件夹。'
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$source_app/Contents/Info.plist")" == local.codexquota ]] || fail '应用标识不匹配。'
/usr/bin/codesign --verify --deep --strict "$source_app" || fail '应用签名完整性检查失败，请重新取得安装包。'
for executable in "$source_app/Contents/MacOS/CodexQuota" "$source_app/Contents/PlugIns/CodexQuotaWidget.appex/Contents/MacOS/CodexQuotaWidget"; do
    /usr/bin/file "$executable" | /usr/bin/grep -q "$(/usr/bin/uname -m)" || fail '安装包缺少本机架构。'
done
printf '系统、处理器架构、应用签名完整性检查通过。\n'
if ! /usr/sbin/spctl --assess --type execute "$source_app" >/dev/null 2>&1; then
    printf '提示：本包尚未通过 Gatekeeper 分发评估。若系统阻止打开，请阅读 README 中的开发版安装说明；本工具不会关闭系统保护。\n'
fi
[[ "${1:-}" != --check ]] || exit 0
[[ ! -d '/Applications/Codex 周额度.app' ]] || fail '系统 Applications 中已有同名应用。请按 README 手动更新原位置，避免安装两个副本。'
if [[ -e "$target" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target/Contents/Info.plist")" == local.codexquota ]] || fail '目标位置存在其他内容，未覆盖。'
fi
mkdir -p "$HOME/Applications"
staging=$(mktemp -d "$HOME/Applications/.codexquota-install.XXXXXX")
trap 'rm -rf "$staging"' EXIT
/usr/bin/ditto "$source_app" "$staging/Codex 周额度.app"
/usr/bin/codesign --verify --deep --strict "$staging/Codex 周额度.app"
# This app contains no editable documents. Stop only its host and widget before replacing.
/usr/bin/pkill -x CodexQuota || true
/usr/bin/pkill -x CodexQuotaWidget || true
backup=""
if [[ -e "$target" ]]; then
    mkdir -p "$HOME/Library/Application Support/CodexQuota/Backups"
    backup=$(mktemp -d "$HOME/Library/Application Support/CodexQuota/Backups/update.XXXXXX")
    mv "$target" "$backup/"
fi
if ! mv "$staging/Codex 周额度.app" "$target"; then
    if [[ -n "$backup" ]]; then mv "$backup/Codex 周额度.app" "$target"; fi
    fail '替换失败，旧版已尝试恢复。'
fi
printf '已安装到：%s\n' "$target"
[[ -z "$backup" ]] || printf '旧版备份：%s\n' "$backup"
/bin/bash "$package_dir/刷新小组件.command" || fail '应用已安装，但注册或打开未完成，请阅读 README 并重试刷新工具。'
