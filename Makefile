APP_NAME := RemoteKeepAliver
BUNDLE_ID := com.ryanlowe.RemoteKeepAliver
APP := build/$(APP_NAME).app

.PHONY: build test bundle run install clean

build:
	swift build -c release

test:
	swift test

# Safe to re-run: directories are created with -p and files are overwritten.
bundle: build
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp -f "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp -f Packaging/Info.plist "$(APP)/Contents/Info.plist"
	printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP)"

run: bundle
	open "$(APP)"

install: bundle
	-pkill -x $(APP_NAME)
	ditto "$(APP)" "/Applications/$(APP_NAME).app"

clean:
	swift package clean
	rm -rf build
