import QtQuick

import "logic.js" as Logic
import "teslaapi.js" as Api
import "tokenhub.js" as TokenHub

// Talks to the Tesla Fleet API (or Teslemetry, or a proxy with the same URLs) for the
// widget's poll and for the settings page's buttons, renews the access token when it can,
// and words a failure as a message people can act on. It never wakes the car.
QtObject {
    id: fetch

    // The running request's number, or 0 when idle.
    property int serial: 0
    property int lastSerial: 0
    readonly property bool busy: serial !== 0
    // What the last run() was given, with the resolved base URL, for messages.
    property var options: ({})
    // The tokens in use: the settings' own, or newer ones renewed since.
    property var tokens: ({ access: "", refresh: "", expiresAt: 0 })

    // result is {kind: "data" | "summary", values} or {kind: "vehicles", vehicles}, or null
    // on failure.
    signal finished(var result, string errorText)
    // New tokens, for the settings, and the refresh token they replace. Sent even if the
    // request that renewed them was cancelled: the old refresh token no longer works.
    signal tokensRenewed(string access, string refresh, real expiresAt, string replaced)

    // options = {service, region, customUrl, accessToken, refreshToken, clientId, authUrl,
    //            tokenExpiry, vin, request, withLocation} (see Api.fleetOptions()), where request is "data", "check", "summary"
    // or "vehicles" (see Api.pollPlan()). Returns false and runs nothing if the settings
    // aren't enough.
    function run(o) {
        const base = Api.baseUrl(o.region, o.customUrl)
        const access = String(o.accessToken || "").trim()
        if (!base || !access) return false
        if (o.request !== "vehicles" && !Api.cleanVin(o.vin)) return false
        options = Object.assign({}, o, { base: base })
        tokens = { access: access, refresh: String(o.refreshToken || "").trim(), expiresAt: Number(o.tokenExpiry) || 0 }
        // Another copy may already have traded these tokens for new ones.
        const shared = tokens.refresh ? TokenHub.latest(tokens.refresh) : null
        if (shared) adopt(shared, tokens.refresh)
        lastSerial = lastSerial + 1
        serial = lastSerial
        const id = serial
        if (!Api.isSecureUrl(base)) {
            failLater(id, { kind: "insecure", detail: base })
            return true
        }
        if (Api.needsRefresh(tokens.expiresAt, Date.now()) && canRenew()) renew(id, () => step(id))
        else step(id)
        return true
    }

    // Drops the running request's result, so data from old settings can't arrive after they
    // change. Its HTTP request stays open, since a token renewal under way has to complete
    // and be saved, so it may still be open when the next run() starts.
    function cancel() {
        serial = 0
    }

    function canRenew() {
        return tokens.refresh !== "" && String(options.clientId || "").trim() !== ""
    }

    // Carries on with tokens that replaced the refresh token `replaced`.
    function adopt(next, replaced) {
        tokens = next
        fetch.tokensRenewed(next.access, next.refresh, next.expiresAt, replaced)
    }

    function done(id, result, error) {
        if (id !== serial) return
        serial = 0
        fetch.finished(result, error ? message(error) : "")
    }

    // Ends a request that can't start, after run() has returned, as one that failed would.
    function failLater(id, error) {
        Qt.callLater(() => done(id, null, error))
    }

    function step(id) {
        if (id !== serial) return
        const vin = options.vin
        switch (options.request) {
        case "vehicles":
            get(id, "/api/1/vehicles", json => done(id, { kind: "vehicles", vehicles: Api.parseVehicles(json) }, null))
            break
        case "summary":
            get(id, Api.vehiclePath(vin), json => done(id, { kind: "summary", values: Api.fromVehicleSummary(json) }, null))
            break
        case "check":
            get(id, Api.vehiclePath(vin), json => {
                const summary = Api.fromVehicleSummary(json)
                if (summary.state === "online") vehicleData(id)
                else done(id, { kind: "summary", values: summary }, null)
            })
            break
        default:
            vehicleData(id)
        }
    }

    // A car that fell asleep since the last poll answers 408, which reads as asleep.
    function vehicleData(id) {
        get(id, Api.vehicleDataPath(options.vin, options.withLocation),
            json => done(id, { kind: "data", values: Api.fromVehicleData(json) }, null),
            status => status === 408 ? (done(id, { kind: "summary", values: { state: "asleep" } }, null), true) : false)
    }

    // GETs path and passes the parsed reply to ok(). special(status) may handle an error
    // status itself by returning true. An expired token is renewed once and the request
    // repeated.
    function get(id, path, ok, special, retried) {
        http.send("GET", options.base + path, null, tokens.access, (status, body) => {
            if (id !== serial) return
            if (status === 401 && !retried && canRenew()) {
                renew(id, () => get(id, path, ok, special, true))
                return
            }
            if (status >= 200 && status < 300) {
                let json
                try {
                    json = JSON.parse(body)
                } catch (e) {
                    done(id, null, { kind: "badJson", detail: "" })
                    return
                }
                ok(json)
                return
            }
            if (special && special(status)) return
            done(id, null, Api.apiError(status, body))
        })
    }

    // Trades the refresh token for new tokens, then calls then(). The result is kept even if
    // the request was cancelled meanwhile.
    function renew(id, then) {
        const old = tokens.refresh
        const tokenUrl = Api.authUrl(options.authUrl, options.region)
        // Never send the refresh token and client ID unencrypted.
        if (!Api.isSecureUrl(tokenUrl)) {
            failLater(id, { kind: "insecure", detail: tokenUrl })
            return
        }
        const shared = TokenHub.latest(old)
        if (shared) {
            adopt(shared, old)
            then()
            return
        }
        // Another copy is renewing these tokens; carry on with the current ones.
        if (!TokenHub.begin(old, Date.now())) {
            then()
            return
        }
        http.send("POST", tokenUrl + "/oauth2/v3/token",
                Api.refreshTokenBody(options.clientId, old), "", (status, body) => {
            let next = null
            if (status === 200) {
                try {
                    next = Api.parseTokens(JSON.parse(body), old, Date.now())
                } catch (e) {
                    next = null
                }
            }
            TokenHub.finish(old, next)
            // Cancelled meanwhile: the new tokens are still saved, but another request with
            // other settings may be running by now, which they aren't for.
            if (id !== serial) {
                if (next) fetch.tokensRenewed(next.access, next.refresh, next.expiresAt, old)
                return
            }
            if (next) {
                adopt(next, old)
                then()
            } else {
                done(id, null, { kind: "refresh", detail: status === 0 ? "" : Api.apiError(status, body).detail })
            }
        })
    }

    readonly property Http http: Http {}

    function host(url) {
        const text = url === undefined ? String(options.base || "") : String(url)
        const match = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)/i.exec(text)
        // Without any user:password@, which a message shouldn't repeat.
        return match ? match[1].replace(/^.*@/, "") : text
    }

    // The message for an error from Api.apiError(), or "" if there was none. The detail is
    // the server's own words, so it is cleaned up before it is shown.
    function message(error) {
        error = Object.assign({}, error, { detail: Logic.plainDetail(error.detail) })
        if (error.kind === "insecure")
            return i18n("%1 doesn't use HTTPS, so the token would be sent unencrypted. Use an https:// address.", host(error.detail))
        if (options.service === "teslemetry") {
            switch (error.kind) {
            case "auth": return i18n("Teslemetry rejected the access token. Make a new one in the Teslemetry console.")
            case "forbidden": return i18n("The Teslemetry token may not read this car's data. Check its access in the Teslemetry console.")
            case "payment": return i18n("Teslemetry wants an active subscription or more credits for this request.")
            case "rateLimited": return i18n("Too many requests to Teslemetry. The widget will try again later.")
            case "server": return i18n("Teslemetry had a problem (HTTP %1). The widget will try again.", error.detail)
            case "http": return i18n("Teslemetry answered: %1", error.detail)
            }
        }
        switch (error.kind) {
        case "": return ""
        case "network": return i18n("Can't reach %1. Check the region or URL and the network.", host())
        case "auth": return canRenew()
            ? i18n("The Tesla API rejected the access token, even after renewing it.")
            : i18n("The Tesla API rejected the access token. It may have expired: paste a new one, or add a refresh token and client ID so the widget renews it.")
        case "refresh": return error.detail
            ? i18n("Couldn't renew the access token: %1. Paste new tokens in the widget settings.", error.detail)
            : i18n("Couldn't renew the access token. Paste new tokens in the widget settings.")
        case "forbidden": return i18n("The token may not read this car's data. It needs the vehicle_device_data scope and access to this car.")
        case "notFound": return i18n("This account has no car with VIN %1. Try Find Cars.", Api.cleanVin(options.vin))
        case "region": return i18n("This account's cars are served from another region. Choose a different region.")
        case "rateLimited": return i18n("Too many requests to the Tesla API. The widget will try again later.")
        case "server": return i18n("The Tesla API had a problem (HTTP %1). The widget will try again.", error.detail)
        case "badJson": return i18n("The reply from %1 couldn't be read. Check the URL.", host())
        case "asleep": return i18n("The car is asleep.")
        default: return i18n("The Tesla API answered: %1", error.detail)
        }
    }
}
