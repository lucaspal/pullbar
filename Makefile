APP_NAME := pullbar
BUILD_DIR := build
APP := $(BUILD_DIR)/$(APP_NAME).app
## Optional: stamp CFBundleShortVersionString, e.g. `make app VERSION=1.2.3`
VERSION ?=

.PHONY: build run test mutation-test app install clean

SPARKLE_ROOT := .build/artifacts/sparkle/Sparkle
SPARKLE_FRAMEWORK := $(SPARKLE_ROOT)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework

APP_ICON := $(BUILD_DIR)/AppIcon.icns

## Compile a release binary into .build/release/pullbar
build:
	swift build -c release

## Run straight from the package (Dock-less, menu bar only)
run:
	swift run -c release pullbar

## Assemble a double-clickable, ad-hoc signed "$(APP_NAME).app" in build/
app: build $(APP_ICON)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(APP)/Contents/Frameworks"
	ditto "$(SPARKLE_FRAMEWORK)" "$(APP)/Contents/Frameworks/Sparkle.framework"
	cp "$(SPARKLE_ROOT)/LICENSE" "$(APP)/Contents/Resources/Sparkle-LICENSE"
	cp .build/release/pullbar "$(APP)/Contents/MacOS/pullbar"
	cp Packaging/Info.plist "$(APP)/Contents/Info.plist"
ifneq ($(VERSION),)
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" "$(APP)/Contents/Info.plist"
endif
	cp "$(APP_ICON)" "$(APP)/Contents/Resources/AppIcon.icns"
	sh Packaging/stamp-build-info.sh "$(APP)/Contents/Info.plist"
	bash Packaging/configure-updates.sh "$(APP)/Contents/Info.plist"
	echo -n "APPL????" > "$(APP)/Contents/PkgInfo"
	codesign --force --sign - --identifier dev.pullbar.menubar "$(APP)"
	@echo "Built $(APP)"

$(APP_ICON): Packaging/AppIcon-1024.png Packaging/build-icon.sh
	mkdir -p "$(BUILD_DIR)"
	sh Packaging/build-icon.sh "$<" "$@"

## Copy the app to ~/Applications and launch it
install: app
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/$(APP_NAME).app"
	ditto "$(APP)" "$(HOME)/Applications/$(APP_NAME).app"
	open "$(HOME)/Applications/$(APP_NAME).app"

clean:
	rm -rf .build "$(BUILD_DIR)"

## Run the unit tests
test:
	swift test

## Check that the tests catch deliberate bugs (see scripts/mutation-test.sh)
mutation-test:
	scripts/mutation-test.sh
