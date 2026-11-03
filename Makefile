PLUGIN_OUT := dist/tesla-monitor.plasmoid
# Set PACKAGE_ROOT to install somewhere other than the user's Plasma widgets folder.
KPT := kpackagetool6 -t Plasma/Applet $(if $(PACKAGE_ROOT),-p $(PACKAGE_ROOT))

.PHONY: build install reload clean

build:
	@mkdir -p dist
	@rm -f $(PLUGIN_OUT)
	@cd package && zip -X -r -q ../$(PLUGIN_OUT) metadata.json contents
	@echo "Built $(PLUGIN_OUT)"

install: build
	@$(KPT) -u $(CURDIR)/$(PLUGIN_OUT) 2>/dev/null || $(KPT) -i $(CURDIR)/$(PLUGIN_OUT)

reload:
	systemctl --user restart plasma-plasmashell.service

clean:
	rm -rf dist
