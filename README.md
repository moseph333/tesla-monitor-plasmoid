# Tesla Monitor

A KDE Plasma 6 widget that shows a Tesla's status from [TeslaMate](https://docs.teslamate.org) over MQTT. On the desktop it's a full card. In a panel it's a Model 3-shaped battery icon and percentage that opens the card when clicked. It's drawn like Plasma's battery icon: a thin outline with a solid fill that grows from left to right, and a bolt while charging.

The card shows:

- Battery level, range and charge limit, plus power, energy added and time left while charging
- Inside and outside temperature, climate and odometer
- A top-down drawing of the car with each tire's pressure, each door and window, the trunk, frunk and charge port, the lock and Sentry. Open doors swing out, anything open turns orange, the charge cable shows while plugged in, and a red camera on the windshield means Sentry is on. Hover over the car to see the same status as text
- Software version and available updates

The widget runs `mosquitto_sub` every 15 seconds by default and reads TeslaMate's retained messages from the broker. It never talks to the car.

## Requirements

- Plasma 6
- `mosquitto_sub`:
  - Fedora: `sudo dnf install mosquitto`
  - Debian and Ubuntu: `sudo apt install mosquitto-clients`
  - Arch: `sudo pacman -S mosquitto`
  - The snap isn't supported. It only provides `mosquitto.sub`, which the widget can't find.
- TeslaMate with MQTT enabled, and a broker this machine can reach

## Install

```bash
make install
```

Then add **Tesla Monitor** to a panel or the desktop and open its settings:

| Setting | Value |
| ------- | ----- |
| Host, Port | Your MQTT broker |
| Username, Password | A broker account, if the broker requires one |
| Topic prefix | `teslamate/cars/1`, or `teslamate/<namespace>/cars/1` if TeslaMate sets `MQTT_NAMESPACE` |
| Show battery percentage | On by default. Turn it off to show only the car in the panel. Hovering over the car still shows the percentage |
| Right-hand drive | Off by default. TeslaMate names doors and windows by driver and passenger side, so turn this on if the steering wheel is on the right |

Each copy of the widget keeps its own settings.

Plasma stores the password in plain text and the widget passes it to `mosquitto_sub` on the command line, so use a read-only broker account. The widget doesn't read GPS or route topics, so that account can be denied them.

## TeslaMate behavior

- TeslaMate creates its MQTT publishers only for cars that exist when it starts. Restart TeslaMate after adding a car, or the broker stays empty.
- After a restart, values appear on the car's next state change. Some, such as tire pressures, need the car to be awake.
- TeslaMate reports each door separately from 1.30 and each window from 4.1.1. With older versions it only says that some door or window is open, so the card outlines all four in orange and the doors don't swing out.

## Development

Edit the files in `package/`, then:

```bash
make install   # build dist/tesla-monitor.plasmoid and install or upgrade it
make reload    # restart Plasma so the new QML loads
```

`make reload` makes the panel and desktop blink, and it clears Plasma's notifications. Raise `Version` in `package/metadata.json` for each release.

With `isMask: true`, use `-symbolic` icon names. Some icon themes, such as WhiteSur, map plain names to full-color icons, which then render as a solid block.
