.pragma library

const SECOND = 1000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;

// Parses `mosquitto_sub -v` output ("topic payload" per line) into {key: payload}, where
// key is the topic without the prefix, e.g. "battery_level". An empty prefix keeps full topics.
function parseMqtt(out, prefix) {
    const values = {};
    const base = String(prefix || "").replace(/\/+$/, "");
    const start = base ? base + "/" : "";
    for (const rawLine of String(out || "").split("\n")) {
        const line = rawLine.replace(/\r$/, "");
        if (!line) continue;
        const space = line.indexOf(" ");
        const topic = space < 0 ? line : line.slice(0, space);
        const payload = space < 0 ? "" : line.slice(space + 1);
        if (!topic.startsWith(start) || topic.length === start.length) continue;
        // TeslaMate clears a value with an empty publish, which mosquitto_sub prints as "(null)".
        values[topic.slice(start.length)] = payload === "(null)" ? "" : payload;
    }
    return values;
}

// The topic prefix from the settings, trimmed, defaulting to TeslaMate's first car.
function topicPrefix(text) {
    return String(text || "").trim().replace(/\/+$/, "") || "teslamate/cars/1";
}

function num(car, key) {
    if (!car || car[key] === undefined || car[key] === "") return null;
    const value = parseFloat(car[key]);
    return isNaN(value) ? null : value;
}

function bool(car, key) {
    return !!car && car[key] === "true";
}

// Like bool(), but null when TeslaMate hasn't reported the value.
function triState(car, key) {
    if (!car || (car[key] !== "true" && car[key] !== "false")) return null;
    return car[key] === "true";
}

// Whether one door or window is open, from its own topic (e.g. driver_front_door_open).
// Older TeslaMate only reports the total (doors_open): then this is "some" if anything is
// open, false if all are closed, null if unknown.
function partOpen(car, key, totalKey) {
    const own = triState(car, key);
    if (own !== null) return own;
    const total = triState(car, totalKey);
    return total === true ? "some" : total;
}

// TeslaMate's names for doors and windows, and for tires.
const PARTS = ["driver_front", "driver_rear", "passenger_front", "passenger_rear"];
const TIRES = ["fl", "fr", "rl", "rr"];
// attention() types that count as left open. These and "unlocked" notify after a delay.
const LEFT_OPEN = ["door", "window", "frunk", "trunk", "sunroof", "port"];
const DELAYED = LEFT_OPEN.concat("unlocked");
// Every id that trackItems() can release, tracked or not.
const TRACKABLE = (() => {
    const ids = ["frunk", "trunk", "sunroof", "port", "unlocked", "door:some", "window:some"];
    for (const part of PARTS) ids.push("door:" + part, "window:" + part);
    for (const tire of TIRES) ids.push("tire:" + tire);
    return ids;
})();

// All four doors or windows (kind is "door" or "window") as {driver_front: true, ...},
// with partOpen()'s values.
function parts(car, kind) {
    const out = {};
    for (const part of PARTS) out[part] = partOpen(car, part + "_" + kind + "_open", kind + "s_open");
    return out;
}

const MILES_PER_KM = 0.621371;
const KM_PER_MILE = 1.609344;
const PSI_PER_BAR = 14.5038;
const KPA_PER_BAR = 100;

// TeslaMate reports metric values. These convert to a unit from resolveUnits().
function distance(km, unit) {
    if (km === null) return null;
    return unit === "mi" ? km * MILES_PER_KM : km;
}

function temperature(c, unit) {
    if (c === null) return null;
    return unit === "F" ? c * 9 / 5 + 32 : c;
}

function pressure(bar, unit) {
    if (bar === null) return null;
    if (unit === "psi") return bar * PSI_PER_BAR;
    if (unit === "kPa") return bar * KPA_PER_BAR;
    return bar;
}

// The units to show, from the three Display settings and Qt's measurement system
// (0 metric, 1 US, 2 UK). The UK uses miles and psi but °C.
function resolveUnits(distanceSetting, temperatureSetting, pressureSetting, measurementSystem) {
    const us = measurementSystem === 1;
    const miles = us || measurementSystem === 2;
    // A setting is its combo box's index. 0 is Automatic: the locale's unit.
    const choose = (setting, units) => units[setting] || units[0];
    return {
        distance: choose(distanceSetting, [miles ? "mi" : "km", "km", "mi"]),
        temperature: choose(temperatureSetting, [us ? "F" : "C", "C", "F"]),
        pressure: choose(pressureSetting, [miles ? "psi" : "bar", "bar", "psi", "kPa"])
    };
}

// The settings to write when upgrading to 1.5, or null if already done. A configured
// widget keeps the units its old imperial checkbox gave; a new one stays on Automatic.
// Idempotent, in case Plasma quits before saving.
function unitMigration(migrated, brokerHost, imperial) {
    if (migrated) return null;
    const keys = { unitsMigrated: true };
    if (String(brokerHost || "").trim() !== "") {
        const unit = imperial ? 2 : 1;
        keys.distanceUnit = unit;
        keys.temperatureUnit = unit;
        keys.pressureUnit = unit;
    }
    return keys;
}

