#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

case "$MODE" in
  run|--build-only|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [--build-only|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

if [[ "$MODE" != "--build-only" ]]; then
  if pgrep -x Breeze >/dev/null; then
    osascript -e 'tell application id "com.breeze.fancontrol" to quit'
    for _ in {1..20}; do
      if ! pgrep -x Breeze >/dev/null; then break; fi
      sleep 0.25
    done
    if pgrep -x Breeze >/dev/null; then
      echo "O Breeze ainda está restaurando o modo automático. Feche pelo menu antes de recompilar." >&2
      exit 1
    fi
  fi
fi

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  echo "Set SIGNING_IDENTITY to an Apple Development or Developer ID Application certificate fingerprint." >&2
  echo "List certificates with: security find-identity -v -p codesigning" >&2
  exit 1
fi
CONFIGURATION="${CONFIGURATION:-Debug}"

xcodegen generate --spec project.yml
mkdir -p build
xcodebuild -project Breeze.xcodeproj -scheme Breeze -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$ROOT_DIR/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build > build/build.log 2>&1 || {
    rg -n -A 5 'error:|BUILD FAILED' build/build.log || tail -n 20 build/build.log
    exit 1
  }

APP_BUNDLE="$ROOT_DIR/build/DerivedData/Build/Products/$CONFIGURATION/Breeze.app"
HELPER="$APP_BUNDLE/Contents/Library/HelperTools/BreezeHelper"
codesign --force --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" \
  --identifier com.breeze.fancontrol.Helper "$HELPER"
codesign --force --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" \
  --identifier com.breeze.fancontrol "$APP_BUNDLE"
codesign --verify --strict "$HELPER"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "App compilado e assinado: $APP_BUNDLE"

case "$MODE" in
  --build-only) exit 0 ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/Breeze" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem BEGINSWITH "com.breeze.fancontrol"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x Breeze >/dev/null
    ;;
esac
