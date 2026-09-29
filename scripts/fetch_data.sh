#!/bin/bash
# CLDR 한국어/영어 annotation과 Unicode emoji-test.txt를 Data/raw/ 로 내려받는다.
#   CLDR_TAG=release-48-2 EMOJI_VERSION=17.0 scripts/fetch_data.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW="$ROOT/Data/raw"
CLDR_TAG="${CLDR_TAG:-release-48-2}"
EMOJI_VERSION="${EMOJI_VERSION:-latest}"
BASE="https://raw.githubusercontent.com/unicode-org/cldr/$CLDR_TAG/common"

mkdir -p "$RAW"
fetch() { echo "  $2"; curl -fsSL --retry 3 -o "$RAW/$1" "$2"; }

echo "CLDR $CLDR_TAG"
fetch annotations-ko.xml        "$BASE/annotations/ko.xml"
fetch annotationsDerived-ko.xml "$BASE/annotationsDerived/ko.xml"
fetch annotations-en.xml        "$BASE/annotations/en.xml"
fetch annotationsDerived-en.xml "$BASE/annotationsDerived/en.xml"
echo "emoji-test.txt ($EMOJI_VERSION)"
fetch emoji-test.txt "https://unicode.org/Public/emoji/$EMOJI_VERSION/emoji-test.txt"

EMOJI_ACTUAL="$(grep -m1 -oE 'Version: [0-9.]+' "$RAW/emoji-test.txt" | awk '{print $2}' || true)"
echo "CLDR $CLDR_TAG / emoji-test ${EMOJI_ACTUAL:-$EMOJI_VERSION} / fetched $(date +%Y-%m-%d)" > "$RAW/VERSION"
echo "done: $(cat "$RAW/VERSION")"
