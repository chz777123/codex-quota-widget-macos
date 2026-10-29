#!/bin/bash
set -u
export LC_ALL=C
quota_app=""
for candidate in "$HOME/Applications/Codex 周额度.app" "/Applications/Codex 周额度.app"; do
    if [[ -d "$candidate" ]]; then quota_app="$candidate"; break; fi
done
if [[ -z "$quota_app" ]]; then
    printf '状态：未安装 Codex 周额度.app\n'
    exit 1
fi
extension="$quota_app/Contents/PlugIns/CodexQuotaWidget.appex"
app_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$quota_app/Contents/Info.plist" 2>/dev/null || true)
extension_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$extension/Contents/Info.plist" 2>/dev/null || true)
printf '系统：%s\n应用路径：%s\n应用 Bundle ID：%s\n扩展 Bundle ID：%s\n' "$(/usr/bin/sw_vers -productVersion)" "$quota_app" "$app_id" "$extension_id"
if [[ "$app_id" != "local.codexquota" ]]; then printf '状态：应用 Bundle ID 不匹配\n'; exit 2; fi
if [[ "$extension_id" != "local.codexquota.widget" ]]; then printf '状态：扩展 Bundle ID 不匹配\n'; exit 2; fi
if ! /usr/bin/codesign --verify --deep --strict "$quota_app" 2>/dev/null; then
    printf '状态：代码签名验证失败\n'
    exit 3
fi
printf '签名：通过\n'
registration="$(/usr/bin/pluginkit -m -A -D -i "$extension_id" 2>&1 || true)"
if [[ "$registration" == *"Connection invalid"* ]]; then
    printf '状态：PlugInKit 服务不可用（Connection invalid）\n诊断：%s\n' "$registration"
    exit 4
fi
if [[ "$registration" == *"$extension_id"* ]]; then
    printf '状态：已注册\nPlugInKit：%s\n' "$registration"
    exit 0
fi
printf '状态：扩展未注册\nPlugInKit：%s\n' "$registration"
printf '建议：运行“刷新小组件.command”，或重新打开“编辑小组件”。\n'
exit 5
