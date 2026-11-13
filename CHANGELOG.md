# Changelog

All notable changes to Tesla Monitor are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.7.0] - 2026-11-13

### Added

- The ring marks the charge limit with a gap in its track, or a notch where a gap can't show, and the level turns red below 10% unless the car is charging.
- Open doors are drawn as a door panel with a dark doorway behind it.
- While charging, the time left is the card's main line, with when the charge will be done below it.
- Plasma's About page for the widget links to the project's website and issue tracker.
- `make uninstall`, `make lint` and `make help`.
- Continuous integration, release packages on GitHub, a changelog, and contributing, security and issue guidelines.

### Changed

- The card keeps the car at its full width when rows need more room, such as with a large font, and grows taller instead.
- The ring and the state dot keep their colors in the panel popup.
- A stale "Updated" time is shown at full strength so it stays readable.

### Fixed

- A warning of several words no longer makes the popup much taller than it needs.
- Reading the configuration no longer counts as a settings change.
- The shading at the car's ends is no longer drawn over the lights.
- An open rear door no longer runs into its open window, and the ring's end no longer shows past the limit when the level is just under it.

## [1.6.0] - 2026-11-11

### Added

- The car is drawn in its own paint, from TeslaMate's `exterior_color`, with dark glass and lights. A new **Car color** setting chooses between the paint and theme colors.

### Changed

- Refreshed card: a clearer battery ring, the stats on one strip, and the car lying on its side with its nose to the right.
- A stale card fades its ring, stats and car.

## [1.5.1] - 2026-11-10

### Fixed

- An update is shown as installing only while the car is actually updating.

## [1.5.0] - 2026-11-05

### Added

- Desktop notifications for charging finished or stopped early, something left open, the car unlocked with nobody inside, low tire pressure, and software updates. Copies of the widget showing the same car notify once.
- Charging details: power, time left and when it'll be done, energy added, current and voltage with phases, and the current the car asks for.
- While driving, the battery's power, and optionally the destination, arrival time, distance left and battery level on arrival.
- The card says whether the car is plugged in, finished charging, stopped early, waiting for a scheduled start, or on a charger with no power.
- One warning that lists everything that needs attention, cold-battery usable capacity, and update download and install progress.
- Stale data is faded with the time of the last update, a refresh button, and slower polling while the car sleeps.
- Connection and Display settings pages, TLS with an optional CA file, pasting a broker URL, **Test Connection** and **Find Cars**.
- Separate distance, temperature and tire pressure units that follow the locale by default.
- Panel text choices: percentage, range or both, and the time to full while charging.
- Clicking the car's name opens TeslaMate. The panel icon works from the keyboard and screen readers.
- `tools/fake-teslamate.sh` to publish made-up TeslaMate data for testing.
- Unit tests for the widget's logic.

### Changed

- The panel icon is sized like a system tray icon.
- Connection errors are explained in words, such as an unknown host, a rejected login or a TLS failure.

### Fixed

- Empty MQTT values show as missing instead of `(null)`.
- Both car drawings render on HiDPI machines using Qt's software renderer.
- A poll to an unreachable host no longer hangs for about 2 minutes.

## [1.4.1] - 2026-11-04

### Fixed

- The panel icon is drawn reliably on Qt 6.7 and 6.8, and the card's car drawing is no longer scaled smaller than its wheels and doors.

## [1.4.0] - 2026-11-03

### Added

- One top-down car drawing with each tire's pressure, doors, windows, frunk, trunk, charge port, lock and Sentry, replacing the tire diagram and status list.
- **Right-hand drive** setting.

### Fixed

- The car outline on Qt 6.7 and 6.8.

## [1.3.0] - 2026-11-03

### Added

- A setting to hide the percentage next to the panel icon.

## [1.2.0] - 2026-11-03

### Added

- The panel icon is a Model 3 shaped battery in the style of Plasma's battery icon, with a bolt while charging.

## [1.1.0] - 2026-11-03

### Added

- First public version of the widget.

[1.7.0]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/4fc8407...v1.7.0
[1.6.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/4fc8407
[1.5.1]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/cad2fd9
[1.5.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/4a90dd5
[1.4.1]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/7e2bfd8
[1.4.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/0ce0db8
[1.3.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/c1b9728
[1.2.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/ea6d888
[1.1.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/ff53763