// 1.34 -> "1h 20m", 0.75 -> "45m", null or <= 0 -> ""
function formatHours(h) {
    if (h === null || h <= 0) return "";
    const mins = Math.round(h * 60);
    const hh = Math.floor(mins / 60);
    const mm = mins % 60;
    if (hh > 0) return hh + "h " + (mm < 10 ? "0" : "") + mm + "m";
    return mm + "m";
}

// ISO timestamp -> time since then as "3m", "2h" or "4d"
function formatSince(iso, nowMs) {
    const then = Date.parse(iso);
    if (isNaN(then)) return "";
    const seconds = Math.max(0, (nowMs - then) / 1000);
    if (seconds < 3600) return Math.max(1, Math.floor(seconds / 60)) + "m";
    if (seconds < 86400) return Math.floor(seconds / 3600) + "h";
    return Math.floor(seconds / 86400) + "d";
}

// After the car is put in gear, TeslaMate can report "online" for a moment before
// "driving", so D and R count as driving too.
function isDriving(car) {
    const state = car ? car.state : "";
    if (state === "driving") return true;
    const shift = car ? car.shift_state : "";
    return state === "online" && (shift === "D" || shift === "R");
}

// The charge port's status: charging, starting, complete, stopped, scheduled, nopower,
// plugged, unplugged, or "" if unknown. TeslaMate before 1.28 has no charging_state, so
// the car's state and the charger's power decide instead.
function chargeStatus(car) {
    const reported = car && car.charging_state ? car.charging_state : "";
    if (reported === "") {
        if ((car && car.state === "charging") || num(car, "charger_power") > 0) return "charging";
        const plugged = triState(car, "plugged_in");
        return plugged === null ? "" : plugged ? "plugged" : "unplugged";
    }
    switch (reported) {
    case "Charging": return "charging";
    case "Starting": return "starting";
    case "Complete": return "complete";
    case "NoPower": return "nopower";
    case "Disconnected": return "unplugged";
    // The car also reports Stopped while waiting for a scheduled start.
    case "Stopped":
        return isNaN(Date.parse(car.scheduled_charging_start_time || "")) ? "stopped" : "scheduled";
    default: return bool(car, "plugged_in") ? "plugged" : "unplugged";
    }
}

// The usable level when a cold battery holds charge back, else null. Same rule as
// TeslaMate: more than 2 points below the battery level.
function usableIfCold(car) {
    const level = num(car, "battery_level");
    const usable = num(car, "usable_battery_level");
    if (level === null || usable === null || level - usable <= 2) return null;
    return usable;
}

// A software update's {phase, percent}. phase is "", available, downloading or installing;
// percent is null when unknown.
// - Installing only while TeslaMate's state is "updating". update_available may already
//   be false by then, so that check comes first.
// - install_perc is ignored otherwise: the car often leaves a stale value (commonly 1).
// - A download at 0 or 100 isn't in progress, so it shows as available.
function updateProgress(car) {
    if (car && car.state === "updating") {
        const install = num(car, "install_perc");
        return { phase: "installing", percent: install !== null && install > 0 ? install : null };
    }
    if (!bool(car, "update_available")) return { phase: "", percent: null };
    const download = num(car, "download_perc");
    if (download !== null && download > 0 && download < 100) return { phase: "downloading", percent: download };
    return { phase: "available", percent: null };
}

// What the climate is doing, for the Climate cell: preconditioning, dog, camp, keep (keep
// climate on), defrost, on, overheat (cabin overheat protection cooling with the climate
// off), off, or null when unknown. Only the Fleet API, Teslemetry, Tessie and Home Assistant
// report all of them.
function climateMode(car) {
    if (bool(car, "is_preconditioning")) return "preconditioning";
    switch (car ? car.climate_keeper_mode : "") {
    case "dog": return "dog";
    case "camp": return "camp";
    case "on": return "keep";
    }
    if (bool(car, "is_front_defroster_on")) return "defrost";
    if (bool(car, "is_climate_on")) return "on";
    if (bool(car, "cabin_overheat_protection_actively_cooling")) return "overheat";
    return triState(car, "is_climate_on") === false ? "off" : null;
}

// When a scheduled installation of an available update starts, in ms, or null if none is
// scheduled or the time has passed. Only the Fleet API, Teslemetry and Tessie say.
function updateSchedule(car, nowMs) {
    if (!bool(car, "update_available")) return null;
    const at = Date.parse(car.update_scheduled_time || "");
    return isNaN(at) || at <= nowMs ? null : at;
}

// About how many minutes an installation has left, from how long the source says it takes
// and how far it has got, or null when either is unknown.
function installMinutesLeft(car) {
    const progress = updateProgress(car);
    const seconds = num(car, "update_duration_sec");
    if (progress.phase !== "installing" || progress.percent === null || seconds === null || seconds <= 0) return null;
    return Math.max(0, (1 - Math.min(progress.percent, 100) / 100) * seconds / 60);
}

