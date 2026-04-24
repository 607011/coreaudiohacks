APP      = MusicFormatSwitcher
BUNDLE   = $(APP).app
INSTALL  = $(HOME)/Applications/$(BUNDLE)
PLIST    = Resources/Info.plist
VERSION  = $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' | grep . || echo "1.0")

# Legacy daemon targets
DAEMON        = music-format-daemon
DAEMON_SOURCE = music-format-daemon.swift
AGENT         = $(HOME)/Library/LaunchAgents/com.user.music-format-daemon.plist

.PHONY: all build bundle install dmg pkg release uninstall-daemon clean

all: bundle

# ── App ──────────────────────────────────────────────────────────────────────

build:
	swift build -c release

bundle: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp .build/release/$(APP) $(BUNDLE)/Contents/MacOS/
	cp $(PLIST) $(BUNDLE)/Contents/
	strip -rSTx $(BUNDLE)/Contents/MacOS/$(APP)
	codesign --sign - --force $(BUNDLE)

install: bundle uninstall-daemon
	@rm -rf $(INSTALL)
	cp -r $(BUNDLE) $(INSTALL)
	@echo "Installed to ~/Applications/$(BUNDLE)"
	open $(INSTALL)

# ── Distribution ─────────────────────────────────────────────────────────────

dmg: bundle
	@rm -rf dmg-staging $(APP)-$(VERSION).dmg
	mkdir dmg-staging
	cp -r $(BUNDLE) dmg-staging/
	ln -s /Applications dmg-staging/Applications
	hdiutil create -volname "$(APP) $(VERSION)" \
		-srcfolder dmg-staging -ov -format UDZO \
		-o $(APP)-$(VERSION).dmg
	codesign --sign - $(APP)-$(VERSION).dmg
	rm -rf dmg-staging
	@echo "Created $(APP)-$(VERSION).dmg"

pkg: bundle
	@rm -rf pkg-root $(APP)-$(VERSION).pkg
	mkdir -p pkg-root/Applications
	cp -r $(BUNDLE) pkg-root/Applications/
	pkgbuild --root pkg-root \
		--identifier com.user.MusicFormatSwitcher \
		--version $(VERSION) \
		--install-location / \
		$(APP)-$(VERSION).pkg
	codesign --sign - $(APP)-$(VERSION).pkg
	rm -rf pkg-root
	@echo "Created $(APP)-$(VERSION).pkg"

release: dmg pkg

# ── Daemon (legacy) ──────────────────────────────────────────────────────────

$(DAEMON): $(DAEMON_SOURCE)
	swiftc -O -wmo -o $@ $<
	strip -rSTx $@

uninstall-daemon:
	@if [ -f "$(AGENT)" ]; then \
		launchctl unload "$(AGENT)" 2>/dev/null; \
		rm "$(AGENT)"; \
		echo "Removed old LaunchAgent."; \
	fi

# ── Misc ─────────────────────────────────────────────────────────────────────

clean:
	rm -rf .build $(BUNDLE) $(DAEMON) dmg-staging pkg-root *.dmg *.pkg
