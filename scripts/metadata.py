import plistlib, sys
from pathlib import Path
app, ext, group, build = sys.argv[1:]
def write(path, data):
    with open(path, 'wb') as f: plistlib.dump(data, f)
base = dict(CFBundleDevelopmentRegion='zh_CN', CFBundleIconFile='QuotaAppIcon-v6.icns', CFBundleShortVersionString='1.2.0', CFBundleVersion='10', LSMinimumSystemVersion='26.0', NSAppTransportSecurity={'NSAllowsLocalNetworking':True})
write(Path(app)/'Contents/Info.plist', dict(base, CFBundleIdentifier='local.codexquota', CFBundleName='Codex 周额度', CFBundleDisplayName='Codex 周额度', CFBundleExecutable='CodexQuota', CFBundlePackageType='APPL', NSPrincipalClass='NSApplication', CFBundleURLTypes=[dict(CFBundleURLName='local.codexquota', CFBundleURLSchemes=['codexquota'])]))
write(Path(ext)/'Contents/Info.plist', dict(base, CFBundleIdentifier='local.codexquota.widget', CFBundleName='Codex 周额度', CFBundleDisplayName='Codex 周额度', CFBundleExecutable='CodexQuotaWidget', CFBundlePackageType='XPC!', NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}))
write(Path(build)/'app.entitlements', {})
write(Path(build)/'widget.entitlements', {'com.apple.security.app-sandbox':True, 'com.apple.security.network.client':True})
