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

.PHONY: all icon install run dev test dist clean

all: $(BUNDLE)

build/$(APP)-%: $(SOURCES)
	@mkdir -p build
	swiftc -O -target $*-apple-$(DEPLOY) -parse-as-library -o $@ $(SOURCES)

$(BUNDLE): $(SLICES) Resources/Info.plist Resources/AppIcon.icns $(wildcard Resources/*.lproj/*) LICENSE NOTICE
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/
	cp -R Resources/*.lproj $(BUNDLE)/Contents/Resources/
	cp LICENSE NOTICE $(BUNDLE)/Contents/Resources/   # the MIT notice has to travel with every copy
	lipo -create $(SLICES) -output $(BUNDLE)/Contents/MacOS/$(APP)
	rm -f $(BUNDLE)/Contents/MacOS/*.cstemp   # left behind by an interrupted signing run
	codesign --force --options runtime --sign $(SIGN) $(BUNDLE)
	@lipo -info $(BUNDLE)/Contents/MacOS/$(APP)
	@touch $(BUNDLE)

# Regenerate the app icon (already committed, so this is rarely needed).
icon:
	swift tools/makeicon.swift Resources/AppIcon.icns

test:
	swift test

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
	@echo "Homebrew cask sha256: $$(shasum -a 256 $(DIST)/$(APP)-$(VERSION).zip | cut -d' ' -f1)"

install: $(BUNDLE)
	-pkill -x $(APP)
	@for i in $$(seq 50); do pgrep -x $(APP) >/dev/null || break; sleep 0.1; done   # open fails with -600 while it is still quitting
	rm -rf /Applications/$(APP).app
	ditto $(BUNDLE) /Applications/$(APP).app

run: install
	open /Applications/$(APP).app

# Faster local loop: host architecture only, in its own bundle so `make dist` stays universal.
dev:
	$(MAKE) run ARCHS=$(shell uname -m) BUNDLE=build/dev/$(APP).app

clean:
	rm -rf build .build $(DIST)
