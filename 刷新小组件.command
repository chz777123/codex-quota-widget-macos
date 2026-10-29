#!/bin/bash
set -euo pipefail
export LC_ALL=C
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
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$quota_app/Contents/Info.plist")
extension_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$quota_extension/Contents/Info.plist")
printf '系统：%s，应用：%s，扩展：%s\n' "$(/usr/bin/sw_vers -productVersion)" "$version" "$extension_version"
/usr/bin/codesign --verify --deep --strict "$quota_app" || {
    printf '代码签名完整性检查失败，未继续注册。\n'
    exit 1
}
printf '签名完整性：通过\n'
# Only restart this app's extension; no system-wide cache deletion or daemon reset.
/usr/bin/pkill -x CodexQuotaWidget || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$quota_app"
# Restore the extension record that may be lost during a macOS upgrade.
/usr/bin/pluginkit -a "$quota_extension" 2>&1 || {
    printf 'PlugInKit 注册命令失败；未删除任何系统缓存。\n'
    exit 1
}
registration="$(/usr/bin/pluginkit -m -A -D -i "$extension_id" 2>&1 || true)"
if [[ "$registration" == *"Connection invalid"* ]]; then
    printf 'PlugInKit 服务返回 Connection invalid。请注销并重新登录，或重启 Mac 后再次运行本工具；未删除任何系统缓存。\n'
    printf '诊断输出：%s\n' "$registration"
    exit 2
fi
if [[ "$registration" != *"$extension_id"* ]]; then
    printf '扩展尚未出现在 PlugInKit 注册表。请保留以下诊断输出：\n%s\n' "$registration"
    printf '如果应用刚更新，请关闭并重新打开“编辑小组件”。\n'
    exit 1
fi
printf 'PlugInKit 注册：通过（%s）\n' "$registration"
/usr/bin/open -a "$quota_app" 'codexquota://refresh'
printf '已重新注册额度应用和小组件扩展，并请求同步。请重新打开“编辑小组件”并搜索“Codex 周额度”。\n'
