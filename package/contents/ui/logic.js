.pragma library

// Parse `mosquitto_sub -v` output ("topic payload" per line) into { key: payload }
// where key is the topic with the prefix stripped, e.g. "battery_level". An empty
// prefix keeps the full topics.
function parseMqtt(out, prefix) {
    var map = {};
    var base = String(prefix || "").replace(/\/+$/, "");
    var pre = base ? base + "/" : "";
    var lines = String(out || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/\r$/, "");
        if (!line) continue;
        var sp = line.indexOf(" ");
        var topic = sp < 0 ? line : line.slice(0, sp);
        var payload = sp < 0 ? "" : line.slice(sp + 1);
        if (topic.indexOf(pre) !== 0 || topic.length === pre.length) continue;
        // mosquitto_sub prints an empty publish, which is how TeslaMate clears a value,
        // as "(null)". It must read as missing rather than show up as text.
        map[topic.slice(pre.length)] = payload === "(null)" ? "" : payload;
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

// TeslaMate names doors and windows by driver and passenger side, and tires by position.
var PARTS = ["driver_front", "driver_rear", "passenger_front", "passenger_rear"];
var TIRES = ["fl", "fr", "rl", "rr"];

// Every door or window (kind "door" or "window") by its TeslaMate name, as partOpen() reads
// it, e.g. {driver_front: true, driver_rear: false, ...}.
function parts(car, kind) {
    var out = {};
    for (var i = 0; i < PARTS.length; i++)
        out[PARTS[i]] = partOpen(car, PARTS[i] + "_" + kind + "_open", kind + "s_open");
    return out;
}

// TeslaMate reports metric values. These convert them to a unit from resolveUnits().
function distance(km, unit) {
    if (km === null) return null;
    return unit === "mi" ? km * 0.621371 : km;
}

function temperature(c, unit) {
    if (c === null) return null;
    return unit === "F" ? c * 9 / 5 + 32 : c;
}

function pressure(bar, unit) {
    if (bar === null) return null;
    if (unit === "psi") return bar * 14.5038;
    if (unit === "kPa") return bar * 100;
    return bar;
}

// The units to show, from the Display settings (0 is Automatic) and Qt's measurement
// system for the locale (0 metric, 1 US, 2 UK). The UK drives in miles and fills tires in
// psi but gives temperatures in °C.
function resolveUnits(d, t, p, measurementSystem) {
    var us = measurementSystem === 1;
    var miles = us || measurementSystem === 2;
    return {
        distance: d === 1 ? "km" : d === 2 ? "mi" : miles ? "mi" : "km",
        temperature: t === 1 ? "C" : t === 2 ? "F" : us ? "F" : "C",
        pressure: p === 1 ? "bar" : p === 2 ? "psi" : p === 3 ? "kPa" : miles ? "psi" : "bar"
    };
}

// The settings to write the first time 1.5 runs, or null once that has happened. An
// existing widget, which has a broker host, keeps the units the old imperial checkbox gave
// it; a new one stays on Automatic. Writing the result again changes nothing, so it's safe
// if Plasma quits before it saves.
function unitMigration(migrated, brokerHost, imperial) {
    if (migrated) return null;
    var keys = { unitsMigrated: true };
    if (String(brokerHost || "").trim() !== "") {
        var unit = imperial ? 2 : 1;
        keys.distanceUnit = unit;
        keys.temperatureUnit = unit;
        keys.pressureUnit = unit;
    }
    return keys;
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

// TeslaMate can still say "online" for a moment after the car is put in gear, before it
// starts recording a drive, so D and R count as driving too.
function isDriving(car) {
    var state = car ? car.state : "";
    if (state === "driving") return true;
    var shift = car ? car.shift_state : "";
    return state === "online" && (shift === "D" || shift === "R");
}

// What the charge port is doing, as a key the card words: charging, starting, complete,
// stopped, scheduled, nopower, plugged, unplugged, or "" while nothing says. TeslaMate
// before 1.28 has no charging_state, so then the car's state and the charger's power decide.
function chargeStatus(car) {
    var s = car && car.charging_state ? car.charging_state : "";
    if (s === "") {
        if ((car && car.state === "charging") || num(car, "charger_power") > 0) return "charging";
        var plugged = triState(car, "plugged_in");
        return plugged === null ? "" : plugged ? "plugged" : "unplugged";
    }
    switch (s) {
    case "Charging": return "charging";
    case "Starting": return "starting";
    case "Complete": return "complete";
    case "NoPower": return "nopower";
    case "Disconnected": return "unplugged";
    // The car also reports Stopped while it waits for a scheduled start, which is expected
    // rather than a charge that ended early.
    case "Stopped":
        return isNaN(Date.parse(car.scheduled_charging_start_time || "")) ? "stopped" : "scheduled";
    default: return bool(car, "plugged_in") ? "plugged" : "unplugged";
    }
}

// The usable level when a cold battery holds some of its charge back, else null. It uses
// TeslaMate's own rule: more than 2 points below the battery level.
function usableIfCold(car) {
    var level = num(car, "battery_level");
    var usable = num(car, "usable_battery_level");
    if (level === null || usable === null || level - usable <= 2) return null;
    return usable;
}

// A software update's phase ("", available, downloading or installing) and its percent,
// or null when that isn't known. TeslaMate's state is "updating" while the car installs,
// and update_available may already be false by then, so that state comes first. A download
// or install at 0 or 100 isn't under way, so the update then just shows as available.
function updateProgress(car) {
    var install = num(car, "install_perc");
    if (car && car.state === "updating")
        return { phase: "installing", percent: install !== null && install > 0 ? install : null };
    if (!bool(car, "update_available")) return { phase: "", percent: null };
    var download = num(car, "download_perc");
    if (download !== null && download > 0 && download < 100) return { phase: "downloading", percent: download };
    if (install !== null && install > 0 && install < 100) return { phase: "installing", percent: install };
    return { phase: "available", percent: null };
}

// The charger's phase count when it's more than one, or null. The car can report more
// phases than a charger has, so, as TeslaMate does, the count is trusted only when the
// power matches current × voltage × phases.
function showPhases(car) {
    var phases = num(car, "charger_phases");
    var amps = num(car, "charger_actual_current");
    var volts = num(car, "charger_voltage");
    var kw = num(car, "charger_power");
    if (phases === null || phases <= 1 || amps === null || amps <= 0
        || volts === null || volts <= 0 || kw === null) return null;
    return Math.round(kw * 1000 / (amps * volts)) === phases ? phases : null;
}

// The route the car is navigating, from TeslaMate's active_route JSON (1.29 and newer), as
// {destination, minutes, trafficMinutes, energyAtArrival, km}, or null. Without a route
// TeslaMate publishes {"error": "No active route available"}; with one, error is null. The
// older active_route_destination topic isn't used because it stays retained after the
// route ends, so it would show an old destination. Numbers TeslaMate leaves out are null.
function activeRoute(car) {
    var text = car ? car.active_route : "";
    if (!text) return null;
    var r;
    try {
        r = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!r || typeof r !== "object" || Array.isArray(r) || r.error) return null;
    var destination = typeof r.destination === "string" ? r.destination.trim() : "";
    if (!destination) return null;
    function number(v) {
        return typeof v === "number" && isFinite(v) ? v : null;
    }
    // TeslaMate gives the distance in miles whatever its own unit setting.
    var miles = number(r.miles_to_arrival);
    return {
        destination: destination,
        minutes: number(r.minutes_to_arrival),
        trafficMinutes: number(r.traffic_minutes_delay),
        energyAtArrival: number(r.energy_at_arrival),
        km: miles === null ? null : miles * 1.609344
    };
}

// TeslaMate 2.1 and newer don't retain healthy, so most polls don't see it. A value that
// arrived within maxAgeMs is kept, and seenAt stays at when it arrived so it can't live on
// forever. Returns {value, seenAt}, with value undefined once there's nothing to keep.
function carryHealthy(fresh, prevValue, prevSeenAt, nowMs, maxAgeMs) {
    if (fresh !== undefined && fresh !== null) return { value: fresh, seenAt: nowMs };
    if (prevValue !== undefined && prevSeenAt !== null && prevSeenAt !== undefined
        && nowMs - prevSeenAt <= maxAgeMs)
        return { value: prevValue, seenAt: prevSeenAt };
    return { value: undefined, seenAt: null };
}

// "Home, Work" -> ["home", "work"], so geofence names compare without regard to case or
// spacing.
function geofenceList(text) {
    var out = [];
    var names = String(text || "").split(",");
    for (var i = 0; i < names.length; i++) {
        var name = names[i].trim().toLowerCase();
        if (name) out.push(name);
    }
    return out;
}

// Shared by attention() and isResolved(), so the two agree on where unlocked is fine.
function atOkGeofence(car, okGeofences) {
    var here = String((car && car.geofence) || "").trim().toLowerCase();
    return here !== "" && (okGeofences || []).indexOf(here) >= 0;
}

// Everything that needs someone's attention, most severe first, as {id, type, part}.
// okGeofences comes from geofenceList(). A charger with no power isn't here: smart and
// solar chargers report that every evening, so the card shows it as a plain status.
function attention(car, okGeofences) {
    var items = [];
    function add(id, type, part) {
        items.push({ id: id, type: type, part: part || "" });
    }
    if (car && car.healthy === "false") add("unhealthy", "unhealthy");
    if (bool(car, "service_mode")) add("service", "service");
    for (var t = 0; t < TIRES.length; t++)
        if (bool(car, "tpms_soft_warning_" + TIRES[t])) add("tire:" + TIRES[t], "tire", TIRES[t]);
    // Only when the car says nobody is inside, so someone sitting in an unlocked car, or a
    // TeslaMate that doesn't report presence, doesn't count.
    if (triState(car, "locked") === false && !isDriving(car)
        && triState(car, "is_user_present") === false && !atOkGeofence(car, okGeofences))
        add("unlocked", "unlocked");
    var kinds = ["door", "window"];
    for (var k = 0; k < kinds.length; k++) {
        var states = parts(car, kinds[k]);
        var named = false;
        var some = false;
        for (var p = 0; p < PARTS.length; p++) {
            if (states[PARTS[p]] === true) {
                add(kinds[k] + ":" + PARTS[p], kinds[k], PARTS[p]);
                named = true;
            } else if (states[PARTS[p]] === "some") {
                some = true;
            }
        }
        // Older TeslaMate only reports that some door or window is open.
        if (!named && some) add(kinds[k] + ":some", kinds[k], "some");
    }
    if (bool(car, "frunk_open")) add("frunk", "frunk");
    if (bool(car, "trunk_open")) add("trunk", "trunk");
    if (triState(car, "sun_roof_installed") !== false && num(car, "sun_roof_percent_open") > 0)
        add("sunroof", "sunroof");
    // An open port is expected while the cable is in.
    if (bool(car, "charge_port_door_open") && !bool(car, "plugged_in")) add("port", "port");
    return items;
}

// Whether an id from attention(), or "update:<version>", is now explicitly fine. A topic
// that went empty doesn't count, so a value TeslaMate stops sending can't end a warning
// that would then start over when it comes back.
function isResolved(car, id, okGeofences) {
    var colon = id.indexOf(":");
    var type = colon < 0 ? id : id.slice(0, colon);
    var part = colon < 0 ? "" : id.slice(colon + 1);
    switch (type) {
    case "door":
    case "window": {
        var states = parts(car, type);
        if (part !== "some") return states[part] === false;
        for (var i = 0; i < PARTS.length; i++)
            if (states[PARTS[i]] !== false) return false;
        return true;
    }
    case "frunk": return triState(car, "frunk_open") === false;
    case "trunk": return triState(car, "trunk_open") === false;
    case "sunroof":
        return triState(car, "sun_roof_installed") === false || num(car, "sun_roof_percent_open") === 0;
    case "port": return triState(car, "charge_port_door_open") === false || bool(car, "plugged_in");
    case "unlocked":
        return triState(car, "locked") === true || triState(car, "is_user_present") === true
            || isDriving(car) || atOkGeofence(car, okGeofences);
    case "tire": return triState(car, "tpms_soft_warning_" + part) === false;
    case "update": return triState(car, "update_available") === false;
    default: return true;
    }
}

// Breeze battery icon name for a level (0..100).
function batteryIcon(level, charging) {
    var step = level === null ? 50 : Math.max(0, Math.min(100, Math.round(level / 10) * 10));
    var name = "battery-" + (step < 10 ? "00" : step < 100 ? "0" : "") + step;
    return charging ? name + "-charging" : name;
}

// How long to wait between polls, in ms. A sleeping car's values don't change, so once
// there's data and nobody has the popup open, the idle setting applies; it never polls
// faster than the normal rate. Without data it keeps trying at the normal rate, since the
// state isn't known yet.
function pollIntervalMs(refresh, idle, state, hasData, popupOpen) {
    var fast = Math.max(5, refresh || 15);
    var sleeping = state === "asleep" || state === "offline" || state === "suspended";
    if (hasData && !popupOpen && sleeping) return Math.max(fast, idle || 0) * 1000;
    return fast * 1000;
}

// Single-quotes a value for the shell, so hosts, topics and passwords reach mosquitto_sub
// unchanged whatever characters they contain.
function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

// Splits what people paste into the Host field, such as mqtts://user:pw@host:8883/path,
// [fd00::1]:1883 or host:1884, into its parts. tls is true or false when the scheme says
// so and null otherwise. port is null when there is none or it is out of range.
function parseBrokerHost(text) {
    var r = { host: "", port: null, tls: null, user: "", password: "" };
    var s = String(text || "").trim();
    var scheme = /^([a-z][a-z0-9+.-]*):\/\//i.exec(s);
    if (scheme) {
        var name = scheme[1].toLowerCase();
        if (["mqtts", "ssl", "tls", "wss"].indexOf(name) >= 0) r.tls = true;
        else if (["mqtt", "tcp", "ws"].indexOf(name) >= 0) r.tls = false;
        s = s.slice(scheme[0].length);
    }
    s = s.split(/[\/?#]/)[0];
    // The last @ ends the credentials, so a password may contain one.
    var at = s.lastIndexOf("@");
    if (at >= 0) {
        var cred = s.slice(0, at);
        var colon = cred.indexOf(":");
        r.user = colon < 0 ? cred : cred.slice(0, colon);
        r.password = colon < 0 ? "" : cred.slice(colon + 1);
        s = s.slice(at + 1);
    }
    var port = "";
    var bracketed = /^\[([^\]]*)\](?::(.*))?$/.exec(s);
    if (bracketed) {
        s = bracketed[1];
        port = bracketed[2] || "";
    } else if (s.indexOf(":") >= 0 && s.indexOf(":") === s.lastIndexOf(":")) {
        // A single colon separates a port; more than one is a bare IPv6 address.
        port = s.slice(s.indexOf(":") + 1);
        s = s.slice(0, s.indexOf(":"));
    }
    if (/^\d+$/.test(port)) {
        var p = parseInt(port, 10);
        if (p >= 1 && p <= 65535) r.port = p;
    }
    r.host = s;
    return r;
}

// The mosquitto_sub call shared by the widget's poll and the settings page.
// o = {host, port, user, password, tls, caFile, topics, wait}; "" when there is no host.
// -W only starts counting once the connection is up, so coreutils timeout bounds a host
// that drops packets (exit 124). timeout exits 127 itself when mosquitto_sub is missing,
// which keeps the install hint working.
function mosquittoCommand(o) {
    o = o || {};
    var b = parseBrokerHost(o.host);
    if (!b.host) return "";
    var wait = Math.max(1, Math.round(o.wait || 2));
    var given = parseInt(o.port, 10);
    var port = b.port || (given >= 1 && given <= 65535 ? given : 1883);
    var cmd = "timeout " + (wait + 10) + " mosquitto_sub -h " + shellQuote(b.host) + " -p " + port;
    var topics = o.topics || [];
    for (var i = 0; i < topics.length; i++) cmd += " -t " + shellQuote(topics[i]);
    cmd += " -v -W " + wait;
    if (o.tls || b.tls === true) {
        var ca = String(o.caFile || "").trim();
        // Only an unquoted leading ~ expands, so a home-relative path keeps it outside
        // the quotes.
        if (ca.indexOf("~/") === 0) cmd += " --cafile ~/" + shellQuote(ca.slice(2));
        else if (ca) cmd += " --cafile " + shellQuote(ca);
        else cmd += " --tls-use-os-certs";
    }
    var user = o.user || b.user;
    var password = o.password || b.password;
    if (user) cmd += " -u " + shellQuote(user);
    if (password) cmd += " -P " + shellQuote(password);
    return cmd;
}

// Sorts a failed mosquitto_sub run into a kind that QML words for people, with the detail
// a message needs. kind "" means the run was fine, even if no messages arrived.
function mqttError(code, stderr, hasOutput) {
    var e = String(stderr || "").trim();
    var plain = e.replace(/^Error:\s*/, "");
    function result(kind, detail) {
        return { kind: kind, detail: detail || "" };
    }
    if (code === 127) return result("notInstalled");
    if (code === 124) return result("noAnswer");
    if (/Unknown option '--tls-use-os-certs'/.test(e)) return result("oldClient");
    if (/Problem setting TLS options/.test(e)) return result("caFile");
    if (code === 4 || code === 5 || /not authori[sz]ed|bad user name or password/i.test(e))
        return result("auth");
    if (/Lookup error/.test(e)) return result("lookup");
    if (/Error: Connection refused/.test(e)) return result("refused");
    if (/No route to host|Network is unreachable|Connection timed out/.test(e))
        return result("unreachable", plain);
    if (code === 14 || /Protocol error/.test(e)) return result("tls");
    // A TLS broker hangs up on a plain client without a word, and so does a plain broker
    // when the client talks TLS.
    if (code === 255 && !e) return result("handshake");
    // When -W runs out, mosquitto 2.0 prints "Timed out" and exits 27; 1.6 exits 0.
    if (code === 0 || code === 27) {
        if (!hasOutput && /denied/.test(e)) return result("denied");
        if (!hasOutput && e && e !== "Timed out") return result("other", plain);
        return result("");
    }
    if (e) return result("other", plain);
    return result("exit", String(code));
}

// The cars a "Find Cars" subscription to teslamate/cars/+/display_name and
// teslamate/+/cars/+/display_name turned up, as [{prefix, name}]. Sorted by namespace and
// then by car id as a number, so car 2 comes before car 10. TeslaMate's ids are numbers;
// anything else goes after them in text order, which keeps the order consistent.
function parseCars(out) {
    var all = parseMqtt(out, "");
    var re = /^(teslamate\/(?:([^\/]+)\/)?cars\/([^\/]+))\/display_name$/;
    var found = [];
    for (var topic in all) {
        var m = re.exec(topic);
        if (m) found.push({ prefix: m[1], name: all[topic], ns: m[2] || "", id: m[3] });
    }
    found.sort(function (a, b) {
        if (a.ns !== b.ns) return a.ns < b.ns ? -1 : 1;
        var an = /^\d+$/.test(a.id), bn = /^\d+$/.test(b.id);
        if (an !== bn) return an ? -1 : 1;
        if (an && Number(a.id) !== Number(b.id)) return Number(a.id) - Number(b.id);
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });
    var cars = [];
    for (var i = 0; i < found.length; i++) cars.push({ prefix: found[i].prefix, name: found[i].name });
    return cars;
}
