# Contributing

Bug reports, ideas and pull requests are welcome. For anything larger than a small fix,
please open an issue first so we can agree on the approach.

## Reporting bugs

Use the [bug report form](https://github.com/moseph333/tesla-monitor-plasmoid/issues/new/choose).
The widget's version, your Plasma and TeslaMate versions, and the output of
`journalctl --user -b -u plasma-plasmashell | grep -i tesla` make problems much quicker to find.
Remove your broker's host name and any credentials before posting logs.

Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Development

See [Development](README.md#development) in the README for building, installing and
reloading the widget, and for `tools/fake-teslamate.sh`, which lets you try every state
without a car.

Before opening a pull request:

1. Run `make test` and `make lint`.
2. Try the change in a real Plasma session with `make install && make reload`. For changes
   to the card, check Breeze Light and Breeze Dark, and a panel as well as the desktop.
3. Add tests to `tests/logic.test.mjs` for changes to `logic.js`, `models.js` or `notifyhub.js`.
   `logic.js` stays free of `Qt` and `i18n()` so Node can run it; put wording in the QML.
4. Wrap every user-visible string in `i18n()` or `i18nc()`.
5. Describe user-visible changes under a new version in [CHANGELOG.md](CHANGELOG.md),
   update the README if the behavior or settings change, and raise `Version` in
   `package/metadata.json`.
6. Include a screenshot for visual changes.

## Releases

Maintainers release by pushing a tag that matches `Version`, such as `v1.7.0`. The release
workflow checks the tag, runs the tests, and publishes the `.plasmoid` with the notes from
the changelog.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
