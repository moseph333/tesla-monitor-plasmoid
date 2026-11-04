# Tesla Monitor

A KDE Plasma 6 widget that shows a Tesla's status from [TeslaMate](https://docs.teslamate.org) over MQTT. On the desktop it's a full card. In a panel it's a Model 3-shaped battery icon and percentage that opens the card when clicked. It's drawn like Plasma's battery icon: a thin outline with a solid fill that grows from left to right, and a bolt while charging.

The card shows:

- Battery level, range and charge limit. While charging it shows the power, energy added, current and voltage with the number of phases, the current the car asks for when that's less than the charger offers, and the time left with when it'll be done. Otherwise it says whether the car is plugged in, finished charging, stopped early, waiting for a scheduled start, or plugged into a charger that has no power
- While driving, the power the battery gives, or takes back while regenerating
- How much of the battery is usable while it's cold
- Inside and outside temperature, climate and odometer
- A top-down drawing of the car with each tire's pressure, each door and window, the trunk, frunk and charge port, the lock and Sentry. Open doors swing out, anything open turns orange, the charge cable shows while plugged in, and a red camera on the windshield means Sentry is on. Hover over the car to see the same status as text
- One warning that lists everything that needs attention: open doors, windows, frunk, trunk, sunroof or charge port, the car unlocked with nobody inside, low tire pressure, service mode, and TeslaMate having trouble reaching the car. The panel icon's tooltip lists the same
- Software version, available updates and their download and install progress

The widget runs `mosquitto_sub` every 15 seconds by default and reads TeslaMate's retained messages from the broker. It never talks to the car.

## Requirements

- Plasma 6
- `mosquitto_sub`:
  - Fedora: `sudo dnf install mosquitto`
  - Debian and Ubuntu: `sudo apt install mosquitto-clients`
  - Arch: `sudo pacman -S mosquitto`
  - The snap isn't supported. It only provides `mosquitto.sub`, which the widget can't find.
  - TLS with the system's certificates needs mosquitto 2.0 or newer.
- TeslaMate with MQTT enabled, and a broker this machine can reach

## Install

```bash
make install
```

Then add **Tesla Monitor** to a panel or the desktop and open its settings.

**Connection**

| Setting | Value |
| ------- | ----- |
| Host, Port | Your MQTT broker. You can paste a URL such as `mqtts://user@broker:8883`, and the widget moves the port, TLS and username into their own fields |
| Username, Password | A broker account, if the broker requires one |
| Use TLS, CA file | For a broker that uses TLS. See [TLS](#tls) |
| Topic prefix | `teslamate/cars/1`, or `teslamate/<namespace>/cars/1` if TeslaMate sets `MQTT_NAMESPACE` |
| Refresh every | 15 seconds by default |

**Test Connection** tries the values on the page before you apply them, and says what went wrong if it can't read TeslaMate's data. **Find Cars** lists the cars TeslaMate publishes on the broker and fills in the topic prefix, or lets you choose when there are several.

**Display**

| Setting | Value |
| ------- | ----- |
| Distance, Temperature, Tire pressure | Automatic by default, which follows Measurement units in System Settings, Region & Language: miles, °F and psi for the US, miles, °C and psi for the UK, and kilometers, °C and bar otherwise. Each can be set on its own, and tire pressure can also be kPa. Speed uses the distance unit. A widget set up before 1.5 keeps the units it showed |
| Range | Rated (matches the car), estimated or ideal |
| Show text next to the icon | On by default. Turn it off to show only the car in the panel. Hovering over the car still shows the percentage and range |
| Text | What the panel shows next to the car: the battery percentage (the default), the range, or both |
| While charging, show the time to full | Off by default. While the car charges, the panel shows the time left to reach the charge limit, instead of the range when Text includes it |
| Right-hand drive | Off by default. TeslaMate names doors and windows by driver and passenger side, so turn this on if the steering wheel is on the right |
| Unlocked is OK at | TeslaMate geofence names, separated by commas, such as `Home, Work`. There an unlocked car isn't shown as a warning, for a garage or home where you leave it unlocked on purpose |

Each copy of the widget keeps its own settings.

Plasma stores the password in plain text and the widget passes it to `mosquitto_sub` on the command line, so use a read-only broker account. The widget doesn't read GPS or route topics, so that account can be denied them.

## TLS

Turn on **Use TLS** for a broker that encrypts its connections. TLS brokers usually listen on port 8883, so the widget switches the port between 1883 and 8883 along with the checkbox, unless you've set a different one. With mosquitto 2.0 or newer, port 8883 always uses TLS.

- Leave **CA file** empty to trust the system's certificates. This needs mosquitto 2.0 or newer.
- For a broker with a self-signed certificate or one from a private CA, choose that CA's certificate, usually a `.pem` or `.crt` file, as the CA file.
- **Host** must be a name the broker's certificate lists, which is usually its host name rather than its IP address.

## TeslaMate behavior

- TeslaMate creates its MQTT publishers only for cars that exist when it starts. Restart TeslaMate after adding a car, or the broker stays empty.
- After a restart, values appear on the car's next state change. Some, such as tire pressures, need the car to be awake.
- TeslaMate reports each door separately from 1.30 and each window from 4.1.1. With older versions it only says that some door or window is open, so the card outlines all four in orange and the doors don't swing out.
- Whether a charge finished, stopped early or has no power needs TeslaMate 1.28 or newer. Older versions only show whether the car is charging or plugged in.
- Update download and install progress, and service mode, need TeslaMate 4.1 or newer.
- TeslaMate 2.1 and newer don't retain `healthy`, so the widget only sees it when a poll happens to catch it, and keeps it for 10 minutes. The warning that TeslaMate is having trouble reaching the car can lag or be missed.
- From TeslaMate 4.4, values the car stops reporting disappear from the card.

## Development

Edit the files in `package/`, then:

```bash
make install   # build dist/tesla-monitor.plasmoid and install or upgrade it
make reload    # restart Plasma so the new QML loads
```

`make reload` makes the panel and desktop blink, and it clears Plasma's notifications. Raise `Version` in `package/metadata.json` for each release.

With `isMask: true`, use `-symbolic` icon names. Some icon themes, such as WhiteSur, map plain names to full-color icons, which then render as a solid block.
