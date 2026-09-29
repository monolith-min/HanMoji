#!/bin/bash
# swift build 결과를 build/HanMoji.app 번들로 만든다.
#   CONFIG=release CODESIGN_IDENTITY="HanMoji Dev" scripts/bundle_app.sh
#
# 서명 주의: ad-hoc(-) 서명은 빌드마다 해시가 바뀌어 접근성 권한을 다시 켜야 한다.
# 자체 서명 인증서("HanMoji Dev")를 만들어 두면 재빌드 후에도 권한이 유지된다. README 참고.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/HanMoji.app"
BIN="$ROOT/.build/$CONFIG/HanMoji"
BUNDLE_ID="com.hanmoji.HanMoji"

[ -x "$BIN" ] || { echo "binary not found: $BIN (run: swift build -c $CONFIG)"; exit 1; }
[ -s "$ROOT/Sources/HanMoji/Resources/emoji.json" ] || { echo "emoji.json missing (run: make data)"; exit 1; }

VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo 0.1.0)}"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || date +%Y%m%d%H%M)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HanMoji"
cp "$ROOT/Sources/HanMoji/Resources/emoji.json" "$APP/Contents/Resources/emoji.json"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$ROOT/Data/Info.plist.template" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 서명 identity: 환경변수 > "HanMoji Dev" 자체 서명 인증서 > Apple Development 인증서 > ad-hoc
IDENTITY="${CODESIGN_IDENTITY:-}"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [ -z "$IDENTITY" ] && echo "$IDENTITIES" | grep -q '"HanMoji Dev"'; then
  IDENTITY="HanMoji Dev"
fi
if [ -z "$IDENTITY" ]; then
  # 이름에 비ASCII 문자가 있으면 codesign이 실패할 수 있어 SHA-1 해시로 지정
  IDENTITY="$(echo "$IDENTITIES" | grep 'Apple Development:' | head -1 | awk '{print $2}')"
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  echo "note: ad-hoc signing. 재빌드마다 접근성 권한을 다시 켜야 합니다 (README '서명' 참고)."
fi
if ! codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"; then
  echo "codesign failed with identity '$IDENTITY'; falling back to ad-hoc"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
SIGNED_BY="$(codesign -dvv "$APP" 2>&1 | grep -m1 -E '^Authority=' | sed 's/Authority=//' || true)"
echo "bundled: $APP (v$VERSION build $BUILD, signed by: ${SIGNED_BY:-ad-hoc})"
