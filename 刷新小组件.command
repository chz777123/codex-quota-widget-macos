#!/bin/bash
set -euo pipefail
quota_app=""
for candidate in "$HOME/Applications/Codex 周额度.app" "/Applications/Codex 周额度.app"; do
    if [[ -d "$candidate" ]]; then
        quota_app="$candidate"
        break
    fi
done
if [[ -z "$quota_app" ]]; then
    printf '未找到已安装的 Codex 周额度，请先将应用放到 Applications 文件夹。\n'
    exit 1
fi
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$quota_app/Contents/Info.plist")
if [[ "$bundle_id" != "local.codexquota" ]]; then
    printf '应用标识不匹配，未执行修复。\n'
    exit 1
fi
quota_extension="$quota_app/Contents/PlugIns/CodexQuotaWidget.appex"
if [[ ! -d "$quota_extension" ]]; then
    printf '安装包缺少小组件扩展，请重新安装完整应用。\n'
    exit 1
fi
extension_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$quota_extension/Contents/Info.plist")
if [[ "$extension_id" != "local.codexquota.widget" ]]; then
    printf '小组件标识不匹配，未执行修复。\n'
    exit 1
fi
# Only restart this app's extension; no system-wide cache deletion or daemon reset.
/usr/bin/pkill -x CodexQuotaWidget || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$quota_app"
# Restore the extension record that may be lost during a macOS upgrade.
/usr/bin/pluginkit -a "$quota_extension"
registration=$(/usr/bin/pluginkit -m -A -D -i "$extension_id")
if [[ "$registration" != *"local.codexquota.widget"* ]]; then
    printf '系统尚未确认小组件注册，请保留此信息以便排查：\n%s\n' "$registration"
    exit 1
fi
/usr/bin/open -a "$quota_app" 'codexquota://refresh'
printf '已重新注册额度应用和小组件扩展，并请求同步。请等待更新；若小组件已消失，请重新打开“编辑小组件”并添加 Codex 周额度。\n'
