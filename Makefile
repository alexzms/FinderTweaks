.PHONY: build test install cert snapshot logs clean

# With only the Command Line Tools installed, swift-testing needs its framework path spelled out.
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
CLT_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
	-Xlinker -F -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW)
endif

build:          ## Build build/FinderTweaks.app
	./scripts/build.sh

test:           ## Run unit tests
	swift test $(TEST_FLAGS)

install: build  ## Build, copy to ~/Applications and relaunch
	./scripts/install.sh

cert:           ## One-time: create the local signing identity
	./scripts/create-signing-cert.sh

snapshot: build ## Render UI states to build/snapshots/*.png
	build/FinderTweaks.app/Contents/MacOS/FinderTweaks --snapshot build/snapshots

logs:           ## Follow the diagnostics log
	tail -f ~/Library/Logs/FinderTweaks.log

clean:
	rm -rf .build build
