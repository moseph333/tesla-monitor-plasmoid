# Changelog

All notable changes to Tesla Monitor are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The widget's description in Plasma's widget browser names every data source, not only TeslaMate over MQTT and the Tesla Fleet API.

### Fixed

- Two widgets showing different cars through the Tesla Fleet API, Teslemetry, Tessie, Home Assistant or the TeslaMate API no longer count as copies of one car, where a notification for one car kept the same notification for the other from being sent.
- With the Tesla Fleet API, Teslemetry and Tessie, notifications are sent for what a sleeping car wakes up with, such as a low tire or a software update. The 15 minutes between polls of a sleeping car counted as a break in the data, after which the widget only records what it finds, and with polls 15 minutes or more apart no notification was ever sent. Copies of the widget that poll more than two hours apart also no longer send the same notification twice.
- With a token server or proxy that renews the Fleet API's access token without replacing the refresh token, the widget keeps renewing. It reused the first renewed access token after that one expired, and said the Tesla API rejected the access token until Plasma restarted.
- Applying a change to the connection settings while the widget renews the Fleet API's tokens no longer deletes the Teslemetry, Tessie, TeslaMate API and Home Assistant tokens from the wallet. The renewed tokens also no longer replace Fleet API tokens entered in that moment.
- With the Tesla Fleet API and Teslemetry, the widget no longer stops updating until the settings change again when a request gets no answer right after the connection settings were applied. The request the change had dropped could switch off the next one's 20-second limit, and the widget then waited for an answer for good.
- Tokens renewed for a request that a change of settings dropped are no longer sent with the request that follows it, which may go to another service.
- With the Tesla Fleet API and Teslemetry, the time next to "Parked" keeps counting for a car that stays awake, such as one with Sentry Mode on. It started again each time the widget stopped asking for data to let the car sleep, and again when it looked once more, so it never got past about 21 minutes. "Falling asleep" now shows how long the car has been parked, too.
- With Home Assistant, the time next to "Parked" counts from when the widget saw the car park or stop charging. It counted from when the car woke up, so a car parked a minute ago after a two-hour outing said "Parked · 2h". A car that is already parked when the widget starts shows no time until it has done something else.

## [1.13.0] - 2026-11-16

### Added

- While charging, the card says how much range the charge adds per hour, and whether the car is on a Supercharger or another DC fast charger, with the Tesla Fleet API, Teslemetry, Tessie and Home Assistant. On a DC charger it leaves out the current and voltage, which the car reports as about 0 A and a few volts there.
- Under the battery ring, the card says when the car is heating the battery, with the same sources.
- The Climate cell names Dog Mode, Camp Mode and Keep Climate, with the TeslaMate API too, and, with the Fleet API, Teslemetry, Tessie and Home Assistant, defrosting and cabin overheat protection. While the climate runs, it shows the temperature it's set to instead of "On".
- The footer says when a scheduled update will install, and about how long an installation has left, with the Fleet API, Teslemetry and Tessie.
- Hovering over the car shows the recommended tire pressure, with the same three sources.
- Tessie's saved locations count as geofences: the card names the one the car is at, and **Unlocked is OK at** takes their names. The widget asks Tessie for the car's location after each update, and keeps only the place's name.
- Hovering over the car names its trim, such as Model 3 Performance, and its wheels, such as Stiletto 20″, with every source but Home Assistant.
- The drawing gives a car that reports a spoiler, such as a Model 3 Performance, a black lip along the trunk lid's trailing edge, with the same sources.

## [1.12.0] - 2026-11-16

### Security

- The broker password is kept in the wallet, KWallet on Plasma or another Secret Service such as GNOME Keyring, through `secret-tool`, instead of in plain text in Plasma's settings. The widget hands it to `mosquitto_sub` through a pipe rather than on the command line, where other users of the computer could see it. Without `secret-tool` or a wallet, the password is kept as before, and the Connection page says so.
- The tokens are kept in the wallet too: the Fleet API's access and refresh tokens, including the ones the widget renews, and the Teslemetry, Tessie, TeslaMate API and Home Assistant tokens. If the wallet refuses renewed tokens, they're kept in the settings instead, since the old ones no longer work.

### Added

- A password and tokens that earlier versions saved in plain text move into the wallet the first time the widget starts with one. If the wallet stays locked, they stay where they are, and the Connection page offers to move them.
- When the wallet doesn't give the password or the tokens, the widget stops polling until you press Refresh or open the popup, so a closed wallet doesn't ask to be opened at every poll. Right after the settings change it tries once more first.

### Changed

- With the password in the wallet, the widget's `mosquitto_sub` no longer reads your own `~/.config/mosquitto_sub`.

## [1.11.1] - 2026-11-16

### Security

