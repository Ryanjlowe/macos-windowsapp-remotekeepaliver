APP_NAME := RemoteKeepAliver
BUNDLE_ID := com.ryanlowe.RemoteKeepAliver
APP := build/$(APP_NAME).app
# A stable identity keeps the Accessibility grant across rebuilds. Ad-hoc
# signing ("-") ties the designated requirement to the cdhash, so every
# rebuild loses the grant. Override with SIGN_IDENTITY="name".
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p;s/.*"\(RemoteKeepAliver Dev\)".*/\1/p' | head -1)

ICON := Packaging/Icon/AppIcon.icns
ICON_SIZES := 16 32 128 256 512

.PHONY: build test icon bundle run install clean

build:
	swift build -c release

test:
	swift test

# Renders the icon with AppKit, then builds the .icns and a README preview.
icon:
	mkdir -p build/icon.iconset
	swiftc -O Packaging/Icon/make-icon.swift -o build/make-icon
	build/make-icon build/icon-1024.png
	for s in $(ICON_SIZES); do \
	  sips -z $$s $$s build/icon-1024.png --out build/icon.iconset/icon_$${s}x$${s}.png >/dev/null; \
	  d=$$(expr $$s \* 2); \
	  sips -z $$d $$d build/icon-1024.png --out build/icon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/icon.iconset -o $(ICON)
	sips -z 256 256 build/icon-1024.png --out docs/images/app-icon.png >/dev/null

# Safe to re-run: directories are created with -p and files are overwritten.
bundle: build
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp -f "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp -f Packaging/Info.plist "$(APP)/Contents/Info.plist"
	cp -f $(ICON) "$(APP)/Contents/Resources/AppIcon.icns"
	printf 'APPL????' > "$(APP)/Contents/PkgInfo"
	codesign --force --sign "$(if $(SIGN_IDENTITY),$(SIGN_IDENTITY),-)" --identifier $(BUNDLE_ID) "$(APP)"

run: bundle
	open "$(APP)"

install: bundle
	-pkill -x $(APP_NAME)
	ditto "$(APP)" "/Applications/$(APP_NAME).app"

clean:
	swift package clean
	rm -rf build
