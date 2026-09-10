.PHONY: ios ios-devices

ios:
	@bash scripts/run-ios.sh

ios-devices:
	@xcrun devicectl list devices --timeout 30
