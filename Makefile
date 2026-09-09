APP     := HoldOn
BUNDLE  := build/$(APP).app
SOURCES := $(wildcard Sources/*.swift)
DEPLOY  := macos14.0
ARCHS   := arm64 x86_64
SLICES  := $(addprefix build/$(APP)-,$(ARCHS))
SIGN    := $(shell security find-identity -v -p codesigning | awk '/Apple Development|Developer ID/ {print $$2; exit}')
SIGN    := $(if $(SIGN),$(SIGN),-)
DIST    := dist
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

.PHONY: all icon install run test dist clean

all: $(BUNDLE)

build/$(APP)-%: $(SOURCES)
	@mkdir -p build
	swiftc -O -target $*-apple-$(DEPLOY) -parse-as-library -o $@ $(SOURCES)

$(BUNDLE): $(SLICES) Resources/Info.plist Resources/AppIcon.icns $(wildcard Resources/*.lproj/*)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/
	cp -R Resources/*.lproj $(BUNDLE)/Contents/Resources/
	lipo -create $(SLICES) -output $(BUNDLE)/Contents/MacOS/$(APP)
	codesign --force --options runtime --sign $(SIGN) $(BUNDLE)
	@lipo -info $(BUNDLE)/Contents/MacOS/$(APP)
	@touch $(BUNDLE)

# Regenerate the app icon (already committed, so this is rarely needed).
icon:
	swift tools/makeicon.swift Resources/AppIcon.icns

test:
	@mkdir -p build
	swiftc -o build/tests Sources/Store.swift Tests/main.swift && ./build/tests

# Release archives for GitHub Releases.
dist: $(BUNDLE)
	@mkdir -p $(DIST)
	rm -rf build/dmg $(DIST)/$(APP)-$(VERSION).zip $(DIST)/$(APP)-$(VERSION).dmg
	ditto -c -k --keepParent $(BUNDLE) $(DIST)/$(APP)-$(VERSION).zip
	mkdir -p build/dmg
	cp -R $(BUNDLE) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "$(APP)" -srcfolder build/dmg -ov -format UDZO -quiet $(DIST)/$(APP)-$(VERSION).dmg
	rm -rf build/dmg
	@ls -lh $(DIST)

install: $(BUNDLE)
	-pkill -x $(APP)
	rm -rf /Applications/$(APP).app
	ditto $(BUNDLE) /Applications/$(APP).app

run: install
	open /Applications/$(APP).app

clean:
	rm -rf build $(DIST)
