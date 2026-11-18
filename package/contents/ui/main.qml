import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

import "logic.js" as Logic
import "models.js" as Models
import "teslaapi.js" as Api
import "sources.js" as Sources
import "rest.js" as Rest

PlasmoidItem {
    id: root

    readonly property var cfg: Plasmoid.configuration
    // Where the data comes from: see sources.js.
    readonly property var source: Sources.byId(cfg.dataSource)
    // For MQTT, uses the command builder's own test, so a host like "mqtt://" counts as not
    // configured.
    readonly property bool configured: {
        switch (source.kind) {
        case "fleet":
            return Api.fleetConfigured(Api.fleetOptions(source.key, settingsView()))
        case "rest":
            return restFetch.canRun(restOptions("data"))
        default:
            return Logic.parseBrokerHost(cfg.brokerHost).host !== ""
        }
    }
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
    // The wallet didn't give a secret, so polls wait until someone asks for one: while the
    // wallet is closed, every poll would ask to open it again.
    property bool keyringPaused: false
    // Right after the settings change, a secret Apply just sent to the wallet may not be
    // there yet, so the first miss is tried again once.
    property bool keyringRetry: false

    // On the desktop the widget is always the card, with no panel icon or popup.
    readonly property bool onDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    // A desktop card counts as closed, so it polls at the idle rate while the car sleeps.
    readonly property bool popupOpen: expanded && !onDesktop
    // Online services have their own, slower rates, and never poll more than once a minute.
    readonly property var rates: Sources.refreshSeconds(source, cfg)
    readonly property int pollMs: Logic.pollIntervalMs(rates.active, rates.idle, carState, hasData, popupOpen)
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
    // The data source's web page, which the car's name and the context menu open: {url, name}.
    readonly property var webLink: Sources.webLink(source, cfg)
    // "" when there is none, or it isn't an http or https address, which hides the link and
    // the context menu entry.
    readonly property string webUrl: Logic.webUrl(webLink.url)
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
    // A pressure in bar as {value, unit, text} in the chosen unit. bar gets one decimal, psi
    // and kPa none.
    function fmtPressure(bar) {
        const p = Logic.pressure(bar, units.pressure)
        const value = p === null ? "—"
            : String(units.pressure === "bar" ? p.toLocaleString(Qt.locale(), "f", 1) : Math.round(p))
        return { value: value, unit: p === null ? "" : pressUnit, text: p === null ? "—" : value + " " + pressUnit }
    }
    // One tire's pressure as {value, unit, text, warn}. The card shows value and unit in
    // different sizes; notifications use text.
    function tire(pos) {
        return Object.assign(fmtPressure(Logic.num(car, "tpms_pressure_" + pos)),
                             { warn: Logic.bool(car, "tpms_soft_warning_" + pos) })
    }
    // The recommended cold pressures, for the sources that give them, or "".
    function recommendedPressureText() {
        const front = Logic.num(car, "tpms_rcp_front")
        const rear = Logic.num(car, "tpms_rcp_rear")
        if (front === null || rear === null) return ""
        const f = fmtPressure(front).text
        const r = fmtPressure(rear).text
        return f === r ? i18n("Recommended pressure: %1", f)
                       : i18n("Recommended pressure: %1 front, %2 rear", f, r)
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
    function openWebPage() {
        if (!webUrl) return
        Qt.openUrlExternally(webUrl)
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
            text: i18nc("open a web site such as TeslaMate", "Open %1", root.webLink.name)
            icon.name: "internet-web-browser"
            visible: root.webUrl !== ""
            onTriggered: root.openWebPage()
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
            keyringId: cfg.keyringId,
            tls: cfg.useTls,
            caFile: cfg.caFile,
            topics: topics,
            wait: wait
        }
    }

    // The settings for TeslaApiFetch.run() (the Fleet API or Teslemetry), asking for request.
    function apiOptions(request) {
        return Object.assign(Api.fleetOptions(source.key, settingsView()), {
            // Only for navigation, which is opt-in: asking for it shows an icon in the car.
            withLocation: cfg.showNavigation,
            request: request
        })
    }

    // The settings for RestFetch.run(), asking for request.
    function restOptions(request) {
        return Rest.restOptions(source, settingsView(), request)
    }

    // Api.pollPlan()'s state between polls, and whether the running request is a summary
    // asked for to let the car sleep.
    property var apiPlan: null
    property bool apiSuspended: false

    // The online services' tokens, keyed by setting (Logic.tokenSettings()): from the
    // wallet, or from the settings without one. null until they're known.
    property var tokens: null
    property bool tokensLoading: false

    readonly property Keyring keyring: Keyring {}
    readonly property string passwordLabel: i18nc("@label name of the entry in the wallet", "Tesla Monitor MQTT password")
    readonly property string tokensLabel: i18nc("@label name of the entry in the wallet", "Tesla Monitor tokens")

    // cfg as a plain object, with the tokens in place of the settings' own. Until the wallet
    // has been read, the tokens in it count as there, so the widget counts as set up.
    function settingsView() {
        const settings = {}
        for (const key of cfg.keys()) settings[key] = cfg[key]
        for (const key of Logic.tokenSettings())
            settings[key] = tokens ? tokens[key] : cfg.tokensKeyringId ? "-" : cfg[key]
        return settings
    }

    // Reads the tokens from the wallet, then polls.
    function loadTokens() {
        const id = cfg.tokensKeyringId
        tokensLoading = true
        keyring.lookup(id, result => {
            if (id !== cfg.tokensKeyringId) return
            tokensLoading = false
            const read = result.status === "ok" ? Logic.unpackSecrets(result.value, Logic.tokenSettings()) : null
            if (!read) {
                keyringFailed(result.status === "missing"
                    ? i18n("secret-tool isn't installed, so the tokens can't be read from the wallet. Install libsecret-tools on Debian and Ubuntu, or libsecret on Fedora and Arch.")
                    : result.detail
                    ? i18n("Couldn't get the tokens from the wallet: %1", result.detail)
                    : i18n("Couldn't get the tokens from the wallet. Open the wallet and refresh, or enter the token again in the settings."))
                return
            }
            keyringRetry = false
            tokens = read
            refresh(false)
        })
    }

    // manual shows a spinner until the result arrives. If a poll is already running, its
    // result is used.
    function refresh(manual) {
        if (!configured) return
        if (manual) {
            userRefreshing = true
            keyringPaused = false
        }
        if (source.kind !== "mqtt" && !tokens) {
            if (tokensLoading) return
            if (cfg.tokensKeyringId) {
                loadTokens()
                return
            }
            const plain = {}
            for (const key of Logic.tokenSettings()) plain[key] = cfg[key]
            tokens = plain
        }
        if (source.kind === "fleet") {
            if (apiFetch.busy) return
            const plan = Api.pollPlan(apiPlan, car, Date.now(), { forced: manual })
            apiPlan = plan.state
            apiSuspended = plan.suspended
            if (!apiFetch.run(apiOptions(plan.request))) userRefreshing = false
            return
        }
        if (source.kind === "rest") {
            if (restFetch.busy) return
            if (!restFetch.run(restOptions("data"))) userRefreshing = false
            return
        }
        if (fetch.busy) return
        if (!fetch.run(connectionOptions([prefix + "/#"], 2))) userRefreshing = false
    }

    function applyResult(out, err, kind) {
        if (kind === "keyring") {
            keyringFailed(err)
            return
        }
        keyringRetry = false
        const parsed = Logic.parseMqtt(out, prefix)
        if (Object.keys(parsed).length === 0)
            applyFailure(err || i18n("No TeslaMate data on %1/#. Check the topic prefix and that MQTT is enabled in TeslaMate.", prefix))
        else
            applyValues(parsed)
    }

    // The wallet didn't give a secret: try again once right after a settings change, and
    // otherwise wait until someone asks.
    function keyringFailed(err) {
        applyFailure(err)
        if (keyringRetry) keyringRetryTimer.start()
        else keyringPaused = true
        keyringRetry = false
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

    // A source that doesn't say when the state began gets the time this widget saw it change.
    function applyRestResult(result, err) {
        if (!result) {
            applyFailure(err)
            return
        }
        const values = result.values
        if (!values.since) values.since = Api.trackSince(car, values, Date.now())
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
        onFinished: (out, err, kind) => root.applyResult(out, err, kind)
    }

    TeslaApiFetch {
        id: apiFetch
        onFinished: (result, err) => root.applyApiResult(result, err)
        // Renewing invalidates the old tokens, so the new ones are saved at once, without
        // counting as a change of settings that discards the data.
        onTokensRenewed: (access, refresh, expiresAt, replaced) => root.saveTokens(access, refresh, expiresAt, replaced)
    }

    // Saves renewed Fleet API tokens where the refresh token they replace is kept: in the
    // wallet, or in the settings without one. Tokens renewed for settings that changed
    // meanwhile aren't saved over the new settings' own.
    function saveTokens(access, refresh, expiresAt, replaced) {
        const id = cfg.tokensKeyringId
        if (!id) {
            if (!Logic.withRenewedTokens({ apiRefreshToken: cfg.apiRefreshToken }, access, refresh, replaced)) return
            if (tokens) tokens = Logic.withRenewedTokens(tokens, access, refresh, replaced) || tokens
            writeSecretSettings({ apiAccessToken: access, apiRefreshToken: refresh, apiTokenExpiry: expiresAt })
            return
        }
        if (tokens) {
            const merged = Logic.withRenewedTokens(tokens, access, refresh, replaced)
            if (!merged) return
            tokens = merged
            storeTokens(id, merged, expiresAt)
            return
        }
        // The settings just changed and the wallet hasn't been read since. The renewed
        // tokens go over what the wallet holds, never in alone: its one entry has every
        // service's tokens.
        keyring.lookup(id, result => {
            if (id !== cfg.tokensKeyringId || result.status !== "ok") return
            const held = Logic.unpackSecrets(result.value, Logic.tokenSettings())
            const merged = Logic.withRenewedTokens(held, access, refresh, replaced)
            if (merged) storeTokens(id, merged, expiresAt)
        })
    }

    // Puts saved, all the tokens, in the wallet under id. Renewing invalidates the old
    // tokens, so if the wallet refuses the new ones, all the tokens go in the settings
    // rather than be lost.
    function storeTokens(id, saved, expiresAt) {
        writeSecretSettings({ apiTokenExpiry: expiresAt })
        keyring.store(id, tokensLabel, Logic.packSecrets(saved, Logic.tokenSettings()), "", result => {
            if (result.status === "ok" || id !== cfg.tokensKeyringId) return
            writeSecretSettings(Object.assign({ tokensKeyringId: "" }, saved))
            keyring.clear(id)
        })
    }

    // Writes settings the widget changes itself, which don't count as a change of settings
    // that discards the data.
    function writeSecretSettings(values) {
        savingSecrets = true
        for (const key in values) Plasmoid.configuration[key] = values[key]
        // Saved now rather than when Plasma next saves, if this Plasma can.
        if (typeof Plasmoid.configuration.writeConfig === "function") Plasmoid.configuration.writeConfig()
        savingSecrets = false
        connectionSeen = connectionNow()
    }

    // Before 1.12 the password and tokens were in the settings in plain text. This offers
    // them to the wallet, once there is one. If the wallet refuses them (it stayed locked),
    // they stay where they are, the widget doesn't ask again at every start, and the
    // settings page offers to move them.
    function migrateSecrets() {
        const password = () => cfg.keyringId ? "" : cfg.brokerPassword
        const tokens = () => {
            if (cfg.tokensKeyringId) return ""
            const plain = {}
            for (const key of Logic.tokenSettings()) plain[key] = cfg[key]
            return Logic.packSecrets(plain, Logic.tokenSettings())
        }
        if (cfg.secretsMigrated || (!password() && !tokens())) return
        keyring.probe(() => {
            // Without a wallet, try again at the next start.
            if (!keyring.ready) return
            const moves = []
            if (password()) moves.push({ value: password, label: passwordLabel, idKey: "keyringId", plainKeys: ["brokerPassword"] })
            if (tokens()) moves.push({ value: tokens, label: tokensLabel, idKey: "tokensKeyringId", plainKeys: Logic.tokenSettings() })
            let left = moves.length
            for (const move of moves) {
                const id = Logic.newKeyringId(Date.now(), Math.random())
                const value = move.value()
                keyring.store(id, move.label, value, "", result => {
                    // Only if the settings still hold what was moved.
                    if (result.status === "ok" && move.value() === value) {
                        const values = {}
                        values[move.idKey] = id
                        for (const key of move.plainKeys) values[key] = ""
                        writeSecretSettings(values)
                    } else if (result.status === "ok") {
                        keyring.clear(id)
                    }
                    if (--left === 0) Plasmoid.configuration.secretsMigrated = true
                })
            }
        })
    }

    RestFetch {
        id: restFetch
        onFinished: (result, err) => root.applyRestResult(result, err)
    }

    Texts { id: texts }

    Notifier {
        id: notifier
        widget: root
    }

    // Changing the interval restarts the timer, so a new rate applies at once.
    Timer {
        interval: root.pollMs
        running: root.configured && !root.keyringPaused
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    Timer {
        id: keyringRetryTimer
        interval: 3000
        onTriggered: root.refresh(false)
    }

    // Refresh when the popup opens: for an online service, which may bill each request, at
    // most once a minute. Opening it counts as asking, so the wallet is tried again.
    // Bindings on expanded (such as popupOpen) may not have updated yet inside this
    // handler, so it uses the signal's argument.
    onExpandedChanged: (expanded) => {
        if (expanded && !onDesktop && configured
            && (!lastUpdated || Date.now() - lastUpdated.getTime() > Sources.popupRefreshMs(source))) {
            keyringPaused = false
            refresh(false)
        }
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
                                           "keyringId", "topicPrefix", "useTls", "caFile", "apiRegion", "apiBaseUrl",
                                           "apiVin", "apiAccessToken", "apiRefreshToken", "apiClientId",
                                           "apiAuthUrl", "teslamateApiUrl", "teslamateApiToken",
                                           "teslamateApiCarId", "teslemetryToken", "teslemetryVin",
                                           "tessieToken", "tessieVin", "haUrl", "haToken", "haPrefix",
                                           "tokensKeyringId"]
    property string connectionSeen: ""
    // True while writeSecretSettings() runs.
    property bool savingSecrets: false
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
            if (root.savingSecrets) {
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
            root.tokens = null
            root.tokensLoading = false
            root.keyringPaused = false
            root.keyringRetry = true
            keyringRetryTimer.stop()
            notifier.startOver()
            fetch.cancel()
            apiFetch.cancel()
            restFetch.cancel()
            root.refresh(false)
        }
    }

    Component.onCompleted: {
        connectionSeen = connectionNow()
        // 1.5 replaced the imperial checkbox with per-unit settings. This carries the old
        // choice over, once.
        const migrated = Logic.unitMigration(cfg.unitsMigrated, cfg.brokerHost, cfg.imperial)
        for (const key in migrated) Plasmoid.configuration[key] = migrated[key]
        migrateSecrets()
    }

    compactRepresentation: CompactRepresentation {
        widget: root
    }

    fullRepresentation: FullRepresentation {
        widget: root
    }
}
