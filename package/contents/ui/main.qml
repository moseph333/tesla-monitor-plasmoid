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
    function fmtTemp(c) {
        const t = Logic.temperature(c, units.temperature)
        return t === null ? "—" : Math.round(t) + tempUnit
    }
    function fmtSpeed(kmh) {
        const v = Logic.distance(kmh, units.distance)
        return v === null ? "" : Math.round(v) + (units.distance === "mi" ? " mph" : " km/h")
    }
    // A tenth of a bar matters, but psi and kPa are read in whole numbers.
    function tire(pos) {
        const p = Logic.pressure(Logic.num(car, "tpms_pressure_" + pos), units.pressure)
        return {
            text: p === null ? "—" : (units.pressure === "bar" ? p.toFixed(1) : Math.round(p)) + " " + pressUnit,
            warn: Logic.bool(car, "tpms_soft_warning_" + pos)
        }
    }
    // Rounded before the sign is chosen, so a small negative value can't show as "−0". The
    // minus sign (U+2212) is as wide as the digits, unlike a hyphen.
    function fmtPower(kw) {
        const r = Math.round(kw)
        return (r < 0 ? "−" : "") + Math.abs(r) + " kW"
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

    // The charging block's heading. The charger reports no power yet while it starts, and
    // current × voltage stands in when it reports 0 kW, as it can for a slow charge.
    function chargePowerText() {
        if (chargeStatus === "starting") return i18n("Starting…")
        if (chargerKw > 0) return chargerKw + " kW"
        const amps = Logic.num(car, "charger_actual_current")
        const volts = Logic.num(car, "charger_voltage")
        if (amps > 0 && volts > 0) return (amps * volts / 1000).toFixed(1) + " kW"
        return i18n("Charging")
    }

    function stateColor() {
        switch (carState) {
        case "charging": return Kirigami.Theme.positiveTextColor
        case "driving": return Kirigami.Theme.highlightColor
        case "online": return Kirigami.Theme.positiveTextColor
        case "updating": return Kirigami.Theme.neutralTextColor
        case "offline": return Kirigami.Theme.negativeTextColor
        default: return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.35)
        }
    }

    function batteryColor() {
        if (charging) return Kirigami.Theme.positiveTextColor
        if (level >= 0 && level < 10) return Kirigami.Theme.negativeTextColor
        if (level >= 0 && level < 20) return Kirigami.Theme.neutralTextColor
        return Kirigami.Theme.highlightColor
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
    toolTipSubText: {
        if (!configured) return i18n("Not configured")
        if (!hasData) return errorText || i18n("Connecting…")
        let s = stateLabel()
        if (level >= 0) s += " · " + level + "% · " + fmtDistance(rangeKm)
        const toFull = Logic.formatHours(hoursToFull)
        if (charging && toFull) s += " · " + i18n("%1 to %2%", toFull, limit)
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

    Connections {
        target: Plasmoid.configuration
        // Only connection settings need fresh data. The display settings (units, range type,
        // right-hand drive, panel text) update through their bindings. Keys the widget
        // writes itself, such as unitsMigrated, must stay off this list, or writing them
        // would throw away the data and poll again.
        function onValueChanged(key) {
            if (["brokerHost", "brokerPort", "brokerUser", "brokerPassword", "topicPrefix", "useTls", "caFile"].indexOf(key) >= 0)
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
        const b = Logic.parseBrokerHost(cfg.brokerHost)
        const source = b.host.toLowerCase() + ":" + (b.port || cfg.brokerPort) + "|" + prefix
        const at = Date.now()
        const mine = Logic.claimEvent(e, car, cfg.leftOpenMinutes * 60000,
                                      (key, windowMs) => Hub.claim(source + "|" + key, at, windowMs))
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
        Layout.preferredWidth: Kirigami.Units.gridUnit * 21
        Layout.preferredHeight: Kirigami.Units.gridUnit * 27
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        Layout.minimumHeight: Kirigami.Units.gridUnit * 20

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
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            visible: root.hasData
            spacing: Kirigami.Units.largeSpacing

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 2

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaExtras.Heading {
                        id: carName
                        Layout.fillWidth: true
                        level: 3
                        text: root.car.display_name || i18n("Tesla")
                        elide: Text.ElideRight
                        // Underlined like a link while pointed at or focused, once it is one.
                        font.underline: root.teslamateUrl !== "" && (nameHover.hovered || nameLink.activeFocus)

                        // With TeslaMate's address set, the name opens it. This covers only the
                        // text, not the empty width the layout gives the heading, and is what
                        // Tab and screen readers reach, so the heading keeps its own role while
                        // there is no link.
                        Item {
                            id: nameLink
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

                        Rectangle {
                            implicitWidth: Kirigami.Units.smallSpacing * 2
                            implicitHeight: implicitWidth
                            radius: width / 2
                            color: root.stateColor()
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            opacity: 0.8
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
                // over it, so the button keeps its icon.
                PlasmaComponents3.BusyIndicator {
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    visible: root.userRefreshing
                    running: visible
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

            // Battery + charging
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing * 2

                BatteryRing {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                    value: root.level >= 0 ? root.level / 100 : 0
                    marker: root.limit >= 0 ? root.limit / 100 : -1
                    color: root.batteryColor()
                    centerText: root.level >= 0 ? root.level + "%" : "—"
                    subText: root.fmtDistance(root.rangeKm)
                    noteText: root.usableCold !== null ? i18n("%1% usable", root.usableCold) : ""
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Kirigami.Units.smallSpacing

                    // Smart and solar chargers report no power every evening, so that's a
                    // neutral status rather than a warning.
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && !root.driving && text !== ""
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: root.chargeStatus === "nopower" ? 1 : 0.7
                        color: root.chargeStatus === "nopower" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                        text: root.chargeStatusText()
                    }

                    // While charging
                    PlasmaExtras.Heading {
                        visible: root.charging
                        level: 2
                        color: Kirigami.Theme.positiveTextColor
                        text: root.chargePowerText()
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: root.charging && text.length > 0
                        wrapMode: Text.Wrap
                        text: {
                            const parts = []
                            const added = Logic.num(root.car, "charge_energy_added")
                            if (added !== null) parts.push("+" + added.toFixed(1) + " kWh")
                            const amps = Logic.num(root.car, "charger_actual_current")
                            const volts = Logic.num(root.car, "charger_voltage")
                            if (amps !== null && volts !== null) {
                                const phases = Logic.showPhases(root.car)
                                parts.push(amps + " A · " + volts + " V"
                                           + (phases !== null ? " · " + i18np("%1 phase", "%1 phases", phases) : ""))
                            }
                            return parts.join("\n")
                        }
                    }
                    // The car asks for less than the charger offers when its charge current
                    // has been turned down, which explains a slow charge.
                    PlasmaComponents3.Label {
                        readonly property var request: Logic.num(root.car, "charge_current_request")
                        readonly property var requestMax: Logic.num(root.car, "charge_current_request_max")

                        Layout.fillWidth: true
                        visible: root.charging && text !== "" && request < requestMax
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: request !== null && requestMax !== null
                            ? i18n("Requested %1 of %2 A", request, requestMax) : ""
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: root.charging && text.length > 0
                        font.weight: Font.DemiBold
                        text: {
                            const t = Logic.formatHours(root.hoursToFull)
                            return t ? i18n("%1 to %2%", t, root.limit) : ""
                        }
                    }
                    // The car's estimate counts from when it was published, which the last
                    // poll is nearest to, so the time doesn't creep later while data is old.
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: root.charging && text.length > 0
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: root.hoursToFull > 0 && root.lastUpdated
                            ? i18n("Done by %1", root.clock(root.lastUpdated.getTime() + root.hoursToFull * 3600000)) : ""
                    }

                    // While driving: what the battery gives, or takes back while regenerating
                    PlasmaExtras.Heading {
                        visible: root.driving && !root.charging && root.power !== null
                        level: 2
                        color: root.power < 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
                        text: root.power !== null ? root.fmtPower(root.power) : ""
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: root.driving && !root.charging && root.power !== null
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: root.power < 0 ? i18n("Regenerating") : i18n("Battery power")
                    }
                    // Navigation, when it's turned on and the car has a route
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && root.route !== null
                        elide: Text.ElideRight
                        font.weight: Font.DemiBold
                        text: root.route !== null ? i18n("To %1", root.route.destination) : ""
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && root.route !== null && text !== ""
                        wrapMode: Text.Wrap
                        text: {
                            const t = root.route !== null && root.route.minutes !== null
                                ? Logic.formatHours(root.route.minutes / 60) : ""
                            if (!t) return ""
                            const delay = root.route.trafficMinutes >= 1
                                ? " · " + i18n("+%1 traffic", Logic.formatHours(root.route.trafficMinutes / 60)) : ""
                            return i18n("Arriving in %1", t) + delay
                        }
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && root.route !== null && text !== ""
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: {
                            if (root.route === null) return ""
                            const parts = []
                            if (root.route.km !== null) parts.push(i18n("%1 to go", root.fmtDistance(root.route.km, true)))
                            if (root.route.energyAtArrival !== null)
                                parts.push(i18n("%1% on arrival", Math.round(root.route.energyAtArrival)))
                            return parts.join(" · ")
                        }
                    }

                    // Not charging. A route takes the limit lines' place while driving.
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && root.route === null && root.limit >= 0
                        font.weight: Font.DemiBold
                        text: i18n("Limit %1%", root.limit)
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && root.route === null && root.limit > 0 && root.level > 0
                                 && root.rangeKm !== null
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: i18n("≈ %1 at limit", root.fmtDistance(root.rangeKm / root.level * root.limit))
                    }
                    // The status line already says when a waiting charge starts.
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && !root.driving && root.chargeStatus !== "scheduled"
                                 && !!root.car.scheduled_charging_start_time
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: {
                            const t = Date.parse(root.car.scheduled_charging_start_time || "")
                            return isNaN(t) ? "" : i18n("Scheduled %1", root.shortTime(new Date(t)))
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

            Kirigami.Separator { Layout.fillWidth: true }

            // Climate + odometer
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Stat {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    label: i18n("Inside")
                    value: root.fmtTemp(Logic.num(root.car, "inside_temp"))
                }
                Stat {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    label: i18n("Outside")
                    value: root.fmtTemp(Logic.num(root.car, "outside_temp"))
                }
                Stat {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    label: i18n("Climate")
                    value: Logic.bool(root.car, "is_preconditioning") ? i18n("Precond.")
                         : Logic.bool(root.car, "is_climate_on") ? i18n("On") : i18n("Off")
                    valueColor: Logic.bool(root.car, "is_climate_on") ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                }
                Stat {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    label: i18n("Odometer")
                    value: root.fmtDistance(Logic.num(root.car, "odometer"))
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // Tires, doors, windows, openings, lock and Sentry on one car
            CarStatus {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 4
                car: root.car
                rightHandDrive: root.cfg.rightHandDrive
                fl: root.tire("fl")
                fr: root.tire("fr")
                rl: root.tire("rl")
                rr: root.tire("rr")
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents3.Label {
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.6
                    text: root.car.version ? i18n("Software %1", root.car.version) : ""
                }

                // Elides rather than pushing the update time out of the footer.
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: root.softwareUpdate.phase !== ""
                    elide: Text.ElideRight
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.highlightColor
                    text: {
                        const v = root.car.update_version || ""
                        const p = root.softwareUpdate.percent !== null ? Math.round(root.softwareUpdate.percent) : 0
                        switch (root.softwareUpdate.phase) {
                        case "downloading":
                            return v ? i18n("Downloading %1 · %2%", v, p) : i18n("Downloading update · %1%", p)
                        case "installing":
                            return v ? i18n("Installing %1", v) : i18n("Installing update")
                        default:
                            return v ? i18n("→ %1 available", v) : i18n("Update available")
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Kirigami.Icon {
                    visible: root.errorText.length > 0
                    source: "data-warning"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    HoverHandler { id: warnHover }
                    PlasmaComponents3.ToolTip {
                        visible: warnHover.hovered
                        text: i18n("Showing last good data.\n%1", root.errorText)
                    }
                }

                // Stands out while the data is old, since this time then says how old.
                PlasmaComponents3.Label {
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: root.stale ? 1 : 0.6
                    color: root.stale ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                    text: root.lastUpdated ? root.shortTime(root.lastUpdated) : ""
                }
            }
        }
    }
}
