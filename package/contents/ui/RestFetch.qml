import QtQuick

import "rest.js" as Rest
import "teslamateapi.js" as TeslaMateApi

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
    // Ends the open HTTP request as if it got no reply.
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
            else done(id, result, null)
        })
        return true
    }

    function convert(json) {
        switch (options.source.key) {
        case "teslamateApi": return TeslaMateApi.convert(options.request, json)
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

    // One GET. callback(status, body) runs once: with status 0 if there was no reply within
    // the timeout.
    function request(url, bearer, callback) {
        const xhr = new XMLHttpRequest()
        let finished = false
        const finish = (status, text) => {
            if (finished) return
            finished = true
            abortPending = null
            timeout.stop()
            callback(status, text)
        }
        abortPending = () => {
            finish(0, "")
            try {
                xhr.abort()
            } catch (e) {
            }
        }
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE) finish(xhr.status, String(xhr.responseText || ""))
        }
        xhr.open("GET", url)
        xhr.setRequestHeader("Accept", "application/json")
        if (bearer) xhr.setRequestHeader("Authorization", "Bearer " + bearer)
        timeout.restart()
        xhr.send()
    }

    property Timer timeout: Timer {
        interval: 20000
        onTriggered: if (fetch.abortPending) fetch.abortPending()
    }

    // The message for an error, or "" if there was none.
    function message(error) {
        const name = options.source ? options.source.name : ""
        const host = Rest.host(options.base)
        switch (error.kind) {
        case "": return ""
        case "network": return i18n("Can't reach %1. Check the address and the network, and that %2 is running.", host, name)
        case "auth": return i18n("%1 rejected the token. Check it in the widget settings.", name)
        case "forbidden": return i18n("The token may not read this car's data.")
        case "notFound": return i18n("%1 doesn't answer like %2. Check the address.", host, name)
        case "noCar": return i18n("TeslaMate has no car with ID %1, or the TeslaMate API hasn't received its values over MQTT yet. Try Find Cars.", String(options.car))
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
