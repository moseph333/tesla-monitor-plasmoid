import QtQuick

import "logic.js" as Logic
import "rest.js" as Rest
import "teslamateapi.js" as TeslaMateApi
import "tessie.js" as Tessie
import "homeassistant.js" as HomeAssistant
import "teslaapi.js" as Api

// Reads the car from a source with a simple JSON API over HTTP (kind "rest" in sources.js)
// for the widget's poll and for the settings page's buttons, and words a failure as a
// message people can act on. Each source's paths and conversions are in its own script.
QtObject {
    id: fetch

    // The running request's number, or 0 when idle.
    property int serial: 0
    property int lastSerial: 0
    readonly property bool busy: serial !== 0
    // What the last run() was given, with the resolved base URL, for messages.
    property var options: ({})
    // Ends the last HTTP request as if it got no reply, if it is still open.
    property var abortPending: null

    // result is {kind: "data" | "summary", values} or {kind: "cars", cars}, or null on
    // failure.
    signal finished(var result, string errorText)

    // Where a request goes, as {base, path}, or null if the settings aren't enough.
    // options = {source, url, token, car, request}: source is a sources.js entry, url the
    // service's address as typed, car the source's way to name the car, and request "data",
    // "test" or "cars".
    function target(o) {
        switch (o.source.key) {
        case "teslamateApi": {
            const base = TeslaMateApi.baseUrl(o.url)
            if (!base || (o.request !== "cars" && !TeslaMateApi.carId(o.car))) return null
            return { base: base, path: TeslaMateApi.requestPath(o.request, o.car) }
        }
        case "tessie":
            if (!String(o.token || "").trim() || (o.request !== "cars" && !Tessie.cleanVin(o.car))) return null
            return { base: Tessie.baseUrl(), path: Tessie.requestPath(o.request, o.car) }
        case "homeAssistant": {
            const base = HomeAssistant.baseUrl(o.url)
            if (!base || !String(o.token || "").trim() || (o.request !== "cars" && !HomeAssistant.cleanPrefix(o.car)))
                return null
            return { base: base, path: HomeAssistant.requestPath(o.request) }
        }
        }
        return null
    }

    // Whether run() would start with these options.
    function canRun(o) {
        return target(o) !== null
    }

    // Returns false and runs nothing if the settings aren't enough.
    function run(o) {
        const where = target(o)
        if (!where) return false
        options = Object.assign({}, o, { base: where.base })
        lastSerial = lastSerial + 1
        serial = lastSerial
        const id = serial
        request(where.base + where.path, String(o.token || "").trim(), (status, body) => {
            if (id !== serial) return
            const error = Rest.httpError(status, body)
            if (error.kind) {
                done(id, null, error)
                return
            }
            let json
            try {
                json = JSON.parse(body)
            } catch (e) {
                done(id, null, { kind: "badJson", detail: "" })
                return
            }
            const result = convert(json)
            if (result.error) done(id, null, result.error)
            else if (result.kind === "data" && o.source.key === "tessie") addTessiePlace(id, where.base, o, result)
            else done(id, result, null)
        })
        return true
    }

    // Asks Tessie for the car's location, and adds the saved location it's at to the
    // values as the geofence. If that fails, the values arrive without one.
    function addTessiePlace(id, base, o, result) {
        request(base + Tessie.locationPath(o.car), String(o.token || "").trim(), (status, body) => {
            if (id !== serial) return
            let place = null
            if (!Rest.httpError(status, body).kind) {
                try {
                    place = Tessie.geofenceFromLocation(JSON.parse(body))
                } catch (e) {
                    place = null
                }
            }
            if (place !== null) result.values.geofence = place
            done(id, result, null)
        })
    }

    function convert(json) {
        switch (options.source.key) {
        case "teslamateApi": return TeslaMateApi.convert(options.request, json)
        case "tessie": return Tessie.convert(options.request, json, Api.fromVehicleData)
        case "homeAssistant": return HomeAssistant.convert(options.request, json, options.car, Date.now())
        }
        return { error: { kind: "badJson", detail: "" } }
    }

    // Drops the running request's result, so data from old settings can't arrive after they
    // change.
    function cancel() {
        serial = 0
        if (abortPending) abortPending()
    }

    function done(id, result, error) {
        if (id !== serial) return
        serial = 0
        fetch.finished(result, error ? message(error) : "")
    }

    // One GET, which cancel() can end. callback(status, body) runs once: with status 0 if
    // there was no reply within the timeout.
    function request(url, bearer, callback) {
        abortPending = http.send("GET", url, null, bearer, callback)
    }

    readonly property Http http: Http {}

    // The message for an error, or "" if there was none. The detail is the server's own
    // words, so it is cleaned up before it is shown.
    function message(error) {
        error = Object.assign({}, error, { detail: Logic.plainDetail(error.detail) })
        const name = options.source ? options.source.name : ""
        const host = Rest.host(options.base)
        switch (error.kind) {
        case "": return ""
        case "network": return i18n("Can't reach %1. Check the address and the network, and that %2 is running.", host, name)
        case "auth": return i18n("%1 rejected the token. Check it in the widget settings.", name)
        case "forbidden": return i18n("The token may not read this car's data.")
        case "notFound": return options.source.key === "tessie"
            ? i18n("This Tessie account has no car with VIN %1. Try Find Cars.", Tessie.cleanVin(options.car))
            : i18n("%1 doesn't answer like %2. Check the address.", host, name)
        case "noCar": return i18n("TeslaMate has no car with ID %1, or the TeslaMate API hasn't received its values over MQTT yet. Try Find Cars.", String(options.car))
        case "noEntities": return i18n("Home Assistant has no entities for a car called %1. Try Find Cars, and check that the car's entities have Home Assistant's English names.", error.detail)
        case "rateLimited": return i18n("Too many requests to %1. The widget will try again later.", name)
        case "server": return error.detail
            ? i18n("%1 had a problem: %2", name, error.detail)
            : i18n("%1 had a problem (HTTP %2). The widget will try again.", name, String(error.status))
        case "service": return i18n("%1 answered: %2", name, error.detail)
        case "badJson": return i18n("The reply from %1 couldn't be read. Check the address.", host)
        default: return i18n("%1 answered: %2", name, error.detail || String(error.status))
        }
    }
}
