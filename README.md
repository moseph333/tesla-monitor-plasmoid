# Tesla Monitor

A KDE Plasma 6 widget that shows a Tesla's status from [TeslaMate](https://docs.teslamate.org) over MQTT. On the desktop it's a full card. In a panel it's a Model 3-shaped battery icon, with the battery percentage or the range beside it, that opens the card when clicked. It's drawn like Plasma's battery icon: a thin outline with a solid fill that grows from left to right, and a bolt while charging. The panel icon also works from the keyboard, where Space or Enter opens the card, and screen readers read out the same status as its tooltip.

The card shows:

- The car's name, what it's doing, the TeslaMate geofence it's in and for how long, such as "Parked · Home · 3h". If you set TeslaMate's address in the settings, clicking the name opens TeslaMate in your browser
- Battery level and range in a ring. A notch on the track marks the charge limit, and the track up to it is a shade stronger than beyond it. While charging, a bolt sits above the level and the stretch still to charge takes the ring's color and pulses slowly while the popup is open, and the card shows the power, the time left with when it'll be done, the energy added, current and voltage with the number of phases, and the current the car asks for when that's less than the charger offers. Otherwise it says whether the car is plugged in, finished charging, stopped early, waiting for a scheduled start, or plugged into a charger that has no power, and gives the charge limit with about how far a charge to it goes
- While driving, the power the battery gives, or takes back while regenerating. If you turn on navigation, also the destination, the time to arrival with any traffic delay, the distance left and the battery level on arrival
- How much of the battery is usable while it's cold
- Inside and outside temperature, climate and odometer
- A top-down drawing of the car in its own paint, lying on its side with its nose to the right so it fills the card, with each tire's pressure, each door and window, the trunk, frunk and charge port, the lock and Sentry. Open doors swing out, anything open turns orange, a low tire turns red, the charge cable shows while plugged in, and a red lens on the windshield means Sentry is on. Hover over the car to see the same status as text. The paint is the one TeslaMate reports. When it reports none, or one the widget doesn't know, the car is drawn in tints of your color scheme, which you can also choose in the settings
- One warning that lists everything that needs attention: open doors, windows, frunk, trunk, sunroof or charge port, the car unlocked with nobody inside, low tire pressure, service mode, and TeslaMate having trouble reaching the car. The popup is a little taller while it shows, so the car keeps its size. The panel icon's tooltip lists the same
- Software version, available updates and their download and install progress

It can also send desktop notifications when charging finishes or stops early, when something is left open or the car is unlocked with nobody inside, when a tire's pressure is low, and when a software update is available. See [Notifications](#notifications).

The widget runs `mosquitto_sub` every 15 seconds by default, and every 2 minutes while the car sleeps and the popup is closed, to read TeslaMate's retained messages from the broker. It never talks to the car. Opening the popup, or pressing the refresh button in its header, updates right away. If the broker stops answering, the card keeps the last data and fades it, the panel icon dims, and the card's footer and the icon's tooltip say when the data was last updated, with the day once that wasn't today.

## Requirements

- Plasma 6
- `mosquitto_sub`:
  - Fedora: `sudo dnf install mosquitto`
  - Debian and Ubuntu: `sudo apt install mosquitto-clients`
  - Arch: `sudo pacman -S mosquitto`
  - The snap isn't supported. It only provides `mosquitto.sub`, which the widget can't find.
  - TLS with the system's certificates needs mosquitto 2.0 or newer.