// The charger's phase count if more than one, else null. The car can report more phases
// than the charger has, so (as TeslaMate does) the count is only trusted when the power
// matches current × voltage × phases.
function showPhases(car) {
    const phases = num(car, "charger_phases");
    const amps = num(car, "charger_actual_current");
    const volts = num(car, "charger_voltage");
    const kw = num(car, "charger_power");
    if (phases === null || phases <= 1 || amps === null || amps <= 0
        || volts === null || volts <= 0 || kw === null) return null;
    return Math.round(kw * 1000 / (amps * volts)) === phases ? phases : null;
}

// What the car is charging from, for sources that say (TeslaMate doesn't): "supercharger",
// "dc" for another DC fast charger, or "" for AC or unknown.
function chargerKind(car) {
    if (!bool(car, "fast_charger_present")) return "";
    const type = String(car.fast_charger_type || "").toLowerCase();
    const brand = String(car.fast_charger_brand || "").toLowerCase();
    return brand.includes("tesla") || type.includes("supercharger") ? "supercharger" : "dc";
}

// The active route from TeslaMate's active_route JSON (1.29+), as {destination, minutes,
// trafficMinutes, energyAtArrival, km}, or null. Missing numbers are null. With no route
// TeslaMate publishes {"error": "No active route available"}.
// The older active_route_destination topic is unreliable: no arrival details, "nil"
// between routes on 1.29+, and a stale destination on 1.28.4 and 1.28.5.
function activeRoute(car) {
    const text = car ? car.active_route : "";
    if (!text) return null;
    let route;
    try {
        route = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!route || typeof route !== "object" || Array.isArray(route) || route.error) return null;
    const destination = typeof route.destination === "string" ? route.destination.trim() : "";
    if (!destination) return null;
    function number(v) {
        return typeof v === "number" && isFinite(v) ? v : null;
    }
    // Always miles, whatever TeslaMate's unit setting.
    const miles = number(route.miles_to_arrival);
    return {
        destination: destination,
        minutes: number(route.minutes_to_arrival),
        trafficMinutes: number(route.traffic_minutes_delay),
        energyAtArrival: number(route.energy_at_arrival),
        km: miles === null ? null : miles * KM_PER_MILE
    };
}

// TeslaMate 2.1+ doesn't retain healthy, so most polls miss it. This carries the last
// value forward for up to maxAgeMs from when it arrived. Returns {value, seenAt}; value
// is undefined once it has expired.
function carryHealthy(fresh, prevValue, prevSeenAt, nowMs, maxAgeMs) {
    if (fresh !== undefined && fresh !== null) return { value: fresh, seenAt: nowMs };
    if (prevValue !== undefined && prevSeenAt !== null && prevSeenAt !== undefined
        && nowMs - prevSeenAt <= maxAgeMs)
        return { value: prevValue, seenAt: prevSeenAt };
    return { value: undefined, seenAt: null };
}

// "Home, Work" -> ["home", "work"], for case-insensitive comparison.
function geofenceList(text) {
    return String(text || "").split(",").map(name => name.trim().toLowerCase()).filter(name => name !== "");
}

// Whether the car is in a geofence where being unlocked is fine.
function atOkGeofence(car, okGeofences) {
    const here = String((car && car.geofence) || "").trim().toLowerCase();
    return here !== "" && (okGeofences || []).includes(here);
}

// Everything that needs attention, most severe first, as [{id, type, part}].
// okGeofences comes from geofenceList(). A charger without power is not included: smart
// and solar chargers report that every evening.
function attention(car, okGeofences) {
    const items = [];
    function add(id, type, part) {
        items.push({ id: id, type: type, part: part || "" });
    }
    if (car && car.healthy === "false") add("unhealthy", "unhealthy");
    if (bool(car, "service_mode")) add("service", "service");
    for (const tire of TIRES)
        if (bool(car, "tpms_soft_warning_" + tire)) add("tire:" + tire, "tire", tire);
    // Only when the car reports nobody inside. A TeslaMate that doesn't report presence
    // never triggers this.
    if (triState(car, "locked") === false && !isDriving(car)
        && triState(car, "is_user_present") === false && !atOkGeofence(car, okGeofences))
        add("unlocked", "unlocked");
    for (const kind of ["door", "window"]) {
        const states = parts(car, kind);
        const open = PARTS.filter(part => states[part] === true);
        for (const part of open) add(kind + ":" + part, kind, part);
        // Older TeslaMate only reports the total.
        if (open.length === 0 && PARTS.some(part => states[part] === "some")) add(kind + ":some", kind, "some");
    }
    if (bool(car, "frunk_open")) add("frunk", "frunk");
    if (bool(car, "trunk_open")) add("trunk", "trunk");
    if (triState(car, "sun_roof_installed") !== false && num(car, "sun_roof_percent_open") > 0)
        add("sunroof", "sunroof");
    // An open port is expected while plugged in.
    if (bool(car, "charge_port_door_open") && !bool(car, "plugged_in")) add("port", "port");
    return items;
}

