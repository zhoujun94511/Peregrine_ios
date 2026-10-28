#!/bin/bash
# USES_XCTRUNNER wraps the UI-test bundle in a host app and does not copy
# the bundle's asset-catalog icon onto that host. actool leaves AppIcon*.png
# and Assets.car inside PlugIns/<product>.xctest, which SpringBoard never
# reads. Lift them to the host app root and point Info.plist at AppIcon.

set -euo pipefail

RUNNER_APP="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}-Runner.app"
XCTEST="${RUNNER_APP}/PlugIns/${PRODUCT_NAME}.xctest"

if [ ! -d "$RUNNER_APP" ]; then
    echo "warning: ${PRODUCT_NAME}-Runner.app not found at $RUNNER_APP; skipping icon embed"
    exit 0
fi

if [ ! -d "$XCTEST" ]; then
    echo "warning: ${PRODUCT_NAME}.xctest not found inside Runner.app; skipping icon embed"
    exit 0
fi

shopt -s nullglob
ICONS=("$XCTEST"/AppIcon*.png)
if [ ${#ICONS[@]} -eq 0 ]; then
    echo "warning: no compiled AppIcon*.png found inside $XCTEST; skipping icon embed"
    exit 0
fi

cp -f "${ICONS[@]}" "$RUNNER_APP/"
if [ -f "$XCTEST/Assets.car" ]; then
    cp -f "$XCTEST/Assets.car" "$RUNNER_APP/"
fi

PLIST="$RUNNER_APP/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleIcons~ipad" "$PLIST" 2>/dev/null || true

/usr/libexec/PlistBuddy -c "Add :CFBundleIcons dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName string AppIcon" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles:0 string AppIcon60x60" "$PLIST"

/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconName string AppIcon" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:0 string AppIcon60x60" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconFiles:1 string AppIcon76x76" "$PLIST"

# The host app is already signed by the time this post-action runs, and a
# scheme post-action does not receive CODE_SIGN_IDENTITY. Re-sign with the
# identity already on the bundle. Simulator builds are ad-hoc ("-").
if [ -d "$RUNNER_APP/_CodeSignature" ]; then
    SIGN_INFO=$(codesign -dvv "$RUNNER_APP" 2>&1 || true)
    EXISTING_IDENT="${EXPANDED_CODE_SIGN_IDENTITY:-}"
    if [ -z "$EXISTING_IDENT" ]; then
        EXISTING_IDENT=$(awk -F'=' '/^Authority/ {print $2; exit}' <<< "$SIGN_INFO")
    fi
    if [ -z "$EXISTING_IDENT" ] && grep -q '^Signature=adhoc' <<< "$SIGN_INFO"; then
        EXISTING_IDENT="-"
    fi
    if [ -n "$EXISTING_IDENT" ]; then
        codesign --force --sign "$EXISTING_IDENT" \
                 --preserve-metadata=identifier,entitlements "$RUNNER_APP"
    else
        echo "warning: bundle is signed but no identity discovered; signature will be invalid"
    fi
fi

echo "embedded icon into $RUNNER_APP"
