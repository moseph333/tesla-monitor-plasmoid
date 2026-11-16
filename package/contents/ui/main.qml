import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

import "logic.js" as Logic
import "models.js" as Models
import "teslaapi.js" as Api

PlasmoidItem {
    id: root

    readonly property var cfg: Plasmoid.configuration
    // 0 TeslaMate over MQTT, 1 the Tesla Fleet API.
    readonly property bool useApi: cfg.dataSource === 1
    // For MQTT, uses the command builder's own test, so a host like "mqtt://" counts as not
    // configured.
    readonly property bool configured: useApi
        ? Api.baseUrl(cfg.apiRegion, cfg.apiBaseUrl) !== "" && cfg.apiAccessToken.trim() !== ""
          && Api.cleanVin(cfg.apiVin) !== ""
        : Logic.parseBrokerHost(cfg.brokerHost).host !== ""
    // Used for both subscribing and stripping topics.
    readonly property string prefix: Logic.topicPrefix(cfg.topicPrefix)
    // Automatic follows the locale's measurement system.
    readonly property var units: Logic.resolveUnits(cfg.distanceUnit, cfg.temperatureUnit, cfg.pressureUnit,
                                                    Qt.locale().measurementSystem)

    // Raw TeslaMate values, keyed by topic suffix. The Tesla API's replies are converted to
    // the same values.
    property var car: ({})
    property bool hasData: false
    property string errorText: ""
    property var lastUpdated: null
    property real now: Date.now()
    // When healthy last arrived, so its carried-over value can expire.
    property var healthySeenAt: null
    // A spinner only shows for a refresh someone asked for, not for regular polls.
    property bool userRefreshing: false

    // On the desktop the widget is always the card, with no panel icon or popup.
    readonly property bool onDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    // A desktop card counts as closed, so it polls at the idle rate while the car sleeps.
    readonly property bool popupOpen: expanded && !onDesktop
    // The API bills each request, so it has its own, slower rates, and never polls more
    // than once a minute.
    readonly property int pollMs: useApi
        ? Logic.pollIntervalMs(Math.max(60, cfg.apiRefreshSeconds), Math.max(60, cfg.apiIdleRefreshSeconds),
                               carState, hasData, popupOpen)
        : Logic.pollIntervalMs(cfg.refreshSeconds, cfg.idleRefreshSeconds, carState, hasData, popupOpen)
    // The last poll failed and the data is over a minute old (or two intervals, when polling
    // slowly), so one missed poll doesn't count.
    readonly property bool stale: hasData && errorText !== "" && lastUpdated !== null
                                  && now - lastUpdated.getTime() > Math.max(60 * 1000, 2 * pollMs)

    // ---------- derived values ----------

    readonly property string carState: car.state || ""
    readonly property string carName: car.display_name || i18n("Tesla")
    readonly property real level: Logic.num(car, "battery_level") ?? -1
    readonly property real limit: Logic.num(car, "charge_limit_soc") ?? -1
    readonly property real chargerKw: Logic.num(car, "charger_power") ?? 0
    readonly property string chargeStatus: Logic.chargeStatus(car)
    // Includes starting, so the icon and ring don't wait for the charger to ramp up.
    readonly property bool charging: chargeStatus === "charging" || chargeStatus === "starting"
    readonly property bool driving: Logic.isDriving(car)
    readonly property var hoursToFull: Logic.num(car, "time_to_full_charge")
    // kW, negative while regenerating. (TeslaMate's docs say watts, but it publishes kW.)
    readonly property var power: Logic.num(car, "power")
    // Opt-in, since it names where the car is going. Only while driving, because a route
    // from an earlier drive can stay retained.
    readonly property var route: cfg.showNavigation && driving ? Logic.activeRoute(car) : null
    // In the order of the Range setting's choices.
    readonly property var rangeTopics: ["rated_battery_range_km", "est_battery_range_km", "ideal_battery_range_km"]
    readonly property var rangeKm: Logic.num(car, rangeTopics[cfg.rangeType] || rangeTopics[0])
    readonly property var okGeofences: Logic.geofenceList(cfg.unlockedOkGeofences)
    readonly property var attentionItems: Logic.attention(car, okGeofences)
    readonly property var attentionLines: texts.attentionLines(attentionItems)
    readonly property var usableCold: Logic.usableIfCold(car)
    // Not named "update": that would hide Item's update() method.
    readonly property var softwareUpdate: Logic.updateProgress(car)
    // "" when unset, which hides the link and the context menu entry.
    readonly property string teslamateUrl: Logic.normalizeUrl(cfg.teslamateUrl)
    // The car drawing's body color, or "" for theme colors (by setting, or unknown paint).
    readonly property string paint: cfg.carColor === 0 ? Logic.paintColor(car.exterior_color) : ""
    // Which model to draw: the setting's choice, or what TeslaMate reports.
    readonly property string carModel: Models.modelKey(cfg.carModel, car.model)

    readonly property string distUnit: units.distance
    readonly property string tempUnit: "°" + units.temperature
    readonly property string pressUnit: units.pressure

    // Rounds to whole units. keepTenths keeps one decimal below 10, for the end of a route.
    function fmtDistance(km, keepTenths) {
        const d = Logic.distance(km, units.distance)
        if (d === null) return "—"
        const digits = keepTenths && d < 10 ? 1 : 0
        return (digits ? d : Math.round(d)).toLocaleString(Qt.locale(), "f", digits) + " " + distUnit
    }
    // A whole number with a real minus sign (U+2212), which is as wide as a digit. Rounds
    // first, so a small negative value can't show as "−0".
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
    // One tire's pressure as {value, unit, text, warn}. bar gets one decimal, psi and kPa
    // none. The card shows value and unit in different sizes; notifications use text.
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
        // In gear, before TeslaMate starts recording the drive.
        case "online": return driving ? i18n("Driving") : i18n("Parked")
        default: return carState ? carState : i18n("Unknown")
        }
    }

    // The locale's short time: "11:40 PM" or "23:40". (Qt.formatTime(t, Locale.ShortFormat)
    // would read the enum as Qt.ISODate and give "23:40:00".)
    function shortTime(d) {
        return d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
    }

    // Like shortTime(), with the weekday when it isn't today: "Sat 7:00 AM".
    function clock(ms) {
        const d = new Date(ms)
        const time = shortTime(d)
        if (d.toDateString() === new Date().toDateString()) return time
        return Qt.locale().dayName(d.getDay(), Locale.ShortFormat) + " " + time
    }

    // "1h 30m to 80%", or "1h 30m left" if the car reports no limit. "" if the time is unknown.
    function chargeRemainingText() {
        const t = Logic.formatHours(hoursToFull)
        if (!t) return ""
        return limit >= 0 ? i18n("%1 to %2%", t, limit) : i18nc("how long a charge still takes", "%1 left", t)
    }

    // The keys that activate a button.
    function isActivationKey(key) {
        return [Qt.Key_Space, Qt.Key_Enter, Qt.Key_Return, Qt.Key_Select].includes(key)
    }

    // Closes the popup too, so it doesn't stay open behind the browser.
    function openTeslaMate() {
        if (!teslamateUrl) return
        Qt.openUrlExternally(teslamateUrl)
        expanded = false
    }

    // ---------- plasmoid setup ----------

    Plasmoid.icon: Logic.batteryIcon(level >= 0 ? level : null, charging)
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: onDesktop ? fullRepresentation : compactRepresentation

    toolTipMainText: carName
    // Names, places and errors come from MQTT, so they are never treated as markup.
    toolTipTextFormat: Text.PlainText
    toolTipSubText: {
        if (!configured) return i18n("Not configured")
        if (!hasData) return errorText || i18n("Connecting…")
        const summary = [stateLabel()]
        if (level >= 0) summary.push(level + "%", fmtDistance(rangeKm))
        const remaining = chargeRemainingText()
        if (charging && remaining) summary.push(remaining)
        // The tooltip is the only place the panel icon can show attention lines.
        const lines = [summary.join(" · ")].concat(attentionLines)
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

    // ---------- fetching ----------
    // TeslaMate retains every value except healthy, so a short-lived MQTT subscriber gets a
    // full snapshot at once and exits after -W seconds. The Tesla API is asked according to
    // Api.pollPlan(), which lets the car fall asleep.

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

    // The API settings for TeslaApiFetch.run(), asking for request.
    function apiOptions(request) {
        return {
            region: cfg.apiRegion,
            customUrl: cfg.apiBaseUrl,
            accessToken: cfg.apiAccessToken,
            refreshToken: cfg.apiRefreshToken,
            clientId: cfg.apiClientId,
            authUrl: cfg.apiAuthUrl,
            tokenExpiry: cfg.apiTokenExpiry,
            vin: cfg.apiVin,
            // Only for navigation, which is opt-in: asking for it shows an icon in the car.
            withLocation: cfg.showNavigation,
            request: request
        }
    }

    // Api.pollPlan()'s state between polls, and whether the running request is a summary
    // asked for to let the car sleep.
    property var apiPlan: null
    property bool apiSuspended: false

    // manual shows a spinner until the result arrives. If a poll is already running, its
    // result is used.
    function refresh(manual) {
        if (!configured) return
        if (manual) userRefreshing = true
        if (useApi) {
            if (apiFetch.busy) return
            const plan = Api.pollPlan(apiPlan, car, Date.now(), { forced: manual })
            apiPlan = plan.state
            apiSuspended = plan.suspended
            if (!apiFetch.run(apiOptions(plan.request))) userRefreshing = false
            return
        }
        if (fetch.busy) return
        if (!fetch.run(connectionOptions([prefix + "/#"], 2))) userRefreshing = false
    }

    function applyResult(out, err) {
        const parsed = Logic.parseMqtt(out, prefix)
        if (Object.keys(parsed).length === 0)
            applyFailure(err || i18n("No TeslaMate data on %1/#. Check the topic prefix and that MQTT is enabled in TeslaMate.", prefix))
        else
            applyValues(parsed)
    }

    function applyApiResult(result, err) {
        if (!result) {
            applyFailure(err)
            return
        }
        const time = Date.now()
        // A summary only has the name and state, so it is laid over the last values.
        const values = result.kind === "data" ? result.values
            : Api.mergeSummary(car, result.values, apiSuspended)
        values.since = Api.trackSince(car, values, time)
        applyValues(values)
    }

    function applyFailure(err) {
        userRefreshing = false
        now = Date.now()
        errorText = err
    }

    function applyValues(parsed) {
        userRefreshing = false
        now = Date.now()
        // TeslaMate 2.1+ doesn't retain healthy, so its last value is kept for 10 minutes.
        const healthy = Logic.carryHealthy(parsed.healthy, car.healthy, healthySeenAt, now, 10 * 60 * 1000)
        if (healthy.value !== undefined) parsed.healthy = healthy.value
        healthySeenAt = healthy.seenAt
        car = parsed
        hasData = true
        errorText = ""
        lastUpdated = new Date()
        notifier.process()
    }

    MqttFetch {
        id: fetch
        onFinished: (out, err) => root.applyResult(out, err)
    }

    TeslaApiFetch {
        id: apiFetch
        onFinished: (result, err) => root.applyApiResult(result, err)
        // Renewing invalidates the old tokens, so the new ones are saved at once, without
        // counting as a change of settings that discards the data.
        onTokensRenewed: (access, refresh, expiresAt) => {
            root.savingTokens = true
            Plasmoid.configuration.apiAccessToken = access
            Plasmoid.configuration.apiRefreshToken = refresh
            Plasmoid.configuration.apiTokenExpiry = expiresAt
            // Saved now rather than when Plasma next saves, if this Plasma can.
            if (typeof Plasmoid.configuration.writeConfig === "function") Plasmoid.configuration.writeConfig()
            root.savingTokens = false
            root.connectionSeen = root.connectionNow()
        }
    }

    Texts { id: texts }

    Notifier {
        id: notifier
        widget: root
    }

    // Changing the interval restarts the timer, so a new rate applies at once.
    Timer {
        interval: root.pollMs
        running: root.configured
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    // Refresh when the popup opens: for the API, which bills each request, at most once a
    // minute. Bindings on expanded (such as popupOpen) may not have updated yet inside this
    // handler, so it uses the signal's argument.
    onExpandedChanged: (expanded) => {
        if (expanded && !onDesktop && configured
            && (!lastUpdated || Date.now() - lastUpdated.getTime() > (useApi ? 60 * 1000 : 5000)))
            refresh(false)
    }

    // Keeps "asleep for 3h" ticking between polls.
    Timer {
        interval: 60 * 1000
        running: root.hasData
        repeat: true
        onTriggered: root.now = Date.now()
    }

    // The settings that decide where data comes from, and their values at the last request.
    readonly property var connectionKeys: ["dataSource", "brokerHost", "brokerPort", "brokerUser", "brokerPassword",
                                           "topicPrefix", "useTls", "caFile", "apiRegion", "apiBaseUrl",
                                           "apiVin", "apiAccessToken", "apiRefreshToken", "apiClientId",
                                           "apiAuthUrl"]
    property string connectionSeen: ""
    // True while the widget saves tokens it renewed, which isn't a change of settings.
    property bool savingTokens: false
    function connectionNow() {
        return JSON.stringify(connectionKeys.map(key => cfg[key]))
    }

    Connections {
        target: Plasmoid.configuration
        // Only connection settings need a new fetch; display settings update through bindings.
        // Plasma emits valueChanged for every key whenever the configuration is re-read, so
        // this compares values: an unchanged key must not discard the data.
        function onValueChanged(key) {
            if (!root.connectionKeys.includes(key)) return
            const now = root.connectionNow()
            if (root.savingTokens) {
                root.connectionSeen = now
                return
            }
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
            root.apiPlan = null
            notifier.startOver()
            fetch.cancel()
            apiFetch.cancel()
            root.refresh(false)
        }
    }

    Component.onCompleted: {
        connectionSeen = connectionNow()
        // 1.5 replaced the imperial checkbox with per-unit settings. This carries the old
        // choice over, once.
        const migrated = Logic.unitMigration(cfg.unitsMigrated, cfg.brokerHost, cfg.imperial)
        for (const key in migrated) Plasmoid.configuration[key] = migrated[key]
    }

    compactRepresentation: CompactRepresentation {
        widget: root
    }

    fullRepresentation: FullRepresentation {
        widget: root
    }
}