// "door:driver_front" -> {type: "door", part: "driver_front"}; "frunk" -> part "".
function splitId(id) {
    const colon = id.indexOf(":");
    return colon < 0 ? { type: id, part: "" } : { type: id.slice(0, colon), part: id.slice(colon + 1) };
}

// Whether an id from attention(), or "update:<version>", is explicitly fine now. An empty
// topic doesn't count: otherwise a value TeslaMate stops sending would end a warning,
// which would then repeat when the value came back.
function isResolved(car, id, okGeofences) {
    const { type, part } = splitId(id);
    switch (type) {
    case "door":
    case "window": {
        const states = parts(car, type);
        if (part !== "some") return states[part] === false;
        return PARTS.every(p => states[p] === false);
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

// The charge state notifyStep() keeps between snapshots: whether the car has charged since
// plugging in and from what level, which notifications were sent, and a stop that is
// waiting to be confirmed.
function chargeSession(status) {
    return { status: status, startLevel: null, wasCharging: false, stopDone: false,
             noPowerDone: false, pending: null };
}

// The charging half of notifyStep(). prev is the previous session, or null to start over.
// Returns {session, events, released}.
//
// A charge that stops early, or a charger that loses power, notifies at most once per
// plug-in, and only after lasting two snapshots and holdMs, so a brief pause doesn't
// count. Unplugging, waiting for a schedule and a top-up of less than 3% stay quiet.
function trackCharge(prev, car, nowMs, holdMs) {
    const status = chargeStatus(car);
    const level = num(car, "battery_level");
    const limit = num(car, "charge_limit_soc");
    // Once charging again, the next finish or stop belongs to a new charge.
    const released = status !== "charging" ? []
        : ["chargeComplete", "chargeStopped", "chargerNoPower"].map(type => eventKey({ type: type }));
    const events = [];

    if (!prev) {
        const session = chargeSession(status);
        if (status === "charging") {
            session.wasCharging = true;
            session.startLevel = level;
        }
        return { session: session, events: events, released: released };
    }

    // A charge that added less than 3% is the car topping itself up.
    const worthTelling = prev.startLevel === null || level === null || level - prev.startLevel >= 3;
    let session = Object.assign({}, prev, { pending: prev.pending ? Object.assign({}, prev.pending) : null });
    switch (status) {
    case "charging":
        session.wasCharging = true;
        if (session.startLevel === null) session.startLevel = level;
        session.pending = null;
        break;
    case "starting":
    case "scheduled":
        session.pending = null;
        break;
    case "unplugged":
        session = chargeSession(status);
        break;
    case "complete":
        if (session.wasCharging && worthTelling) events.push({ type: "chargeComplete", level: level });
        session = chargeSession(status);
        break;
    case "stopped":
    case "plugged":
    case "nopower": {
        if (!session.wasCharging) {
            session.pending = null;
            break;
        }
        const kind = status === "nopower" ? "nopower" : "stop";
        session.pending = session.pending && session.pending.kind === kind
            ? { kind: kind, since: session.pending.since, count: session.pending.count + 1 }
            : { kind: kind, since: nowMs, count: 1 };
        if (session.pending.count < 2 || nowMs - session.pending.since < holdMs) break;
        if (kind === "stop" && level !== null && limit !== null && level >= limit - 1) {
            // TeslaMate before 1.28 has no Complete: stopping at the limit means the same.
            if (worthTelling) events.push({ type: "chargeComplete", level: level });
            session = chargeSession(status);
            break;
        }
        if (kind === "stop" && !session.stopDone)
            events.push({ type: "chargeStopped", level: level, limit: limit });
        if (kind === "nopower" && !session.noPowerDone)
            events.push({ type: "chargerNoPower", level: level });
        if (kind === "stop") session.stopDone = true;
        else session.noPowerDone = true;
        session.wasCharging = false;
        session.pending = null;
        break;
    }
    }
    // An empty status keeps the previous one.
    if (status !== "") session.status = status;
    return { session: session, events: events, released: released };
}

// The other half of notifyStep(): things left open, the unlocked car, tires and updates.
// old is the previous {id: {since, done}}. first means this snapshot only records the
// current state. Returns {tracked, events, released}.
//
// Left-open items and the unlocked car notify after leftOpenMs with nobody in the car.
// Tires and updates notify on the next snapshot.
function trackItems(old, car, nowMs, first, leftOpenMs, okGeofences) {
    const unattended = !isDriving(car) && triState(car, "is_user_present") !== true;
    const candidates = attention(car, okGeofences)
        .filter(item => DELAYED.includes(item.type) || item.type === "tire");
    if (bool(car, "update_available"))
        candidates.push({ id: "update:" + (car.update_version || ""), type: "update", part: "" });

    const tracked = {};
    const due = [];
    for (const item of candidates) {
        const was = old[item.id];
        const entry = was ? { since: was.since, done: was.done } : { since: nowMs, done: first };
        const delayed = DELAYED.includes(item.type);
        if (delayed && !unattended) entry.since = nowMs;
        const waited = !delayed || (unattended && nowMs - entry.since >= leftOpenMs);
        if (!entry.done && waited) {
            entry.done = true;
            due.push(item);
        }
        tracked[item.id] = entry;
    }
    // An item that disappeared is only dropped once its value says it's fine. If its topic
    // went empty it is kept, so it doesn't notify again when the value returns.
    const released = [];
    function release(key) {
        if (!released.includes(key)) released.push(key);
    }
    for (const id in old) {
        if (tracked.hasOwnProperty(id)) continue;
        if (isResolved(car, id, okGeofences)) release(itemKey(id));
        else tracked[id] = { since: old[id].since, done: old[id].done };
    }
    // Release whatever is fine even if this copy wasn't tracking it: another copy, or this
    // one before a gap, may hold the claim.
    for (const id of TRACKABLE) {
        if (isResolved(car, id, okGeofences)) release(itemKey(id));
    }

    const leftOpen = due.filter(item => LEFT_OPEN.includes(item.type));
    const tires = due.filter(item => item.type === "tire").map(item => item.part);
    const events = [];
    if (leftOpen.length > 0) events.push({ type: "leftOpen", items: leftOpen });
    if (due.some(item => item.type === "unlocked")) events.push({ type: "unlocked" });
    if (tires.length > 0) events.push({ type: "tires", items: tires });
    if (due.some(item => item.type === "update")) events.push({ type: "update", version: car.update_version || "" });
    return { tracked: tracked, events: events, released: released };
}

// Decides which notifications a new snapshot calls for. Pass the returned state back in
// with the next snapshot; prev is null at the start.
// opts = {leftOpenMs, staleMs, holdMs, okGeofences}.
// Returns {state, events, released}: events are [{type, ...}] for QML to word, and
// released lists the claim keys (see claimEvent) of what is fine again.
//
// Notifications are for changes. The first snapshot, and the first after a gap longer
// than staleMs (a suspend or broker outage), only record the current state.
// See trackItems() and trackCharge() for the rules.
function notifyStep(prev, car, nowMs, opts) {
    const { leftOpenMs = 10 * MINUTE, staleMs = 15 * MINUTE, holdMs = 3 * MINUTE, okGeofences = [] } = opts || {};
    // A clock set back also starts over, or every timer would be in the future.
    const gap = prev ? nowMs - prev.at : NaN;
    const first = !(gap >= 0 && gap <= staleMs);
    const items = trackItems(first ? {} : prev.tracked || {}, car, nowMs, first, leftOpenMs, okGeofences);
    const charge = trackCharge(first ? null : prev.charge, car, nowMs, holdMs);
    return {
        state: { at: nowMs, charge: charge.session, tracked: items.tracked },
        events: first ? [] : charge.events.concat(items.events),
        released: items.released.concat(charge.released)
    };
}

// The identity of an event, so copies of the widget showing the same car can tell they
// saw the same one. Charge events are keyed by type alone: copies see a charge end at
// different times, and the car's `since` can change in between.
function eventKey(event) {
    switch (event.type) {
    case "update": return "update|" + (event.version || "");
    case "unlocked": return "unlocked";
    case "tires":
    case "leftOpen": {
        const keys = event.items.map(item => event.type === "tires" ? item : item.id).sort();
        return event.type + "|" + keys.join(",");
    }
    default: return event.type;
    }
}

// The eventKey() for an id that trackItems() tracks.
function itemKey(id) {
    const { type, part } = splitId(id);
    if (type === "unlocked") return eventKey({ type: "unlocked" });
    if (type === "tire") return eventKey({ type: "tires", items: [part] });
    if (type === "update") return eventKey({ type: "update", version: part });
    return eventKey({ type: "leftOpen", items: [{ id: id }] });
}

// The part of an event this copy of the widget should send, or null if other copies
// already sent all of it. claim(key, windowMs) is notifyhub.js's claim() for this car.
//
// Each left-open item and each low tire is claimed separately, because copies poll at
// different times and may group them differently. A claim lasts until notifyStep()
// releases it, or two hours: twice the longest poll interval the settings allow.
function claimEvent(event, claim) {
    const windowMs = 2 * HOUR;
    if (!event.items) return claim(eventKey(event), windowMs) ? event : null;
    const items = event.items.filter(item => claim(eventKey({ type: event.type, items: [item] }), windowMs));
    if (items.length === 0) return null;
    return Object.assign({}, event, { items: items });
}

// The Breeze battery icon for a level (0..100, or null if unknown).
function batteryIcon(level, charging) {
    const step = level === null ? 50 : Math.max(0, Math.min(100, Math.round(level / 10) * 10));
    const name = "battery-" + String(step).padStart(3, "0");
    return charging ? name + "-charging" : name;
}

// Tesla's paints, matched by a word in the name. Most specific first, so that
// "MidnightCherryRed" isn't matched as Midnight Silver or Red, nor "Quicksilver" as
// Silver. Colors are approximate; black is lightened so the drawing's shading shows.
const PAINTS = [
    ["cherry", "#5a1a25"],
    ["ultrared", "#b5141f"],
    ["red", "#a31e27"],
    ["glacier", "#a3b9c9"],
    ["marine", "#2c5a7a"],
    ["blue", "#1f3f77"],
    ["pearl", "#f0f1f2"],
    ["white", "#f0f1f2"],
    ["black", "#17191c"],
    ["midnight", "#44484d"],
    ["stealth", "#4a4d51"],
    ["quicksilver", "#a2a6aa"],
    ["steel", "#6c7074"],
    ["titanium", "#7a6a5b"],
    ["copper", "#7a6a5b"],
    ["silver", "#bfc2c6"],
    ["grey", "#6c7074"],
    ["gray", "#6c7074"],
    ["brown", "#4c3629"],
    ["green", "#1f4b3a"]
];

// The "#rrggbb" for TeslaMate's exterior_color (e.g. "DeepBlue"), or "" if unknown.
// Case, spaces and punctuation are ignored: the same paint is reported as "RedMulticoat"
// or "Red" depending on the car's age.
function paintColor(name) {
    const paint = String(name || "").toLowerCase().replace(/[^a-z]/g, "");
    for (const [word, color] of PAINTS) {
        if (paint.includes(word)) return color;
    }
    return "";
}

// Milliseconds between polls. The idle rate applies when the car is asleep, there is
// data, and the popup is closed. It is never faster than the normal rate.
function pollIntervalMs(refresh, idle, state, hasData, popupOpen) {
    const fast = Math.max(5, refresh || 15);
    const sleeping = state === "asleep" || state === "offline" || state === "suspended";
    if (hasData && !popupOpen && sleeping) return Math.max(fast, idle || 0) * SECOND;
    return fast * SECOND;
}

// Single-quotes a value for the shell.
function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

// Splits what people paste into the Host field (mqtts://user:pw@host:8883/path,
// [fd00::1]:1883, host:1884) into {host, port, tls, user, password}. tls is null unless
// the scheme decides it. port is null if absent or out of range.
function parseBrokerHost(text) {
    const broker = { host: "", port: null, tls: null, user: "", password: "" };
    let rest = String(text || "").trim();
    const scheme = /^([a-z][a-z0-9+.-]*):\/\//i.exec(rest);
    if (scheme) {
        const name = scheme[1].toLowerCase();
        if (["mqtts", "ssl", "tls", "wss"].includes(name)) broker.tls = true;
        else if (["mqtt", "tcp", "ws"].includes(name)) broker.tls = false;
        rest = rest.slice(scheme[0].length);
    }
    rest = rest.split(/[\/?#]/)[0];
    // Split at the last @, since a password may contain one.
    const at = rest.lastIndexOf("@");
    if (at >= 0) {
        const credentials = rest.slice(0, at);
        const colon = credentials.indexOf(":");
        broker.user = colon < 0 ? credentials : credentials.slice(0, colon);
        broker.password = colon < 0 ? "" : credentials.slice(colon + 1);
        rest = rest.slice(at + 1);
    }
    let port = "";
    const bracketed = /^\[([^\]]*)\](?::(.*))?$/.exec(rest);
    if (bracketed) {
        rest = bracketed[1];
        port = bracketed[2] || "";
    } else if (rest.split(":").length === 2) {
        // One colon separates a port. More than one is a bare IPv6 address.
        [rest, port] = rest.split(":");
    }
    if (/^\d+$/.test(port)) {
        const number = parseInt(port, 10);
        if (number >= 1 && number <= 65535) broker.port = number;
    }
    broker.host = rest;
    return broker;
}

// Turns an address as typed (teslamate.local:4000) into a URL by adding http:// if it
// has no scheme. "" stays "".
function normalizeUrl(text) {
    const url = String(text || "").trim();
    if (!url) return "";
    return /^[a-z][a-z0-9+.-]*:\/\//i.test(url) ? url : "http://" + url;
}

// The web page a URL from normalizeUrl() may open: only http and https, so a setting can't
// hand the browser, or another handler, a file or some other kind of address. "" if not.
function webUrl(text) {
    const url = normalizeUrl(text);
    return /^https?:\/\/[^\/?#\s]/i.test(url) && !/\s/.test(url) ? url : "";
}

// The mosquitto_sub command line, or "" without a host.
// options = {host, port, user, password, keyringId, tls, caFile, topics, wait}. With a
// keyringId, the password comes from the wallet (see keyringPipeline) and options.password
// is ignored.
// -W only counts once connected, so `timeout` bounds a host that drops packets (exit 124).
// `timeout` itself exits 127 if mosquitto_sub is missing.
function mosquittoCommand(options) {
    options = options || {};
    const broker = parseBrokerHost(options.host);
    if (!broker.host) return "";
    const wait = Math.max(1, Math.round(options.wait || 2));
    const given = parseInt(options.port, 10);
    const port = broker.port || (given >= 1 && given <= 65535 ? given : 1883);
    const args = ["timeout", wait + 10, "mosquitto_sub", "-h", shellQuote(broker.host), "-p", port];
    for (const topic of options.topics || []) args.push("-t", shellQuote(topic));
    args.push("-v", "-W", wait);
    if (options.tls || broker.tls === true) {
        const caFile = String(options.caFile || "").trim();
        // The shell only expands an unquoted leading ~.
        if (caFile.startsWith("~/")) args.push("--cafile", "~/" + shellQuote(caFile.slice(2)));
        else if (caFile) args.push("--cafile", shellQuote(caFile));
        else args.push("--tls-use-os-certs");
    }
    const user = options.user || broker.user;
    const password = options.password || broker.password;
    if (user) args.push("-u", shellQuote(user));
    // mosquitto_sub refuses a password without a username, so a password left over after
    // the username was cleared is dropped.
    if (user && options.keyringId) return keyringPipeline(options.keyringId, args.join(" "));
    if (user && password) args.push("-P", shellQuote(password));
    return args.join(" ");
}

// The Secret Service attributes of one of a widget's secrets, as secret-tool arguments.
// Each secret has an id of its own in the settings (keyringId, apiKeyringId).
function keyringAttributes(id) {
    return "service 'net.moseph.teslamonitor' widget " + shellQuote(id || "");
}

// A new id for a secret. It only names the entry, so it only has to be unlikely to repeat.
// now and random are Date.now() and Math.random().
function newKeyringId(now, random) {
    return Math.floor(now).toString(36) + "-" + Math.floor(random * 2176782336).toString(36);
}

// Prints a secret with no newline after it. A search never asks to unlock the wallet, so
// an empty id, which matches nothing, checks for secret-tool and a Secret Service quietly.
function keyringLookupCommand(id) {
    return "secret-tool lookup " + keyringAttributes(id);
}

// Saves a secret under id, then deletes the entry under oldId, if any. printf is a shell
// builtin, so the secret reaches secret-tool through a pipe; it's on this shell's command
// line only while the job runs. The job runs in the background and the shell waits for
// it, because closing the settings kills the shell and the job must not die halfway. The
// exit status is the store's: a failed delete only leaves an unused entry.
function keyringStoreCommand(id, label, secret, oldId) {
    let job = "printf '%s' " + shellQuote(secret) + " | secret-tool store --label="
        + shellQuote(label) + " " + keyringAttributes(id);
    if (oldId && oldId !== id)
        job += " && { secret-tool clear " + keyringAttributes(oldId) + " || true; }";
    return "(" + job + ") & wait $!";
}

// Deletes a secret, in the background for the same reason as the store.
function keyringClearCommand(id) {
    return "(secret-tool clear " + keyringAttributes(id) + ") & wait $!";
}

// A secret-tool result as {status, value, detail}. status is "ok" (value is the secret, for
// a lookup), "notFound" (no match, or the wallet stayed locked: secret-tool can't tell
// them apart), "missing" (no secret-tool) or "error" (detail says why, such as no Secret
// Service running).
function keyringResult(code, stdout, stderr) {
    const message = String(stderr || "").trim().replace(/^secret-tool:\s*/, "");
    function result(status, value, detail) {
        return { status: status, value: value || "", detail: detail || "" };
    }
    if (code === 0) return result("ok", String(stdout || ""));
    if (code === 127) return result("missing");
    if (code === 1 && !message) return result("notFound");
    return result("error", "", message || String(code));
}

// The settings that hold the online services' tokens. They're kept together, as one
// secret in the wallet.
function tokenSettings() {
    return ["apiAccessToken", "apiRefreshToken", "teslemetryToken", "tessieToken", "teslamateApiToken", "haToken"];
}

// Several secrets as one text for the wallet: the non-empty ones of values under their
// keys, in the order of keys, so the same values always give the same text. "" if all are
// empty.
function packSecrets(values, keys) {
    const packed = {};
    let any = false;
    for (const key of keys) {
        const value = String((values || {})[key] || "").trim();
        if (!value) continue;
        packed[key] = value;
        any = true;
    }
    return any ? JSON.stringify(packed) : "";
}

// packSecrets()'s text back as {key: value} for every one of keys, "" for a missing one,
// or null if it isn't such a text.
function unpackSecrets(text, keys) {
    let json;
    try {
        json = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!json || typeof json !== "object" || Array.isArray(json)) return null;
    const values = {};
    for (const key of keys) {
        if (json[key] !== undefined && typeof json[key] !== "string") return null;
        values[key] = json[key] || "";
    }
    return values;
}

// Runs a mosquitto_sub command with the password from the wallet, off every command line:
// the shell reads it into a variable, and printf pipes it into mosquitto_sub's default
// options file ($XDG_CONFIG_HOME/mosquitto_sub, read since mosquitto 1.4), which is a link
// to stdin in a directory of its own. So a ~/.config/mosquitto_sub of the user's isn't
// read. That file takes lines of up to 1023 bytes, and the rest of a longer line reads as
// an option, so a password over 1000 bytes goes on the command line after all, where -P
// beats the file. If the wallet doesn't give the password, the command exits 75 (76
// without secret-tool) before mosquitto_sub runs.
function keyringPipeline(id, mosquitto) {
    return "pw=$(" + keyringLookupCommand(id) + "); s=$?; "
        + "case $s in 0) ;; 127) exit 76 ;; *) exit 75 ;; esac; "
        + "[ -n \"$pw\" ] || exit 75; "
        + "opt=\"-P $pw\"; set --; "
        + "if [ \"$(LC_ALL=C; echo ${#pw})\" -gt 1000 ]; then opt=\"#\"; set -- -P \"$pw\"; fi; "
        + "d=$(mktemp -d) || exit 1; "
        + "ln -s /dev/stdin \"$d/mosquitto_sub\" && "
        + "printf '%s\\n' \"$opt\" | XDG_CONFIG_HOME=\"$d\" " + mosquitto + " \"$@\"; "
        + "s=$?; rm -r \"$d\"; exit $s";
}

// Classifies a mosquitto_sub result as {kind, detail} for QML to word. kind "" means
// success, even if no messages arrived.
function mqttError(code, stderr, hasOutput) {
    const message = String(stderr || "").trim();
    const plain = message.replace(/^Error:\s*/, "");
    function result(kind, detail) {
        return { kind: kind, detail: detail || "" };
    }
    if (code === 127) return result("notInstalled");
    if (code === 124) return result("noAnswer");
    // keyringPipeline's own codes, with secret-tool's complaint, if any, as the detail.
    if (code === 75) return result("keyring", message.replace(/^secret-tool:\s*/, ""));
    if (code === 76) return result("keyringMissing");
    if (/Unknown option '--tls-use-os-certs'/.test(message)) return result("oldClient");
    if (/Problem setting TLS options/.test(message)) return result("caFile");
    if (code === 4 || code === 5 || /not authori[sz]ed|bad user name or password/i.test(message))
        return result("auth");
    if (/Lookup error/.test(message)) return result("lookup");
    if (/Error: Connection refused/.test(message)) return result("refused");
    if (/No route to host|Network is unreachable|Connection timed out/.test(message))
        return result("unreachable", plain);
    if (code === 14 || /Protocol error/.test(message)) return result("tls");
    // A TLS broker silently hangs up on a plain client, and vice versa.
    if (code === 255 && !message) return result("handshake");
    // When -W runs out, mosquitto 2.0 prints "Timed out" and exits 27; 1.6 exits 0.
    if (code === 0 || code === 27) {
        if (!hasOutput && /denied/.test(message)) return result("denied");
        if (!hasOutput && message && message !== "Timed out") return result("other", plain);
        return result("");
    }
    if (message) return result("other", plain);
    return result("exit", String(code));
}

// The cars found by subscribing to teslamate/cars/+/display_name and
// teslamate/+/cars/+/display_name, as [{prefix, name}]. Sorted by namespace, then by
// numeric car id (2 before 10), then non-numeric ids as text.
function parseCars(out) {
    const all = parseMqtt(out, "");
    const re = /^(teslamate\/(?:([^\/]+)\/)?cars\/([^\/]+))\/display_name$/;
    const found = [];
    for (const topic in all) {
        const match = re.exec(topic);
        if (match) found.push({ prefix: match[1], name: all[topic], ns: match[2] || "", id: match[3] });
    }
    const numeric = id => /^\d+$/.test(id);
    found.sort((a, b) => {
        if (a.ns !== b.ns) return a.ns < b.ns ? -1 : 1;
        if (numeric(a.id) !== numeric(b.id)) return numeric(a.id) ? -1 : 1;
        if (numeric(a.id) && Number(a.id) !== Number(b.id)) return Number(a.id) - Number(b.id);
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });
    return found.map(car => ({ prefix: car.prefix, name: car.name }));
}

// Plasma renders a notification's body as markup.
function escapeMarkup(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Replaces < and > with look-alikes, so a label that guesses whether text is markup
// (Text.AutoText, as message boxes and combo boxes use) can never take a car's name or a
// server's reply for HTML, which could load images from anywhere or show fake links.
function noMarkup(s) {
    return String(s === undefined || s === null ? "" : s).replace(/</g, "\u2039").replace(/>/g, "\u203a");
}

// Text a server or mosquitto_sub sent, as a detail in a message: on one line, without
// control characters or markup, and cut to max characters (300 by default) so a long
// error page can't fill the screen.
function plainDetail(s, max) {
    const limit = max > 1 ? max : 300;
    let text = noMarkup(s).replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ")
        .replace(/\s+/g, " ").trim();
    if (text.length > limit) text = text.slice(0, limit - 1).replace(/\s+$/, "") + "\u2026";
    return text;
}
