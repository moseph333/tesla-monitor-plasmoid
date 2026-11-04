import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

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
    readonly property var rangeKm: Logic.num(car, ["rated_battery_range_km", "est_battery_range_km", "ideal_battery_range_km"][cfg.rangeType] || "rated_battery_range_km")
    readonly property var okGeofences: Logic.geofenceList(cfg.unlockedOkGeofences)
    readonly property var attentionItems: Logic.attention(car, okGeofences)
    readonly property var attentionLines: texts.attentionLines(attentionItems)
    readonly property var usableCold: Logic.usableIfCold(car)
    // Not "update", which would hide Item's update() method.
    readonly property var softwareUpdate: Logic.updateProgress(car)

    readonly property string distUnit: units.distance
    readonly property string tempUnit: "°" + units.temperature
    readonly property string pressUnit: units.pressure

    function fmtDistance(km) {
        const d = Logic.distance(km, units.distance)
        return d === null ? "—" : Math.round(d).toLocaleString(Qt.locale(), "f", 0) + " " + distUnit
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

    // A time that may be days away, such as a scheduled charge, so it names the weekday
    // when it isn't today: "11:40 PM" or "Sat 7:00 AM".
    function clock(ms) {
        const d = new Date(ms)
        const time = Qt.formatTime(d, Locale.ShortFormat)
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
        return [s].concat(attentionLines).join("\n")
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh Now")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
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

    function refresh() {
        if (!configured || fetch.busy) return
        fetch.run(connectionOptions([prefix + "/#"], 2))
    }

    function applyResult(out, err) {
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
        }
    }

    MqttFetch {
        id: fetch
        onFinished: (out, err) => root.applyResult(out, err)
    }

    Texts { id: texts }

    Timer {
        interval: Math.max(5, root.cfg.refreshSeconds) * 1000
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
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
            fetch.cancel()
            root.refresh()
        }
    }

    Component.onCompleted: {
        // 1.5 replaced the imperial checkbox with a setting for each unit. This keeps what an
        // existing widget showed, once; libplasma saves the new values a moment later.
        const m = Logic.unitMigration(cfg.unitsMigrated, cfg.brokerHost, cfg.imperial)
        if (m) for (const k in m) Plasmoid.configuration[k] = m[k]
    }

    // ---------- panel ----------

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        Layout.minimumWidth: horizontal ? row.implicitWidth : -1

        RowLayout {
            id: row
            anchors.centerIn: parent
            height: parent.height
            spacing: Kirigami.Units.smallSpacing

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

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: root.configured && !root.hasData && root.errorText.length > 0
            iconName: "network-disconnect"
            text: i18n("No data yet")
            explanation: root.errorText
            helpfulAction: QQC2.Action {
                text: i18n("Retry")
                icon.name: "view-refresh"
                onTriggered: root.refresh()
            }
        }

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            visible: root.configured && !root.hasData && root.errorText.length === 0
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
                        Layout.fillWidth: true
                        level: 3
                        text: root.car.display_name || i18n("Tesla")
                        elide: Text.ElideRight
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

                    // Not charging
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && root.limit >= 0
                        font.weight: Font.DemiBold
                        text: i18n("Limit %1%", root.limit)
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && root.limit > 0 && root.level > 0 && root.rangeKm !== null
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
                            return isNaN(t) ? "" : i18n("Scheduled %1", Qt.formatTime(new Date(t), Locale.ShortFormat))
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

                PlasmaComponents3.Label {
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.6
                    text: root.lastUpdated ? Qt.formatTime(root.lastUpdated, Locale.ShortFormat) : ""
                }
            }
        }
    }
}