- The Tesla Fleet API source no longer sends tokens over plain HTTP. A custom URL or token server that uses `http://` is refused, with a message saying why, unless it's on this computer (`localhost`, `127.0.0.1` or `[::1]`), as a local proxy or `tools/fake-tesla-api.py` is. A token server typed without a scheme gets `https://`, as the custom URL already did.
- Error messages that quote a server or `mosquitto_sub`, and the car names that **Find Cars** shows, can no longer be read as markup by the settings page, so a server can't make it show images or links. Such messages are also kept to one line of at most 300 characters.
- Clicking the car's name only opens `http://` and `https://` addresses.
- `tools/tesla-login.py` no longer gives up when its sign-in listener gets a reply that belongs to another sign-in, such as a reloaded tab from an earlier run. It turns it away and keeps waiting. A browser that connects without sending anything can't hold it past its deadline, the page it shows isn't cached, and control characters in Tesla's replies are dropped before they reach the terminal.

### Fixed

- A Fleet API error whose `error` field isn't text no longer shows as "[object Object]".

## [1.11.0] - 2026-11-16

### Added

- Four more data sources, chosen under **Data source** on the Connection page:
  - **TeslaMate API** reads TeslaMate's values from TeslaMateApi over HTTP, so the widget doesn't need `mosquitto_sub` or a way to the MQTT broker.
  - **Teslemetry** reads the car from Teslemetry with its own long-lived token, the way the Fleet API source does, letting the car sleep.
  - **Tessie** reads the car's latest state from Tessie, which answers from its own copy, so asking never keeps the car awake.
  - **Home Assistant** reads the car's entities from Home Assistant's Tesla Fleet, Teslemetry or Tessie integration, and counts its zones as geofences.
- **Test Connection** and **Find Cars** work for each new source, and fill in the car ID, VIN or car.
- `tools/fake-tesla-api.py` also serves the scenario car as TeslaMateApi, Tessie and Home Assistant do.

### Changed

- Clicking the car's name, or the context menu entry, opens the data source's own page with Home Assistant, Teslemetry or Tessie. With TeslaMate it still opens TeslaMate's address from the Display settings.
- The card's placeholder and the Display page's hints name the chosen source.

## [1.10.0] - 2026-11-16

### Added

- `tools/tesla-login.py` gets the tokens for the Tesla Fleet API source. `register` registers your Fleet API app with Tesla for a region, and `login` signs in through Tesla's page in the browser and prints the region, tokens, client ID and VIN to paste into the widget's settings. The README walks through it.
- `tools/fake-tesla-api.py` also fakes Tesla's sign-in page and app registration, so the helper can be tried without Tesla.

## [1.9.0] - 2026-11-16

### Added

- The widget can read the car straight from the Tesla Fleet API, as well as from TeslaMate over MQTT. A new **Data source** setting chooses between them. The API source takes a region or a custom URL (for services that offer the same API), an access token and the car's VIN, and with a refresh token and client ID renews the access token itself. **Find Cars** lists the account's cars.
- With the API, the widget lets the car sleep: it never wakes the car, asks only for its state while it sleeps, and stops asking an idle car for its data for 21 minutes so it can fall asleep. Each request is billed, so the API has its own refresh settings, every 5 minutes and every 15 minutes while the car sleeps by default.
- `tools/fake-tesla-api.py` serves made-up Fleet API replies, to try the API source without a car.

## [1.8.0] - 2026-11-14

### Added

- The panel icon and the car in the card are drawn as a Model S, Model 3, Model X, Model Y or Cybertruck. A new **Model** setting chooses one, and by default follows the model TeslaMate reports.
- A Model X's rear doors lift like wings when they are open. On a Model S, X and Y the rear window opens with the trunk, as the hatch does, and the Cybertruck's trunk is the cover of its bed.

### Changed

- The cars are redrawn after the side and top views in Tesla's owner's manuals, with Tesla's dimensions. The Model 3 changed with the others: a rounder nose and tail, a windshield that bows forward, glass that narrows towards the tail with the side windows along it, and its own lights and mirrors.

## [1.7.1] - 2026-11-14

### Fixed

- Car names, places, navigation destinations and software versions that contain `<` or `&` are shown as written in the card and the panel tooltip, never as formatting.

### Added

- Dependabot keeps the GitHub Actions used by CI and releases up to date.

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

[Unreleased]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/v1.13.0...HEAD
[1.13.0]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/v1.12.0...v1.13.0
[1.12.0]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/v1.11.1...v1.12.0
[1.11.1]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/v1.11.0...v1.11.1
[1.11.0]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/v1.10.0...v1.11.0
[1.10.0]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/v1.8.0...v1.9.0
[1.7.1]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/moseph333/tesla-monitor-plasmoid/compare/4fc8407...v1.7.0
[1.6.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/4fc8407
[1.5.1]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/cad2fd9
[1.5.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/4a90dd5
[1.4.1]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/7e2bfd8
[1.4.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/0ce0db8
[1.3.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/c1b9728
[1.2.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/ea6d888
[1.1.0]: https://github.com/moseph333/tesla-monitor-plasmoid/commit/ff53763
