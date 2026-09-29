CONFIG ?= release
EMOJI_MAX_VERSION ?= 17.0
APP := build/HanMoji.app

.PHONY: all build bundle run open test fetch gen data clean

all: bundle

build:
	swift build -c $(CONFIG)

bundle: build
	CONFIG=$(CONFIG) scripts/bundle_app.sh

# 번들 안의 바이너리를 직접 실행 → 터미널에 로그가 보임
run: bundle
	@pkill -x HanMoji 2>/dev/null || true
	$(APP)/Contents/MacOS/HanMoji

# 백그라운드로 실행 (로그 없음)
open: bundle
	@pkill -x HanMoji 2>/dev/null || true
	open $(APP)

test:
	swift test

fetch:
	scripts/fetch_data.sh

gen:
	swift run -c release hanmoji-datagen Data/raw Sources/HanMoji/Resources/emoji.json --max-emoji-version $(EMOJI_MAX_VERSION)

data: fetch gen

clean:
	rm -rf .build build
