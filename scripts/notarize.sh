#!/bin/bash
# Run only with the owner's Developer ID-signed app and a configured notarytool profile.
set -euo pipefail
app="${1:?Usage: notarize.sh /absolute/path/app}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your existing notarytool Keychain profile}"
codesign --verify --deep --strict "$app"
if ! codesign -dv "$app" 2>&1 | grep -q 'Authority=Developer ID Application:'; then
    echo 'Developer ID Application signature required; ad hoc builds cannot be notarized.' >&2
    exit 1
fi
stage=$(mktemp -d /private/tmp/quota-notarize.XXXXXX)
trap 'rm -rf "$stage"' EXIT
ditto -c -k --keepParent "$app" "$stage/submission.zip"
xcrun notarytool submit "$stage/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$stage/result.json"
python3 - "$stage/result.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print('Notarization:', result.get('status'), 'Submission:', result.get('id'))
if result.get('status') != 'Accepted':
    raise SystemExit('Not accepted. Use notarytool log with this submission ID before distributing.')
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