- KNotifications' QML module, `org.kde.notification`. Most distributions ship it with KNotifications. Where it's a separate package, install it, or the widget won't load
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
| Username, Password | A broker account, if the broker requires one. A password without a username isn't sent, since MQTT has no such login |
| Use TLS, CA file | For a broker that uses TLS. See [TLS](#tls) |
| Topic prefix | `teslamate/cars/1`, or `teslamate/<namespace>/cars/1` if TeslaMate sets `MQTT_NAMESPACE` |
| Every (under Refresh) | 15 seconds by default |
| While the car sleeps | 2 minutes by default. Used while the car is asleep or offline and the popup is closed. A widget on the desktop has no popup, so it uses this whenever the car sleeps. It never polls faster than **Every** |

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
| Car color | **The car's paint** by default: the drawing's body takes the color TeslaMate reports as `exterior_color`. **Theme colors** draws it in tints of your color scheme instead, which is also what you get when TeslaMate reports no paint or one the widget doesn't know |
| Show the destination and arrival while driving | Off by default. While the car follows a route, the card shows the destination, the time to arrival with any traffic delay, the distance left and the battery level on arrival. Needs TeslaMate 1.29 or newer |
| Unlocked is OK at | TeslaMate geofence names, separated by commas, such as `Home, Work`. There an unlocked car isn't shown as a warning or notified, for a garage or home where you leave it unlocked on purpose |
| TeslaMate | TeslaMate's web address, such as `http://teslamate.local:4000`. Clicking the car's name in the popup, or **Open TeslaMate** in the widget's context menu, opens it in your browser. `http://` is added if you leave it out |

**Notifications**

| Setting | Value |
| ------- | ----- |
| Notify when | Charging finishes, charging stops early or the charger loses power, something is left open, the car is unlocked with nobody inside, a tire's pressure is low, or a software update is available. All are on by default. See [Notifications](#notifications) |
| For at least | 10 minutes by default. How long something has to stay open, or the car unlocked with nobody inside, before the widget notifies |

Each copy of the widget keeps its own settings.

Plasma stores the password in plain text and the widget passes it to `mosquitto_sub` on the command line, so use a read-only broker account. The widget never uses the car's position (`latitude`, `longitude`, `location`, `heading`, `elevation`) or the older `active_route_*` topics, so the account can be denied those. It shows the navigation destination (`active_route`) only when **Show the destination and arrival while driving** is on, but it still receives that topic with everything else under the prefix, so deny it too if you don't use navigation.

## TLS

Turn on **Use TLS** for a broker that encrypts its connections. TLS brokers usually listen on port 8883, so the widget switches the port between 1883 and 8883 along with the checkbox, unless you've set a different one. With mosquitto 2.0 or newer, port 8883 always uses TLS.

- Leave **CA file** empty to trust the system's certificates. This needs mosquitto 2.0 or newer.
- For a broker with a self-signed certificate or one from a private CA, choose that CA's certificate, usually a `.pem` or `.crt` file, as the CA file.
- **Host** must be a name the broker's certificate lists, which is usually its host name rather than its IP address.

## Notifications

The widget sends a notification when:

- Charging finishes. A charge that adds less than 3% doesn't count, so the car topping itself up stays quiet.
- Charging stops before the limit, or the charger stops supplying power during a charge. The widget waits about 3 minutes in case the charge carries on, and tells you once per plug-in. Unplugging and waiting for a scheduled start never notify.
- A door, window, the frunk, trunk, sunroof or charge port is left open, or the car is unlocked with nobody inside, for 10 minutes (**For at least**) while nobody is in the car. Each notifies once, and again only after it has been closed or locked.
- A tire's pressure is low, or a software update is available.

Notifications are only for changes. Nothing is sent for what's already the case when the widget starts, after you change the connection settings, or after a long break in the data, such as while the computer sleeps. Plasma shows them as System Notifications, and clicking one opens the widget. Copies of the widget that show the same car, such as one in the panel and one on the desktop, send each notification once.

If you leave the car unlocked on purpose somewhere, such as in your garage at home, add that TeslaMate geofence to **Unlocked is OK at** on the Display page. The widget then neither warns nor notifies there.

## TeslaMate behavior

- TeslaMate creates its MQTT publishers only for cars that exist when it starts. Restart TeslaMate after adding a car, or the broker stays empty.
- After a restart, values appear on the car's next state change. Some, such as tire pressures, need the car to be awake.
- TeslaMate reports each door separately from 1.30 and each window from 4.1.1. With older versions it only says that some door or window is open, so the card outlines all four in orange and the doors don't swing out.
- Whether a charge finished, stopped early or has no power needs TeslaMate 1.28 or newer. Older versions only show whether the car is charging or plugged in.
- Navigation needs TeslaMate 1.29 or newer, which publishes `active_route`. The widget doesn't fall back to the older `active_route_destination`, which has no arrival details and reads `nil` between routes (TeslaMate 1.28.4 and 1.28.5 kept the last destination there instead).
- Update download and install progress, and service mode, need TeslaMate 4.1 or newer.
- TeslaMate 2.1 and newer don't retain `healthy`, so the widget only sees it when a poll happens to catch it, and keeps it for 10 minutes. The warning that TeslaMate is having trouble reaching the car can lag or be missed.
- From TeslaMate 4.4, values the car stops reporting disappear from the card.
- TeslaMate reports the paint as the car names it, such as `DeepBlue`, `PearlWhite` or `RedMulticoat`. The widget knows Tesla's paints by the words in those names and draws a close color, not the exact one. For any other name it uses theme colors.

## Development

Edit the files in `package/`, then:

```bash
make install   # build dist/tesla-monitor.plasmoid and install or upgrade it
make reload    # restart Plasma so the new QML loads
make test      # run the unit tests
```

`make reload` makes the panel and desktop blink, and it clears Plasma's notifications. Raise `Version` in `package/metadata.json` for each release.

The tests in `tests/` cover `logic.js` and `notifyhub.js` and need only Node.js 18 or newer. `logic.js` holds the widget's decisions and never calls `Qt` or `i18n()`, so Node can run it; the QML turns its results into words. Qt 6's `qmllint` catches QML syntax errors:

```bash
qmllint package/contents/ui/*.qml package/contents/config/*.qml
```

If it isn't on your `PATH`, look in Qt 6's `bin` folder, such as `/usr/lib/qt6/bin` or `/usr/lib64/qt6/bin`. Outside a Plasma session it can't find Plasma's and Kirigami's modules, so ignore its warnings about those.

### Fake TeslaMate data

`tools/fake-teslamate.sh` publishes made-up TeslaMate values to a broker, so you can try the widget without a car, and see states your car is rarely in. It needs `mosquitto_pub`, which comes with `mosquitto_sub`. Run a broker of your own, from the `mosquitto` package, so nothing lands on a real TeslaMate's topics:

```bash
mosquitto -p 1884 -v                            # in another terminal
tools/fake-teslamate.sh -p 1884 parked          # parked and locked, everything closed
tools/fake-teslamate.sh -p 1884 charging        # then whatever you want to see
```

Set the widget's host to `localhost` and its port to 1884. The values are retained, as TeslaMate's are, so the widget sees them on its next poll. Each scenario changes only its own values, so they combine, and `parked` puts everything back. Run the script without a scenario to see what each one does:

- `parked`, `asleep`, `driving`, `regen`, `route`, `noroute`
- `charging`, `complete`, `stopped`, `nopower`, `scheduled`
- `open`, `close`, `unlock`, `lock`, `present`, `away`, `home`
- `tires`, `tires-empty`, `update`, `downloading`, `installing`
- `cold`, `unhealthy`, `service`
- `car2` adds a second car for **Find Cars**, and `clear` removes everything the script published

`-h` and `-p` choose the broker's host and port, and `-t` the topic prefix, such as `teslamate/<namespace>/cars/1`.

Notifications are for changes, so run a scenario, let the widget poll, then run the next. `charging` and then `complete` notifies that charging finished, and `charging` and then `stopped` notifies about 3 minutes later. `parked` removes `healthy`, as TeslaMate 2.1 and newer don't retain it, so a warning from `unhealthy` stays on the card for 10 minutes.

`parked` also gives the fake car a Deep Blue paint. To see the drawing in another, publish that paint's name:

```bash
mosquitto_pub -p 1884 -r -t teslamate/cars/1/exterior_color -m PearlWhite
```

The card draws its own lock, Sentry and bolt signs instead of taking them from the icon theme, so they look the same in every theme. If you add a theme icon with `isMask: true`, use a `-symbolic` name. Some icon themes, such as WhiteSur, map plain names to full-color icons, which then render as a solid block.
