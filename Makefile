PLUGIN_ID := net.moseph.teslamonitor
PLUGIN_OUT := dist/tesla-monitor.plasmoid
# Set PACKAGE_ROOT to install somewhere other than the user's Plasma widgets folder.
KPT := kpackagetool6 -t Plasma/Applet $(if $(PACKAGE_ROOT),-p $(PACKAGE_ROOT))
# qmlformat parses QML without needing Plasma's modules, so it checks syntax anywhere.
QMLFORMAT ?= $(firstword $(shell command -v qmlformat6 qmlformat 2>/dev/null) \
	$(wildcard /usr/lib/qt6/bin/qmlformat /usr/lib64/qt6/bin/qmlformat))
QML_FILES := $(wildcard package/contents/ui/*.qml package/contents/config/*.qml)

.PHONY: help build install uninstall reload clean test lint

help:
	@echo "make build      build $(PLUGIN_OUT)"
	@echo "make install    build, then install or upgrade the widget"
	@echo "make uninstall  remove the installed widget"
	@echo "make reload     restart Plasma so new QML loads"
	@echo "make test       run the unit tests (Node.js 18+)"
	@echo "make lint       check QML syntax, the metadata, the config schema and the shell script"
	@echo "make clean      remove dist/"

build:
	@command -v zip >/dev/null || { echo "zip is required to build the package" >&2; exit 1; }
	@mkdir -p dist
	@rm -f $(PLUGIN_OUT)
	@cd package && zip -X -r -q ../$(PLUGIN_OUT) metadata.json contents
	@echo "Built $(PLUGIN_OUT)"

install: build
	@$(KPT) -u $(CURDIR)/$(PLUGIN_OUT) 2>/dev/null || $(KPT) -i $(CURDIR)/$(PLUGIN_OUT)

uninstall:
	$(KPT) -r $(PLUGIN_ID)

reload:
	systemctl --user restart plasma-plasmashell.service

clean:
	rm -rf dist

test:
	@node --test tests/*.test.mjs

lint:
	@status=0; \
	if [ -n "$(QMLFORMAT)" ]; then \
		for f in $(QML_FILES); do "$(QMLFORMAT)" "$$f" >/dev/null || { echo "QML syntax error in $$f" >&2; status=1; }; done; \
	else echo "skipping QML: qmlformat not found (Qt 6 declarative tools)"; fi; \
	if command -v jq >/dev/null; then jq empty package/metadata.json || status=1; \
	else echo "skipping metadata.json: jq not found"; fi; \
	if command -v xmllint >/dev/null; then xmllint --noout package/contents/config/main.xml || status=1; \
	else echo "skipping main.xml: xmllint not found"; fi; \
	if command -v shellcheck >/dev/null; then shellcheck tools/*.sh || status=1; \
	else echo "skipping tools/: shellcheck not found"; fi; \
	[ $$status -eq 0 ] && echo "Lint passed"; exit $$status
