import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.notification

import "logic.js" as Logic
import "models.js" as Models
import "notifyhub.js" as Hub

PlasmoidItem {
    id: root

    readonly property var cfg: Plasmoid.configuration
    // The same test the command builder uses, so a host such as "mqtt://" can't leave the
    // card waiting for data that no command will fetch.
    readonly property bool configured: Logic.parseBrokerHost(cfg.brokerHost).host !== ""
    // One value for both the subscription and stripping topics, so the two can't disagree.
    readonly property string prefix: cfg.topicPrefix.trim().replace(/\/+$/, "") || "teslamate/cars/1"
    // Automatic follows Measurement units in Region & Language, which Qt reads from the locale.
    readonly property var units: Logic.resolveUnits(cfg.distanceUnit, cfg.temperatureUnit, cfg.pressureUnit,
                                                    Qt.locale().measurementSystem)

    // Raw TeslaMate values keyed by topic suffix
    property var car: ({})
    property bool hasData: false
    property string errorText: ""
    property var lastUpdated: null
    property real now: Date.now()
    // When healthy last arrived, so its carried-over value can expire.
    property var healthySeenAt: null
    // Only a refresh someone asked for shows a spinner, so the regular polls stay quiet.
    property bool userRefreshing: false
    // What Logic.notifyStep() knew after the last poll, or null to start over.
    property var notifyState: null
    // The car, as notifyhub.js knows it, so copies of the widget that show it share claims.
    readonly property string notifySource: {
        const b = Logic.parseBrokerHost(cfg.brokerHost)
        return b.host.toLowerCase() + ":" + (b.port || cfg.brokerPort) + "|" + prefix
    }

    // A card on the desktop counts as closed, so it polls at the idle rate while the car
    // sleeps.
    readonly property bool popupOpen: expanded && Plasmoid.formFactor !== PlasmaCore.Types.Planar
    readonly property int pollMs: Logic.pollIntervalMs(cfg.refreshSeconds, cfg.idleRefreshSeconds, carState,
                                                       hasData, popupOpen)
    // The last poll failed and the data is older than a minute, or two intervals while
    // polling slowly, so one missed poll of a sleeping car doesn't count.
    readonly property bool stale: hasData && errorText !== "" && lastUpdated !== null
                                  && now - lastUpdated.getTime() > Math.max(60000, 2 * pollMs)

    // ---------- derived values ----------

    readonly property string carState: car.state || ""
    readonly property real level: Logic.num(car, "battery_level") ?? -1
    readonly property real limit: Logic.num(car, "charge_limit_soc") ?? -1
    readonly property real chargerKw: Logic.num(car, "charger_power") ?? 0
    readonly property string chargeStatus: Logic.chargeStatus(car)
    // Starting counts, so the icon and the ring don't wait for the charger to ramp up.
    readonly property bool charging: chargeStatus === "charging" || chargeStatus === "starting"
    readonly property bool driving: Logic.isDriving(car)
    readonly property var hoursToFull: Logic.num(car, "time_to_full_charge")
    // kW, negative while regenerating. TeslaMate's docs say watts, but it publishes kW.
    readonly property var power: Logic.num(car, "power")
    // Only when turned on, since it names where the car is going, and only while driving, so
    // a route still retained from an earlier drive doesn't show on a parked car.
    readonly property var route: cfg.showNavigation && driving ? Logic.activeRoute(car) : null
    readonly property var rangeKm: Logic.num(car, ["rated_battery_range_km", "est_battery_range_km", "ideal_battery_range_km"][cfg.rangeType] || "rated_battery_range_km")
    readonly property var okGeofences: Logic.geofenceList(cfg.unlockedOkGeofences)
    readonly property var attentionItems: Logic.attention(car, okGeofences)
    readonly property var attentionLines: texts.attentionLines(attentionItems)
    readonly property var usableCold: Logic.usableIfCold(car)
    // Not "update", which would hide Item's update() method.
    readonly property var softwareUpdate: Logic.updateProgress(car)
    // "" while no address is set, which hides the link and the context menu entry.
    readonly property string teslamateUrl: Logic.normalizeUrl(cfg.teslamateUrl)
    // The body color for the car drawing, or "" for theme colors: when that's the setting,
    // or TeslaMate reports no paint the widget knows.
    readonly property string paint: cfg.carColor === 0 ? Logic.paintColor(car.exterior_color) : ""
    // Which car the panel icon and the card draw: the settings' choice, or the model
    // TeslaMate reports.
    readonly property string carModel: Models.modelKey(cfg.carModel, car.model)

    readonly property string distUnit: units.distance
    readonly property string tempUnit: "°" + units.temperature
    readonly property string pressUnit: units.pressure

    // Whole units, except that keepTenths keeps one decimal below 10, for a distance such as
    // what's left of a route, where "0 km" would say nothing.
    function fmtDistance(km, keepTenths) {
        const d = Logic.distance(km, units.distance)
        if (d === null) return "—"
        const digits = keepTenths && d < 10 ? 1 : 0
        return (digits ? d : Math.round(d)).toLocaleString(Qt.locale(), "f", digits) + " " + distUnit
    }
    // A whole number with a minus sign (U+2212) that is as wide as the digits, unlike a
    // hyphen. Rounded before the sign is chosen, so a small negative value can't show as "−0".
    function signed(n) {
        const r = Math.round(n)
        return (r < 0 ? "−" : "") + Math.abs(r)
    }
    function fmtTemp(c) {
        const t = Logic.temperature(c, units.temperature)
        return t === null ? "—" : signed(t) + tempUnit
    }
    function fmtSpeed(kmh) {
        const v = Logic.distance(kmh, units.distance)
        return v === null ? "" : Math.round(v) + (units.distance === "mi" ? " mph" : " km/h")
    }
    // A tenth of a bar matters, but psi and kPa are read in whole numbers. The tenth takes
    // the locale's decimal separator, as the other numbers on the card do. The card shows
    // the value and the unit in different sizes; a notification takes the text.
    function tire(pos) {
        const p = Logic.pressure(Logic.num(car, "tpms_pressure_" + pos), units.pressure)
        const value = p === null ? "—"
            : String(units.pressure === "bar" ? p.toLocaleString(Qt.locale(), "f", 1) : Math.round(p))
        return {
            value: value,
            unit: p === null ? "" : pressUnit,
            text: p === null ? "—" : value + " " + pressUnit,
            warn: Logic.bool(car, "tpms_soft_warning_" + pos)
        }
    }
    function fmtPower(kw) {
        return signed(kw) + " kW"
    }

    // The text next to the panel icon. While charging, the time to full can take the
    // range's place, since it's what matters then.
    function panelLabel() {
        const parts = []
        if (cfg.panelText !== 1 && level >= 0) parts.push(level + "%")
        const toFull = charging && cfg.panelChargingTime ? Logic.formatHours(hoursToFull) : ""
        if (toFull) parts.push(toFull)
        else if (cfg.panelText !== 0 && rangeKm !== null) parts.push(fmtDistance(rangeKm))
        return parts.join(" · ")
    }

    function stateLabel() {
        switch (carState) {
        case "driving": {
            const s = fmtSpeed(Logic.num(car, "speed"))
            return s ? i18n("Driving · %1", s) : i18n("Driving")
        }
        case "charging": return i18n("Charging")
        case "asleep": return i18n("Asleep")
        case "offline": return i18n("Offline")
        case "updating":
            return softwareUpdate.percent !== null ? i18n("Installing update · %1%", Math.round(softwareUpdate.percent))
                                                   : i18n("Installing update")
        case "suspended": return i18n("Falling asleep")
        case "online": {
            const shift = car.shift_state || ""
            return (shift === "D" || shift === "R") ? i18n("Driving") : i18n("Parked")
        }
        default: return carState ? carState : i18n("Unknown")
        }
    }

    // The locale's short time, "11:40 PM" or "23:40". Qt.formatTime(t, Locale.ShortFormat)
    // would read the enum as Qt.ISODate and give "23:40:00".
    function shortTime(d) {
        return d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
    }

    // A time that may be days away, such as a scheduled charge, so it names the weekday
    // when it isn't today: "11:40 PM" or "Sat 7:00 AM".
    function clock(ms) {
        const d = new Date(ms)
        const time = shortTime(d)
        if (d.toDateString() === new Date().toDateString()) return time
        return Qt.locale().dayName(d.getDay(), Locale.ShortFormat) + " " + time
    }

    // The charge port's status for the card while it isn't charging.
    function chargeStatusText() {
        switch (chargeStatus) {
        case "complete": return i18n("Charging complete")
        case "stopped": return i18n("Charging stopped")
        case "scheduled": return i18n("Charging starts at %1", clock(Date.parse(car.scheduled_charging_start_time)))
        case "nopower": return i18n("Plugged in, charger has no power")
        case "plugged": return i18n("Plugged in")
        case "unplugged": return i18n("Not plugged in")
        default: return ""
        }
    }

    // The charging block's figure. The charger reports no power yet while it starts, and
    // current × voltage stands in when it reports 0 kW, as it can for a slow charge.
    function chargePowerText() {
        if (chargeStatus === "starting") return i18n("Starting…")
        if (chargerKw > 0) return chargerKw + " kW"
        const amps = Logic.num(car, "charger_actual_current")
        const volts = Logic.num(car, "charger_voltage")
        if (amps > 0 && volts > 0) return (amps * volts / 1000).toLocaleString(Qt.locale(), "f", 1) + " kW"
        return i18n("Charging")
    }

    // How long the charge still takes: "1h 30m to 80%", or "1h 30m left" while the car
    // reports no limit to name. "" when it doesn't say how long.
    function chargeRemainingText() {
        const t = Logic.formatHours(hoursToFull)
        if (!t) return ""
        return limit >= 0 ? i18n("%1 to %2%", t, limit) : i18nc("how long a charge still takes", "%1 left", t)
    }

    // While charging: when the limit is reached, on the line after how long that takes.
    // The car's estimate counts from when it was published, which the last poll is nearest
    // to, so the time doesn't creep later while data is old.
    function chargeDoneText() {
        if (!chargeRemainingText() || !lastUpdated) return ""
        return i18nc("follows how long a charge still takes", "done by %1",
                     clock(lastUpdated.getTime() + hoursToFull * 3600000))
    }

    // While charging: the energy added so far and what the charger supplies.
    function chargeSupplyText() {
        const parts = []
        const added = Logic.num(car, "charge_energy_added")
        if (added !== null) parts.push("+" + added.toLocaleString(Qt.locale(), "f", 1) + " kWh")
        const amps = Logic.num(car, "charger_actual_current")
        const volts = Logic.num(car, "charger_voltage")
        if (amps !== null && volts !== null) {
            parts.push(amps + " A", volts + " V")
            const phases = Logic.showPhases(car)
            // ki18n takes the plural form from an integer only, and a number read from a
            // payload is a real even when it's whole.
            if (phases !== null) parts.push(i18np("%1 phase", "%1 phases", phases | 0))
        }
        return parts.join(" · ")
    }

    // The car asks for less than the charger offers when its charge current has been
    // turned down, which explains a slow charge.
    function chargeRequestText() {
        const request = Logic.num(car, "charge_current_request")
        const requestMax = Logic.num(car, "charge_current_request_max")
        return request !== null && requestMax !== null && request < requestMax
            ? i18n("Requested %1 of %2 A", request, requestMax) : ""
    }

    // On a route: when the car arrives, and how much of that is traffic.
    function routeArrivalText() {
        const t = route !== null && route.minutes !== null ? Logic.formatHours(route.minutes / 60) : ""
        if (!t) return ""
        const arriving = i18n("Arriving in %1", t)
        return route.trafficMinutes >= 1
            ? arriving + " · " + i18n("+%1 traffic", Logic.formatHours(route.trafficMinutes / 60)) : arriving
    }

    // On a route: how far it still is, and the battery level the car expects to arrive with.
    function routeRemainingText() {
        if (route === null) return ""
        const parts = []
        if (route.km !== null) parts.push(i18n("%1 to go", fmtDistance(route.km, true)))
        // Negative when the battery won't last as far as the destination.
        if (route.energyAtArrival !== null) parts.push(i18n("%1% on arrival", signed(route.energyAtArrival)))
        return parts.join(" · ")
    }

    // The charge limit, with the range a charge to it gives when that can be worked out.
    function limitText() {
        if (limit < 0) return ""
        const parts = [i18n("Limit %1%", limit)]
        if (limit > 0 && level > 0 && rangeKm !== null)
            parts.push(i18nc("the range a charge to the limit gives", "about %1",
                             fmtDistance(rangeKm / level * limit)))
        return parts.join(" · ")
    }

    // When a scheduled charge starts. The status line already says so while the car waits
    // for it.
    function scheduleText() {
        if (chargeStatus === "scheduled") return ""
        const t = Date.parse(car.scheduled_charging_start_time || "")
        return isNaN(t) ? "" : i18n("Scheduled %1", shortTime(new Date(t)))
    }

    // The update's status in the footer.
    function updateText() {
        const v = car.update_version || ""
        switch (softwareUpdate.phase) {
        case "downloading": {
            const p = softwareUpdate.percent !== null ? Math.round(softwareUpdate.percent) : 0
            return v ? i18n("Downloading %1 · %2%", v, p) : i18n("Downloading update · %1%", p)
        }
        case "installing":
            return v ? i18n("Installing %1", v) : i18n("Installing update")
        default:
            return v ? i18n("%1 available", v) : i18n("Update available")
        }
    }

    // When the data on the card arrived, for the footer: "Updated 2:30 PM", or "Updated Mon
    // 2:30 PM" once that was not today.
    function updatedText(time) {
        return i18n("Updated %1", clock(time.getTime()))
    }

    // The browser takes over, so the popup closes rather than stay open behind it.
    function openTeslaMate() {
        if (!teslamateUrl) return
        Qt.openUrlExternally(teslamateUrl)
        expanded = false
    }

    // ---------- plasmoid setup ----------

    Plasmoid.icon: Logic.batteryIcon(level >= 0 ? level : null, charging)
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation

    toolTipMainText: car.display_name || i18n("Tesla")
    // Car names, places and errors come from MQTT; show them as written, never as markup.
    toolTipTextFormat: Text.PlainText
    toolTipSubText: {
        if (!configured) return i18n("Not configured")
        if (!hasData) return errorText || i18n("Connecting…")
        let s = stateLabel()
        if (level >= 0) s += " · " + level + "% · " + fmtDistance(rangeKm)
        const remaining = chargeRemainingText()
        if (charging && remaining) s += " · " + remaining
        // Every attention line, since the panel icon has no other way to show them.
        const lines = [s].concat(attentionLines)
        if (stale)
            lines.push(i18n("Not updated since %1. %2", lastUpdated.toLocaleString(Qt.locale(), Locale.ShortFormat), errorText))
        return lines.join("\n")
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh Now")
            icon.name: "view-refresh"
            onTriggered: root.refresh(true)
        },
        PlasmaCore.Action {
            text: i18n("Open TeslaMate")
            icon.name: "internet-web-browser"
            visible: root.teslamateUrl !== ""
            onTriggered: root.openTeslaMate()
        }
    ]

    // ---------- MQTT via mosquitto_sub ----------
    // TeslaMate publishes every value except healthy as a retained message, so a
    // short-lived subscriber receives a full snapshot immediately and exits after -W seconds.

    function connectionOptions(topics, wait) {
        return {
            host: cfg.brokerHost,
            port: cfg.brokerPort,
            user: cfg.brokerUser,
            password: cfg.brokerPassword,
            tls: cfg.useTls,
            caFile: cfg.caFile,
            topics: topics,
            wait: wait
        }
    }

    // manual is true when someone asked, which shows a spinner until the result arrives. If a
    // poll is already running, its result is the one they get.
    function refresh(manual) {
        if (!configured) return
        if (manual) userRefreshing = true
        if (fetch.busy) return
        if (!fetch.run(connectionOptions([prefix + "/#"], 2))) userRefreshing = false
    }

    function applyResult(out, err) {
        userRefreshing = false
        now = Date.now()
        const parsed = Logic.parseMqtt(out, prefix)
        if (Object.keys(parsed).length === 0) {
            errorText = err || i18n("No TeslaMate data on %1/#. Check the topic prefix and that MQTT is enabled in TeslaMate.", prefix)
        } else {
            // TeslaMate 2.1 and newer don't retain healthy, so it's only in the polls that
            // happen to catch it. Its last value stays for 10 minutes.
            const h = Logic.carryHealthy(parsed.healthy, car.healthy, healthySeenAt, now, 600000)
            if (h.value !== undefined) parsed.healthy = h.value
            healthySeenAt = h.seenAt
            car = parsed
            hasData = true
            errorText = ""
            lastUpdated = new Date()
            processNotifications()
        }
    }

    MqttFetch {
        id: fetch
        onFinished: (out, err) => root.applyResult(out, err)
    }

    Texts { id: texts }

    // A new interval restarts the countdown, so the rate changes as soon as the car falls
    // asleep or the popup opens.
    Timer {
        interval: root.pollMs
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    // Opening the popup shows fresh data, which matters most while polling slowly. Inside
    // this handler, bindings on expanded such as popupOpen may not have updated yet, so it
    // reads the signal's argument instead.
    onExpandedChanged: (expanded) => {
        if (expanded && Plasmoid.formFactor !== PlasmaCore.Types.Planar && configured
            && (!lastUpdated || Date.now() - lastUpdated.getTime() > 5000))
            refresh(false)
    }

    // Keep "asleep for 3h" ticking between polls.
    Timer {
        interval: 60000
        running: root.hasData
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // The connection settings the data was asked with.
    property string connectionSeen: ""
    function connectionNow() {
        return JSON.stringify([cfg.brokerHost, cfg.brokerPort, cfg.brokerUser, cfg.brokerPassword,
                               cfg.topicPrefix, cfg.useTls, cfg.caFile])
    }

    Connections {
        target: Plasmoid.configuration
        // Only connection settings need fresh data. The display settings (units, range type,
        // right-hand drive, panel text) update through their bindings. Plasma sends
        // valueChanged for every key when the configuration is read again, whatever was
        // changed, so this goes by the values: a key that kept its value must not throw
        // away the data and poll again.
        function onValueChanged(key) {
            if (["brokerHost", "brokerPort", "brokerUser", "brokerPassword", "topicPrefix", "useTls", "caFile"].indexOf(key) < 0)
                return
            const now = root.connectionNow()
            if (now === root.connectionSeen) return
            root.connectionSeen = now
            configSettle.restart()
        }
    }

    Timer {
        id: configSettle
        interval: 300
        onTriggered: {
            root.car = {}
            root.hasData = false
            root.errorText = ""
            root.healthySeenAt = null
            root.userRefreshing = false
            // Another broker or car starts over, so what it already shows isn't news.
            root.notifyState = null
            fetch.cancel()
            root.refresh(false)
        }
    }

    Component.onCompleted: {
        connectionSeen = connectionNow()
        // 1.5 replaced the imperial checkbox with a setting for each unit. This keeps what an
        // existing widget showed, once; libplasma saves the new values a moment later.
        const m = Logic.unitMigration(cfg.unitsMigrated, cfg.brokerHost, cfg.imperial)
        if (m) for (const k in m) Plasmoid.configuration[k] = m[k]
    }

    // ---------- notifications ----------

    // After every poll that got data. The state moves on even while a notification is
    // turned off, so turning it on later doesn't bring up something old.
    function processNotifications() {
        const r = Logic.notifyStep(notifyState, car, Date.now(), {
            leftOpenMs: cfg.leftOpenMinutes * 60000,
            // Several polls at the slower rate, so only something like a suspend or a broker
            // outage counts as a gap that starts over.
            staleMs: Math.max(900000, 3000 * Math.max(cfg.refreshSeconds, cfg.idleRefreshSeconds)),
            okGeofences: okGeofences
        })
        notifyState = r.state
        // What's fine again ends its claim for every copy, so the next time is news.
        for (const key of r.released) Hub.release(notifySource + "|" + key)
        for (const e of r.events) sendNotification(e)
    }

    function sendNotification(e) {
        const wanted = {
            chargeComplete: cfg.notifyChargeComplete,
            chargeStopped: cfg.notifyChargeStopped,
            chargerNoPower: cfg.notifyChargeStopped,
            leftOpen: cfg.notifyLeftOpen,
            unlocked: cfg.notifyUnlocked,
            tires: cfg.notifyTires,
            update: cfg.notifyUpdates
        }
        if (!wanted[e.type]) return
        // Every copy of the widget that shows this car sees the event on its own poll, and
        // only the first to claim each part of it sends that part.
        const at = Date.now()
        const mine = Logic.claimEvent(e, (key, windowMs) => Hub.claim(notifySource + "|" + key, at, windowMs))
        if (!mine) return
        const content = notificationContent(mine, car.display_name || i18n("Tesla"))
        if (!content) return
        const note = notificationComponent.createObject(root, {
            title: content.title,
            text: Logic.escapeMarkup(content.body),
            iconName: content.icon
        })
        if (note) note.sendEvent()
    }

    // The title, body and icon for an event from Logic.notifyStep(). A body says less when
    // a value is missing, rather than leave a gap.
    function notificationContent(e, name) {
        const minutes = cfg.leftOpenMinutes
        switch (e.type) {
        case "chargeComplete":
            return {
                title: i18n("%1 finished charging", name),
                body: e.level === null ? i18n("Charging is complete.")
                    : rangeKm !== null ? i18n("Charged to %1% (%2).", e.level, fmtDistance(rangeKm))
                    : i18n("Charged to %1%.", e.level),
                icon: Logic.batteryIcon(e.level, false)
            }
        case "chargeStopped":
            return {
                title: i18n("%1 stopped charging", name),
                body: e.level === null ? i18n("Charging stopped before the limit.")
                    : e.limit !== null ? i18n("Stopped at %1%, below the %2% limit.", e.level, e.limit)
                    : i18n("Stopped at %1%.", e.level),
                icon: Logic.batteryIcon(e.level, false)
            }
        case "chargerNoPower":
            return {
                title: i18n("%1 can't charge", name),
                body: e.level === null ? i18n("The charger stopped supplying power.")
                    : i18n("The charger stopped supplying power at %1%.", e.level),
                icon: "dialog-warning"
            }
        case "leftOpen":
            return {
                title: i18n("%1 needs attention", name),
                body: texts.attentionLines(e.items)
                    .concat(i18np("Like this for %1 minute.", "Like this for %1 minutes.", minutes)).join("\n"),
                icon: "dialog-warning"
            }
        case "unlocked":
            return {
                title: i18n("%1 is unlocked", name),
                body: i18np("Nobody has been inside for %1 minute.", "Nobody has been inside for %1 minutes.", minutes),
                icon: "object-unlocked"
            }
        case "tires":
            return {
                title: i18n("%1 has low tire pressure", name),
                body: i18n("Check %1.", e.items.map(pos => {
                    const pressure = tire(pos).text
                    return pressure === "—" ? texts.tireName(pos)
                        : i18nc("tire position (pressure)", "%1 (%2)", texts.tireName(pos), pressure)
                }).join(", ")),
                icon: "dialog-warning"
            }
        case "update":
            return {
                title: i18n("Software update for %1", name),
                body: e.version ? i18n("Version %1 is available.", e.version) : i18n("An update is available."),
                icon: "system-software-update"
            }
        }
        return null
    }

    // One object per notification, which deletes itself once Plasma is done with it.
    // Plasma drops a notification without a componentName, so it goes out as Plasma's own.
    Component {
        id: notificationComponent

        Notification {
            componentName: "plasma_workspace"
            eventId: "notification"
            urgency: Notification.NormalUrgency
            autoDelete: true
            defaultAction: NotificationAction {
                label: i18n("Show")
                onActivated: root.expanded = true
            }
        }
    }

    // ---------- panel ----------

    // Behaves like Plasma's default panel icon, for the mouse, the keyboard and screen readers.
    compactRepresentation: MouseArea {
        id: compact

        readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        // Pressing the icon while the popup is open takes focus from the popup, which closes
        // it before the click arrives. The click goes by the state at the press, or it would
        // open the popup again straight away.
        property bool wasExpanded: false

        Layout.minimumWidth: horizontal ? row.implicitWidth : -1
        hoverEnabled: true
        activeFocusOnTab: true
        onPressed: wasExpanded = root.expanded
        onClicked: root.expanded = !wasExpanded

        Keys.onPressed: (event) => {
            switch (event.key) {
            case Qt.Key_Space:
            case Qt.Key_Enter:
            case Qt.Key_Return:
            case Qt.Key_Select:
                Plasmoid.activated()
                // Taken here, so a system tray holding the widget doesn't act on it as well.
                event.accepted = true
                break
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: Plasmoid.title
        // The tooltip, which is all the icon has to say.
        Accessible.description: root.toolTipMainText + "; " + root.toolTipSubText
        Accessible.onPressAction: Plasmoid.activated()

        RowLayout {
            id: row
            anchors.centerIn: parent
            height: parent.height
            spacing: Kirigami.Units.smallSpacing
            // Dimmed while the data is old, so a level from hours ago doesn't pass for now.
            opacity: root.stale ? 0.5 : 1

            CarBattery {
                // Plasma's small icon size, so it sits near the system tray's battery icon (whose
                // battery shape is 12 px tall) instead of growing with the panel. Thinner panels
                // and vertical panels shrink it to fit.
                readonly property real fitHeight: Math.min(Kirigami.Units.iconSizes.small,
                                                           compact.horizontal ? compact.height : compact.width / aspect)

                Layout.preferredHeight: fitHeight
                Layout.preferredWidth: fitHeight * aspect
                model: root.carModel
                value: root.level >= 0 ? root.level / 100 : -1
                charging: root.charging
                active: compact.containsMouse
            }

            PlasmaComponents3.Label {
                visible: compact.horizontal && root.cfg.showPanelPercentage && text !== ""
                text: root.panelLabel()
                font.features: { "tnum": 1 }
            }
        }
    }

    // ---------- desktop / popup ----------

    fullRepresentation: Item {
        // What every row but the car's needs, with the margins around them. Wrapped lines
        // make the rows taller at a narrow width, and this follows them.
        readonly property real rowsHeight: content.implicitHeight - carStatus.implicitHeight
                                           + 2 * content.anchors.margins

        // A message that needs attention makes the popup taller rather than the car
        // smaller: one line of it, with its frame and the space before it, is three grid
        // units high. This goes by whether there is one and not by its height, which
        // Kirigami animates. Rows that need more than usual, as they do in a larger font
        // or with a second line in the footer, make the popup taller by as much, so the
        // car keeps its width: 10.5 grid units is nearly what the rows of a parked card
        // leave it in the 27, and still leaves a card with a two-line message at its 30.
        readonly property real popupHeight: Math.max(Kirigami.Units.gridUnit * (root.attentionLines.length > 0 ? 30 : 27),
                                                     rowsHeight + Kirigami.Units.gridUnit * 10.5)

        Layout.preferredWidth: Kirigami.Units.gridUnit * 21
        // A card on the desktop keeps one height to ask for: Plasma lets a widget there
        // grow to a larger one, and never shrinks it again.
        Layout.preferredHeight: Plasmoid.formFactor === PlasmaCore.Types.Planar ? Kirigami.Units.gridUnit * 27
                                                                                : popupHeight
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        // Room for every row at its own height and the car drawing at its smallest, so an
        // attention message or extra charging lines can't push the drawing and the footer
        // out of the bottom of the card.
        // In the popup this stops at the height the popup has without tall rows. For a
        // moment after a message appears its text is wrapped a word to a line, and Plasma
        // makes a popup as tall as its minimum but never shorter again when that falls.
        Layout.minimumHeight: Math.max(Kirigami.Units.gridUnit * 20,
                                       Plasmoid.formFactor === PlasmaCore.Types.Planar
                                       ? rowsHeight + carStatus.Layout.minimumHeight
                                       : Math.min(rowsHeight + carStatus.Layout.minimumHeight,
                                                  Kirigami.Units.gridUnit * (root.attentionLines.length > 0 ? 30 : 27)))

        // Created here rather than on the root item, which lives in the panel: the card's
        // colors have to be the popup's.
        Look { id: look }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: !root.configured
            iconName: "battery-080"
            text: i18n("Connect to TeslaMate")
            explanation: root.cfg.brokerHost.trim() !== ""
                ? i18n("The broker host isn't valid. Check it in the widget settings.")
                : i18n("Add your MQTT broker in the widget settings.")
            helpfulAction: QQC2.Action {
                text: i18n("Configure…")
                icon.name: "configure"
                onTriggered: Plasmoid.internalAction("configure").trigger()
            }
        }

        // Retry swaps the old error for the spinner until the new result arrives, so the
        // click visibly does something.
        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: root.configured && !root.hasData && root.errorText.length > 0 && !root.userRefreshing
            iconName: "network-disconnect"
            text: i18n("No data yet")
            explanation: root.errorText
            helpfulAction: QQC2.Action {
                text: i18n("Retry")
                icon.name: "view-refresh"
                onTriggered: root.refresh(true)
            }
        }

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            visible: root.configured && !root.hasData && (root.errorText.length === 0 || root.userRefreshing)
            running: visible
        }

        ColumnLayout {
            id: content

            // The rows that show the car fade while the data is old, as the panel icon
            // does, so a level from hours ago doesn't pass for now. They fade less than
            // the icon: old values are all there is to read then, and their text has to
            // stay readable. The header and the footer stay as they are: they say what is
            // shown and how old it is.
            property real dataOpacity: root.stale ? 0.7 : 1
            Behavior on dataOpacity {
                NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
            }

            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            visible: root.hasData
            spacing: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaExtras.Heading {
                        id: carName
                        Layout.fillWidth: true
                        level: 3
                        font.weight: Font.DemiBold
                        text: root.car.display_name || i18n("Tesla")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        // Underlined like a link while pointed at or focused, once it is one.
                        font.underline: root.teslamateUrl !== "" && (nameHover.hovered || nameLink.activeFocus)

                        // With TeslaMate's address set, the name opens it. This covers only the
                        // text, not the empty width the layout gives the heading, and is what
                        // Tab and screen readers reach, so the heading keeps its own role while
                        // there is no link. Plasma mirrors the popup and the desktop for a
                        // right-to-left language, which draws the name at the right edge, so the
                        // link goes wherever the text is.
                        Item {
                            id: nameLink
                            x: carName.effectiveHorizontalAlignment === Text.AlignRight ? carName.width - width : 0
                            width: Math.min(carName.contentWidth, carName.width)
                            height: carName.height
                            activeFocusOnTab: root.teslamateUrl !== ""

                            Keys.onPressed: (event) => {
                                switch (event.key) {
                                case Qt.Key_Space:
                                case Qt.Key_Enter:
                                case Qt.Key_Return:
                                case Qt.Key_Select:
                                    root.openTeslaMate()
                                    event.accepted = true
                                    break
                                }
                            }

                            Accessible.role: Accessible.Link
                            Accessible.name: carName.text
                            Accessible.description: i18n("Open TeslaMate")
                            Accessible.ignored: root.teslamateUrl === ""
                            Accessible.onPressAction: root.openTeslaMate()

                            HoverHandler {
                                id: nameHover
                                enabled: root.teslamateUrl !== ""
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                enabled: root.teslamateUrl !== ""
                                onTapped: root.openTeslaMate()
                            }
                            PlasmaComponents3.ToolTip {
                                visible: nameHover.hovered
                                text: i18n("Open TeslaMate")
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        // The state's dot inside a soft halo of its own color. The layout
                        // places the halo, so it stays inside the header's line.
                        Rectangle {
                            implicitWidth: stateDot.width + 2 * Math.round(Kirigami.Units.smallSpacing * 0.75)
                            implicitHeight: implicitWidth
                            radius: width / 2
                            color: look.tint(stateDot.color, stateDot.color.a * 0.25)

                            Rectangle {
                                id: stateDot
                                anchors.centerIn: parent
                                width: Kirigami.Units.smallSpacing * 2
                                height: width
                                radius: width / 2
                                color: look.stateColor(root.carState)
                            }
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.features: { "tnum": 1 }
                            opacity: look.secondary
                            textFormat: Text.PlainText
                            text: {
                                root.now // re-evaluate on tick
                                const parts = [root.stateLabel()]
                                if (root.car.geofence) parts.push(root.car.geofence)
                                const since = root.car.since ? Logic.formatSince(root.car.since, root.now) : ""
                                if (since && root.carState !== "driving") parts.push(since)
                                return parts.join(" · ")
                            }
                        }
                    }
                }

                // Only for a refresh someone asked for, and beside the button rather than
                // over it, so the button keeps its icon. Its place is kept while it's
                // hidden, so the header doesn't move when it shows.
                Item {
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small

                    PlasmaComponents3.BusyIndicator {
                        anchors.fill: parent
                        visible: root.userRefreshing
                        running: visible
                    }
                }

                // Always visible and enabled, even while refreshing, so it never takes
                // keyboard focus away by disappearing or turning off.
                PlasmaComponents3.ToolButton {
                    id: refreshButton
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                    text: i18n("Refresh")
                    onClicked: root.refresh(true)

                    PlasmaComponents3.ToolTip {
                        visible: refreshButton.hovered
                        text: refreshButton.text
                    }
                }
            }

            // Battery, and what the car is doing. The ring is open at the bottom: its arc
            // ends well above the edge of its square, which leaves more than a row's
            // distance already, so the next row follows the square without another.
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: -content.spacing
                spacing: Kirigami.Units.largeSpacing * 2
                opacity: content.dataOpacity

                BatteryRing {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                    value: root.level >= 0 ? root.level / 100 : 0
                    marker: root.limit >= 0 ? root.limit / 100 : -1
                    color: look.batteryColor(root.level, root.charging)
                    numberText: root.level >= 0 ? String(root.level) : "—"
                    unitText: root.level >= 0 ? "%" : ""
                    charging: root.charging
                    // Old data can't say that the car is charging right now.
                    animated: root.popupOpen && !root.stale
                    faded: content.dataOpacity < 1
                    subText: root.fmtDistance(root.rangeKm)
                    noteText: root.usableCold !== null ? i18n("%1% usable", root.usableCold) : ""
                }

                // The same lines in the same order whatever the car is doing: a figure and
                // its caption, then a title, a sentence and notes. A line with nothing to
                // say is left out.
                // They are stacked by columns and not by layouts. A line that wraps is only
                // as high as it gets once it has its width, and a layout that needs more
                // than two rounds to settle that logs a polish loop on Qt 6.6, as these did
                // with a destination of two lines.
                Column {
                    id: details

                    // The car takes energy back. This goes by the whole kW the figure
                    // shows, so "0 kW" is never called regenerating.
                    readonly property bool regenerating: root.power !== null && Math.round(root.power) < 0

                    // A line of parts joined by " · ", broken between its parts where it
                    // is too long, so "done by" can't end a line that "4:00 PM" starts
                    // and no line ends in a dot. The lines fill from the last part back,
                    // which leaves the short line first: "+4.2 kWh" over "16 A · 230 V ·
                    // 3 phases". Parts share a line when they fit with a pixel to spare,
                    // since the layout also counts how far the last letter overhangs,
                    // which FontMetrics doesn't. A part too long for a line wraps as any
                    // text does. Every line is as wide as this column, and a label that
                    // read its own width here would change it by setting its text.
                    function brokenBetweenParts(line, metrics) {
                        metrics.font // re-evaluate when the font changes
                        const lines = []
                        for (const part of line.split(" · ").reverse()) {
                            if (lines.length > 0 && metrics.advanceWidth(part + " · " + lines[0]) + 1 <= width)
                                lines[0] = part + " · " + lines[0]
                            else
                                lines.unshift(part)
                        }
                        return lines.join("\n")
                    }
                    // A sentence that keeps its last two words together, so it doesn't
                    // end in a line of one word. A time such as "7:00 AM" has a no-break
                    // space of its own and counts as one word. The two words are only
                    // joined when they fit in a line with a little to spare, since text
                    // that can't wrap at a space is cut in the middle of a word.
                    function noBreakAtEnd(sentence, metrics) {
                        metrics.font // re-evaluate when the font changes
                        return sentence.replace(/[^ ]+ [^ ]+$/, words =>
                            metrics.advanceWidth(words) + Kirigami.Units.smallSpacing <= width
                                ? words.replace(" ", "\u00a0") : words)
                    }

                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    // The lines have no such space below them and keep the distance
                    // themselves, above as well, which leaves them level with the middle
                    // of the ring. The row grows when they need more than the ring.
                    Layout.topMargin: content.spacing
                    Layout.bottomMargin: content.spacing

                    FontMetrics {
                        id: titleMetrics
                        font: title.font
                    }
                    FontMetrics {
                        id: bodyMetrics
                        font: body.font
                    }
                    FontMetrics {
                        id: noteMetrics
                        font: note.font
                    }

                    // What the charger supplies, or what the battery gives while driving,
                    // in green when it takes it back.
                    PlasmaExtras.Heading {
                        id: figure
                        width: details.width
                        visible: root.charging || (root.driving && root.power !== null)
                        level: 1
                        wrapMode: Text.Wrap
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: root.charging || details.regenerating ? Kirigami.Theme.positiveTextColor
                                                                     : Kirigami.Theme.textColor
                        text: root.charging ? root.chargePowerText()
                            : root.power !== null ? root.fmtPower(root.power) : ""
                    }
                    PlasmaComponents3.Label {
                        width: details.width
                        visible: !root.charging && root.driving && root.power !== null
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: look.secondary
                        text: details.regenerating ? i18n("Regenerating") : i18n("Battery power")
                    }

                    // Sets the lines apart from the figure, which is semi-bold as a title is.
                    Item {
                        width: details.width
                        height: Kirigami.Units.largeSpacing
                        visible: figure.visible && detailLines.height > 0
                    }

                    Column {
                        id: detailLines
                        width: details.width
                        spacing: Kirigami.Units.smallSpacing

                        // The charge port's status while parked, or how long the charge
                        // still takes, which is the answer then. With the time it is done
                        // on a line of its own, the block has as many lines at any time
                        // of day. Smart and solar chargers report no power every evening,
                        // so that's a neutral status rather than a warning.
                        PlasmaComponents3.Label {
                            id: title
                            width: detailLines.width
                            visible: !root.driving && text !== ""
                            wrapMode: Text.Wrap
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: root.chargeStatus === "nopower" ? Kirigami.Theme.neutralTextColor
                                                                   : Kirigami.Theme.textColor
                            text: details.noBreakAtEnd(root.charging ? root.chargeRemainingText()
                                                       : root.chargeStatusText(), titleMetrics)
                        }
                        // Where the car is going, when navigation is turned on and it has a
                        // route. A destination can be a whole address, so it gets two lines.
                        PlasmaComponents3.Label {
                            width: detailLines.width
                            visible: !root.charging && root.route !== null
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.weight: Font.DemiBold
                            text: root.route !== null ? i18n("To %1", root.route.destination) : ""
                            textFormat: Text.PlainText
                        }

                        // When the charge is done, or when the car arrives.
                        PlasmaComponents3.Label {
                            id: body
                            width: detailLines.width
                            visible: text !== ""
                            wrapMode: Text.Wrap
                            font.features: { "tnum": 1 }
                            text: details.brokenBetweenParts(root.charging ? root.chargeDoneText()
                                                             : root.routeArrivalText(), bodyMetrics)
                        }

                        // A route takes the limit's place while driving, and a charge takes
                        // both.
                        PlasmaComponents3.Label {
                            id: note
                            width: detailLines.width
                            visible: text !== ""
                            wrapMode: Text.Wrap
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.features: { "tnum": 1 }
                            opacity: look.secondary
                            text: details.brokenBetweenParts(root.charging ? root.chargeSupplyText()
                                                             : root.route !== null ? root.routeRemainingText()
                                                             : root.limitText(), noteMetrics)
                        }
                        // What the car asks of the charger, or when a schedule starts.
                        PlasmaComponents3.Label {
                            width: detailLines.width
                            visible: text !== ""
                            wrapMode: Text.Wrap
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.features: { "tnum": 1 }
                            opacity: look.secondary
                            text: root.charging ? root.chargeRequestText()
                                : root.driving ? "" : root.scheduleText()
                        }
                    }
                }
            }

            // Anything that needs attention. Past two lines it shows the first and a count,
            // so the car drawing keeps its room; hovering, and the panel tooltip, list all.
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.attentionLines.length > 0
                type: Kirigami.MessageType.Warning
                text: root.attentionLines.length <= 2 ? root.attentionLines.join("\n")
                    : root.attentionLines[0] + "\n"
                      + i18np("And %1 more", "And %1 more", root.attentionLines.length - 1)

                HoverHandler { id: attentionHover }
                PlasmaComponents3.ToolTip {
                    visible: attentionHover.hovered && root.attentionLines.length > 2
                    text: root.attentionLines.join("\n")
                }
            }

            // Climate and odometer on one tinted surface
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: stats.implicitHeight + stats.anchors.topMargin + stats.anchors.bottomMargin
                radius: look.radius
                color: look.surface
                opacity: content.dataOpacity

                RowLayout {
                    id: stats

                    readonly property bool climateOn: Logic.bool(root.car, "is_climate_on")
                    readonly property bool preconditioning: Logic.bool(root.car, "is_preconditioning")
                    // The cells are as wide as each other, except one whose texts need
                    // more than its share, as "Preconditioning" does. That one gets what
                    // it asks for and the others share the rest, so the hairlines hardly
                    // move when a text changes. This is the width of the cells that
                    // share. It is 0 when the strip is too narrow for what the cells ask
                    // for, and the layout then shrinks them all.
                    readonly property real share: {
                        const needs = [inside, outside, climate, odometer].map(cell => cell.implicitWidth)
                        needs.sort((a, b) => b - a)
                        let room = width
                        let cells = needs.length
                        for (const need of needs) {
                            if (need * cells <= room) break
                            room -= need
                            cells--
                        }
                        return cells > 0 ? room / cells : 0
                    }

                    anchors.fill: parent
                    anchors.topMargin: Kirigami.Units.smallSpacing * 1.5
                    anchors.bottomMargin: Kirigami.Units.smallSpacing * 1.5
                    spacing: 0

                    Stat {
                        id: inside
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(implicitWidth, stats.share)
                        divider: false
                        label: i18n("Inside")
                        value: root.fmtTemp(Logic.num(root.car, "inside_temp"))
                    }
                    Stat {
                        id: outside
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(implicitWidth, stats.share)
                        label: i18n("Outside")
                        value: root.fmtTemp(Logic.num(root.car, "outside_temp"))
                    }
                    Stat {
                        id: climate
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(implicitWidth, stats.share)
                        label: stats.preconditioning ? i18n("Preconditioning") : i18n("Climate")
                        // A dash, like the readings beside it, while TeslaMate hasn't said
                        // whether the climate is on.
                        value: stats.preconditioning || stats.climateOn ? i18n("On")
                            : Logic.triState(root.car, "is_climate_on") === null ? "—" : i18n("Off")
                        dot: stats.preconditioning || stats.climateOn
                    }
                    Stat {
                        id: odometer
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(implicitWidth, stats.share)
                        label: i18n("Odometer")
                        value: root.fmtDistance(Logic.num(root.car, "odometer"))
                    }
                }
            }

            // Tires, doors, windows, openings, lock and Sentry on one car
            CarStatus {
                id: carStatus
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Enough for the car to lie on its side, as it does in the popup, however
                // large the font of its readings is. In less it stands nose up and is a
                // third of the size.
                Layout.minimumHeight: Math.max(Kirigami.Units.gridUnit * 5, carStatus.sidewaysHeight)
                opacity: content.dataOpacity
                car: root.car
                model: root.carModel
                rightHandDrive: root.cfg.rightHandDrive
                paint: root.paint
                fl: root.tire("fl")
                fr: root.tire("fr")
                rl: root.tire("rl")
                rr: root.tire("rr")
            }

            // Footer. An update's status moves to a line of its own when one line can't
            // hold everything, as on a narrow card or during a download. The version and
            // the status are as wide as their texts, to the next whole pixel, and give way
            // when even that is too much, so a long version elides rather than widen the
            // card.
            GridLayout {
                id: footer

                // Moving the status to the other line resizes the car, which mustn't
                // happen each time a poll fails or the hour gains a digit. So the warning
                // icon keeps its place while it's hidden, and the time counts as wide as
                // it gets.
                readonly property bool oneLine: softwareVersion.implicitWidth + updateStatus.implicitWidth
                                                + freshness.implicitWidth
                                                + Math.max(0, widestUpdated.advanceWidth - updated.implicitWidth)
                                                + 2 * columnSpacing <= width

                Layout.fillWidth: true
                columns: 3
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing * 1.5

                // An hour of two digits, on a 12 hour clock and on a 24 hour clock, and
                // today, so no weekday comes with it.
                TextMetrics {
                    id: widestUpdated
                    font: updated.font
                    text: {
                        const late = new Date()
                        late.setHours(22, 0, 0, 0)
                        return root.updatedText(late)
                    }
                }

                PlasmaComponents3.Label {
                    id: softwareVersion
                    Layout.row: 0
                    Layout.column: 0
                    Layout.fillWidth: true
                    Layout.maximumWidth: Math.ceil(implicitWidth)
                    visible: text !== ""
                    elide: Text.ElideRight
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.features: { "tnum": 1 }
                    opacity: look.secondary
                    text: root.car.version ? i18n("Software %1", root.car.version) : ""
                    textFormat: Text.PlainText
                }

                // The update's status on a tint of the highlight color, which fills from
                // the start as the download or the installation goes on. The tint is a
                // little taller than the line of text, without making the footer taller.
                Item {
                    id: updateStatus

                    property real progress: root.softwareUpdate.percent !== null
                        ? Math.max(0, Math.min(1, root.softwareUpdate.percent / 100)) : 0
                    Behavior on progress {
                        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
                    }

                    Layout.row: footer.oneLine ? 0 : 1
                    Layout.column: footer.oneLine ? 1 : 0
                    Layout.columnSpan: footer.oneLine ? 1 : 3
                    Layout.fillWidth: true
                    Layout.maximumWidth: Math.ceil(implicitWidth)
                    visible: root.softwareUpdate.phase !== ""
                    implicitWidth: updateLabel.implicitWidth + 2 * updateLabel.anchors.leftMargin
                    implicitHeight: updateLabel.implicitHeight

                    Rectangle {
                        id: pill
                        anchors.fill: parent
                        anchors.topMargin: -Kirigami.Units.smallSpacing / 2
                        anchors.bottomMargin: -Kirigami.Units.smallSpacing / 2
                        radius: height / 2
                        color: look.tint(Kirigami.Theme.highlightColor, 0.2)

                        Item {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * updateStatus.progress
                            clip: true

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: pill.width
                                radius: pill.radius
                                color: look.tint(Kirigami.Theme.highlightColor, 0.3)
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        id: updateLabel
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        elide: Text.ElideRight
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.features: { "tnum": 1 }
                        text: root.updateText()
                    }
                }

                RowLayout {
                    id: freshness
                    Layout.row: 0
                    Layout.column: 2
                    Layout.fillWidth: true
                    // The filler before the icon would count a spacing as width the row
                    // needs, so the time keeps its distance from the icon by a margin.
                    spacing: 0

                    Item { Layout.fillWidth: true }

                    // The icon is a pixel taller than the line of text. It hangs over the
                    // line rather than stretch it, so the rows above don't move each time
                    // a poll fails or works again.
                    Item {
                        implicitWidth: warning.width
                        implicitHeight: updated.implicitHeight

                        Kirigami.Icon {
                            id: warning
                            y: Math.round((parent.height - height) / 2)
                            width: Kirigami.Units.iconSizes.small
                            height: width
                            visible: root.errorText.length > 0
                            source: "data-warning"
                            HoverHandler { id: warnHover }
                            PlasmaComponents3.ToolTip {
                                visible: warnHover.hovered
                                text: i18n("Showing last good data.\n%1", root.errorText)
                            }
                        }
                    }

                    // At full strength while the data is old, since this time then says how
                    // old. It stays in the text color: the icon before it carries the
                    // warning's color, which some themes make too pale to read as text.
                    PlasmaComponents3.Label {
                        id: updated
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.features: { "tnum": 1 }
                        opacity: root.stale ? 1 : look.secondary
                        color: Kirigami.Theme.textColor
                        text: {
                            root.now // re-evaluate on tick: at midnight the time gets its weekday
                            return root.lastUpdated ? root.updatedText(root.lastUpdated) : ""
                        }
                    }
                }
            }
        }
    }
}
