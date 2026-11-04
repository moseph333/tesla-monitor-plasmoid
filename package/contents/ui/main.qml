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

    // ---------- derived values ----------

    readonly property string carState: car.state || ""
    readonly property real level: Logic.num(car, "battery_level") ?? -1
    readonly property real limit: Logic.num(car, "charge_limit_soc") ?? -1
    readonly property bool pluggedIn: Logic.bool(car, "plugged_in")
    readonly property real chargerKw: Logic.num(car, "charger_power") ?? 0
    readonly property bool charging: carState === "charging" || chargerKw > 0
    readonly property var rangeKm: Logic.num(car, ["rated_battery_range_km", "est_battery_range_km", "ideal_battery_range_km"][cfg.rangeType] || "rated_battery_range_km")
    readonly property var openList: Logic.openings(car)

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

    // The text next to the panel icon. While charging, the time to full can take the
    // range's place, since it's what matters then.
    function panelLabel() {
        const parts = []
        if (cfg.panelText !== 1 && level >= 0) parts.push(level + "%")
        const toFull = charging && cfg.panelChargingTime
            ? Logic.formatHours(Logic.num(car, "time_to_full_charge")) : ""
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
        case "updating": return i18n("Installing update")
        case "suspended": return i18n("Falling asleep")
        case "online": {
            const shift = car.shift_state || ""
            return (shift === "D" || shift === "R") ? i18n("Driving") : i18n("Parked")
        }
        default: return carState ? carState : i18n("Unknown")
        }
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
        return s
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Refresh Now")
            icon.name: "view-refresh"
            onTriggered: root.refresh()
        }
    ]

    // ---------- MQTT via mosquitto_sub ----------
    // TeslaMate publishes every value as a retained message, so a short-lived
    // subscriber receives a full snapshot immediately and exits after -W seconds.

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
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        text: root.charging ? i18n("Charging")
                            : root.pluggedIn ? i18n("Plugged in")
                            : i18n("Not plugged in")
                    }

                    // While charging
                    PlasmaExtras.Heading {
                        visible: root.charging
                        level: 2
                        color: Kirigami.Theme.positiveTextColor
                        text: root.chargerKw + " kW"
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: root.charging
                        wrapMode: Text.Wrap
                        text: {
                            const parts = []
                            const added = Logic.num(root.car, "charge_energy_added")
                            if (added !== null) parts.push("+" + added.toFixed(1) + " kWh")
                            const amps = Logic.num(root.car, "charger_actual_current")
                            const volts = Logic.num(root.car, "charger_voltage")
                            if (amps !== null && volts !== null) parts.push(amps + " A · " + volts + " V")
                            return parts.join("\n")
                        }
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: root.charging && text.length > 0
                        font.weight: Font.DemiBold
                        text: {
                            const t = Logic.formatHours(Logic.num(root.car, "time_to_full_charge"))
                            return t ? i18n("%1 to %2%", t, root.limit) : ""
                        }
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
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: !root.charging && !!root.car.scheduled_charging_start_time
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

            // Something left open
            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.openList.length > 0
                type: Kirigami.MessageType.Warning
                text: {
                    const names = {
                        frunk: i18n("Frunk"), trunk: i18n("Trunk"),
                        doors: i18n("A door"), windows: i18n("A window")
                    }
                    return root.openList.map(k => names[k]).join(", ") + " " + i18n("open")
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
                Layout.minimumHeight: Kirigami.Units.gridUnit * 5
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

                PlasmaComponents3.Label {
                    visible: Logic.bool(root.car, "update_available")
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.highlightColor
                    text: root.car.update_version ? i18n("→ %1 available", root.car.update_version) : i18n("Update available")
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
