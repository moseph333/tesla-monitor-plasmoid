.pragma library

// Parse `mosquitto_sub -v` output ("topic payload" per line) into { key: payload }
// where key is the topic with the prefix stripped, e.g. "battery_level".
function parseMqtt(out, prefix) {
    var map = {};
    var pre = String(prefix).replace(/\/+$/, "") + "/";
    var lines = String(out || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/\r$/, "");
        if (!line) continue;
        var sp = line.indexOf(" ");
        var topic = sp < 0 ? line : line.slice(0, sp);
        var payload = sp < 0 ? "" : line.slice(sp + 1);
        if (topic.indexOf(pre) !== 0) continue;
        map[topic.slice(pre.length)] = payload;
    }
    return map;
}

function num(car, key) {
    if (!car || car[key] === undefined || car[key] === "") return null;
    var v = parseFloat(car[key]);
    return isNaN(v) ? null : v;
}

function bool(car, key) {
    return !!car && car[key] === "true";
}

// Like bool(), but null while TeslaMate hasn't reported the value.
function triState(car, key) {
    if (!car || (car[key] !== "true" && car[key] !== "false")) return null;
    return car[key] === "true";
}

// One door or window: true/false from its own topic (e.g. driver_front_door_open). TeslaMate
// versions without per-part topics only report the total (doors_open), so then this is
// "some" while that says something is open, false when all are closed, and null if unknown.
function partOpen(car, key, totalKey) {
    var own = triState(car, key);
    if (own !== null) return own;
    var total = triState(car, totalKey);
    return total === true ? "some" : total;
}

function distance(km, imperial) {
    if (km === null) return null;
    return imperial ? km * 0.621371 : km;
}

function temperature(c, imperial) {
    if (c === null) return null;
    return imperial ? c * 9 / 5 + 32 : c;
}

function pressure(bar, imperial) {
    if (bar === null) return null;
    return imperial ? bar * 14.5038 : bar;
}

// Hours (float) -> "1h 20m" / "45m"
function formatHours(h) {
    if (h === null || h <= 0) return "";
    var mins = Math.round(h * 60);
    var hh = Math.floor(mins / 60);
    var mm = mins % 60;
    if (hh > 0) return hh + "h " + (mm < 10 ? "0" : "") + mm + "m";
    return mm + "m";
}

// ISO timestamp -> compact elapsed time "3m" / "2h" / "4d"
function formatSince(iso, nowMs) {
    var t = Date.parse(iso);
    if (isNaN(t)) return "";
    var s = Math.max(0, (nowMs - t) / 1000);
    if (s < 3600) return Math.max(1, Math.floor(s / 60)) + "m";
    if (s < 86400) return Math.floor(s / 3600) + "h";
    return Math.floor(s / 86400) + "d";
}

// Names of anything left open, in a stable order.
function openings(car) {
    var out = [];
    if (bool(car, "frunk_open")) out.push("frunk");
    if (bool(car, "trunk_open")) out.push("trunk");
    if (bool(car, "doors_open")) out.push("doors");
    if (bool(car, "windows_open")) out.push("windows");
    return out;
}

// Breeze battery icon name for a level (0..100).
function batteryIcon(level, charging) {
    var step = level === null ? 50 : Math.max(0, Math.min(100, Math.round(level / 10) * 10));
    var name = "battery-" + (step < 10 ? "00" : step < 100 ? "0" : "") + step;
    return charging ? name + "-charging" : name;
}
