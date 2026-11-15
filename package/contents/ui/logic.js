.pragma library

const SECOND = 1000;
const MINUTE = 60 * SECOND;
const HOUR = 60 * MINUTE;

// Parse `mosquitto_sub -v` output ("topic payload" per line) into { key: payload }
// where key is the topic with the prefix stripped, e.g. "battery_level". An empty
// prefix keeps the full topics.
function parseMqtt(out, prefix) {
    const map = {};
    const base = String(prefix || "").replace(/\/+$/, "");
    const pre = base ? base + "/" : "";
    for (const rawLine of String(out || "").split("\n")) {
        const line = rawLine.replace(/\r$/, "");
        if (!line) continue;
        const sp = line.indexOf(" ");
        const topic = sp < 0 ? line : line.slice(0, sp);
        const payload = sp < 0 ? "" : line.slice(sp + 1);
        if (topic.indexOf(pre) !== 0 || topic.length === pre.length) continue;
        // mosquitto_sub prints an empty publish, which is how TeslaMate clears a value,
        // as "(null)". It must read as missing rather than show up as text.
        map[topic.slice(pre.length)] = payload === "(null)" ? "" : payload;
    }
    return map;
}

function num(car, key) {
    if (!car || car[key] === undefined || car[key] === "") return null;
    const value = parseFloat(car[key]);
    return isNaN(value) ? null : value;
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
    const own = triState(car, key);
    if (own !== null) return own;
    const total = triState(car, totalKey);
    return total === true ? "some" : total;
}

// TeslaMate names doors and windows by driver and passenger side, and tires by position.
const PARTS = ["driver_front", "driver_rear", "passenger_front", "passenger_rear"];
const TIRES = ["fl", "fr", "rl", "rr"];
// The attention() types that count as left open. Those, and the unlocked car, notify only
// after a delay.
const LEFT_OPEN = ["door", "window", "frunk", "trunk", "sunroof", "port"];
const DELAYED = LEFT_OPEN.concat("unlocked");
// Every id attention() can give for something left open, the unlocked car or a tire, so a
// snapshot can say which of them are fine whether or not this copy was tracking them.
const TRACKABLE = (() => {
    const ids = ["frunk", "trunk", "sunroof", "port", "unlocked", "door:some", "window:some"];
    for (const part of PARTS) ids.push("door:" + part, "window:" + part);
    for (const tire of TIRES) ids.push("tire:" + tire);
    return ids;
})();

// Every door or window (kind "door" or "window") by its TeslaMate name, as partOpen() reads
// it, e.g. {driver_front: true, driver_rear: false, ...}.
function parts(car, kind) {
    const out = {};
    for (const part of PARTS) out[part] = partOpen(car, part + "_" + kind + "_open", kind + "s_open");
    return out;
}

const MILES_PER_KM = 0.621371;
const KM_PER_MILE = 1.609344;
const PSI_PER_BAR = 14.5038;
const KPA_PER_BAR = 100;

// TeslaMate reports metric values. These convert them to a unit from resolveUnits().
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

// The units to show, from the three Display settings and Qt's measurement system for the
// locale (0 metric, 1 US, 2 UK). The UK drives in miles and fills tires in psi but gives
// temperatures in °C.
function resolveUnits(distanceSetting, temperatureSetting, pressureSetting, measurementSystem) {
    const us = measurementSystem === 1;
    const miles = us || measurementSystem === 2;
    // A setting is an index into its combo box, where 0 is Automatic: the locale's unit.
    const choose = (setting, units) => units[setting] || units[0];
    return {
        distance: choose(distanceSetting, [miles ? "mi" : "km", "km", "mi"]),
        temperature: choose(temperatureSetting, [us ? "F" : "C", "C", "F"]),
        pressure: choose(pressureSetting, [miles ? "psi" : "bar", "bar", "psi", "kPa"])
    };
}

// The settings to write the first time 1.5 runs, or null once that has happened. An
// existing widget, which has a broker host, keeps the units the old imperial checkbox gave
// it; a new one stays on Automatic. Writing the result again changes nothing, so it's safe
// if Plasma quits before it saves.
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

// Hours (float) -> "1h 20m" / "45m"
function formatHours(h) {
    if (h === null || h <= 0) return "";
    const mins = Math.round(h * 60);
    const hh = Math.floor(mins / 60);
    const mm = mins % 60;
    if (hh > 0) return hh + "h " + (mm < 10 ? "0" : "") + mm + "m";
    return mm + "m";
}

// ISO timestamp -> compact elapsed time "3m" / "2h" / "4d"
function formatSince(iso, nowMs) {
    const then = Date.parse(iso);
    if (isNaN(then)) return "";
    const seconds = Math.max(0, (nowMs - then) / 1000);
    if (seconds < 3600) return Math.max(1, Math.floor(seconds / 60)) + "m";
    if (seconds < 86400) return Math.floor(seconds / 3600) + "h";
    return Math.floor(seconds / 86400) + "d";
}

// TeslaMate can still say "online" for a moment after the car is put in gear, before it
// starts recording a drive, so D and R count as driving too.
function isDriving(car) {
    const state = car ? car.state : "";
    if (state === "driving") return true;
    const shift = car ? car.shift_state : "";
    return state === "online" && (shift === "D" || shift === "R");
}

// What the charge port is doing, as a key the card words: charging, starting, complete,
// stopped, scheduled, nopower, plugged, unplugged, or "" while nothing says. TeslaMate
// before 1.28 has no charging_state, so then the car's state and the charger's power decide.
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
    const level = num(car, "battery_level");
    const usable = num(car, "usable_battery_level");
    if (level === null || usable === null || level - usable <= 2) return null;
    return usable;
}

// A software update's phase ("", available, downloading or installing) and its percent,
// or null when that isn't known. The car is installing only while TeslaMate's state is
// "updating", and update_available may already be false by then, so that state comes first.
// install_perc alone isn't trusted: the car often reports a leftover value, commonly 1,
// while an update is only available or scheduled. A download at 0 or 100 isn't under way,
// so the update then just shows as available.
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

// The charger's phase count when it's more than one, or null. The car can report more
// phases than a charger has, so, as TeslaMate does, the count is trusted only when the
// power matches current × voltage × phases.
function showPhases(car) {
    const phases = num(car, "charger_phases");
    const amps = num(car, "charger_actual_current");
    const volts = num(car, "charger_voltage");
    const kw = num(car, "charger_power");
    if (phases === null || phases <= 1 || amps === null || amps <= 0
        || volts === null || volts <= 0 || kw === null) return null;
    return Math.round(kw * 1000 / (amps * volts)) === phases ? phases : null;
}

// The route the car is navigating, from TeslaMate's active_route JSON (1.29 and newer), as
// {destination, minutes, trafficMinutes, energyAtArrival, km}, or null. Without a route
// TeslaMate publishes {"error": "No active route available"}; with one, error is null. The
// older active_route_destination topic isn't used: it has no arrival details, reads "nil"
// between routes on 1.29 and newer, and kept the last destination on 1.28.4 and 1.28.5.
// Numbers TeslaMate leaves out are null.
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
    // TeslaMate gives the distance in miles whatever its own unit setting.
    const miles = number(route.miles_to_arrival);
    return {
        destination: destination,
        minutes: number(route.minutes_to_arrival),
        trafficMinutes: number(route.traffic_minutes_delay),
        energyAtArrival: number(route.energy_at_arrival),
        km: miles === null ? null : miles * KM_PER_MILE
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
    return String(text || "").split(",").map(name => name.trim().toLowerCase()).filter(name => name !== "");
}

// Shared by attention() and isResolved(), so the two agree on where unlocked is fine.
function atOkGeofence(car, okGeofences) {
    const here = String((car && car.geofence) || "").trim().toLowerCase();
    return here !== "" && (okGeofences || []).indexOf(here) >= 0;
}

// Everything that needs someone's attention, most severe first, as {id, type, part}.
// okGeofences comes from geofenceList(). A charger with no power isn't here: smart and
// solar chargers report that every evening, so the card shows it as a plain status.
function attention(car, okGeofences) {
    const items = [];
    function add(id, type, part) {
        items.push({ id: id, type: type, part: part || "" });
    }
    if (car && car.healthy === "false") add("unhealthy", "unhealthy");
    if (bool(car, "service_mode")) add("service", "service");
    for (const tire of TIRES)
        if (bool(car, "tpms_soft_warning_" + tire)) add("tire:" + tire, "tire", tire);
    // Only when the car says nobody is inside, so someone sitting in an unlocked car, or a
    // TeslaMate that doesn't report presence, doesn't count.
    if (triState(car, "locked") === false && !isDriving(car)
        && triState(car, "is_user_present") === false && !atOkGeofence(car, okGeofences))
        add("unlocked", "unlocked");
    for (const kind of ["door", "window"]) {
        const states = parts(car, kind);
        const open = PARTS.filter(part => states[part] === true);
        for (const part of open) add(kind + ":" + part, kind, part);
        // Older TeslaMate only reports that some door or window is open.
        if (open.length === 0 && PARTS.some(part => states[part] === "some")) add(kind + ":some", kind, "some");
    }
    if (bool(car, "frunk_open")) add("frunk", "frunk");
    if (bool(car, "trunk_open")) add("trunk", "trunk");
    if (triState(car, "sun_roof_installed") !== false && num(car, "sun_roof_percent_open") > 0)
        add("sunroof", "sunroof");
    // An open port is expected while the cable is in.
    if (bool(car, "charge_port_door_open") && !bool(car, "plugged_in")) add("port", "port");
    return items;
}

// An id from attention() or "update:<version>" as its {type, part}: "door:driver_front" is
// the driver_front door, and "frunk" has no part.
function splitId(id) {
    const colon = id.indexOf(":");
    return colon < 0 ? { type: id, part: "" } : { type: id.slice(0, colon), part: id.slice(colon + 1) };
}

// Whether an id from attention(), or "update:<version>", is now explicitly fine. A topic
// that went empty doesn't count, so a value TeslaMate stops sending can't end a warning
// that would then start over when it comes back.
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

// What notifyStep() remembers about a charge between snapshots, starting with nothing known
// but the charge port's status: whether the car has charged since, and from which level;
// whether the session has had its notifications; and a stop that has yet to last.
function chargeSession(status) {
    return { status: status, startLevel: null, wasCharging: false, stopDone: false,
             noPowerDone: false, pending: null };
}

// The charging half of notifyStep(): the session after this snapshot, the events it calls
// for, and the claim keys it ends. prev is the session before it, or null to start over.
//
// A charge that stops early, or a charger that loses power, notifies at most once per
// plug-in, and only after it has lasted for two snapshots and holdMs, so a charger that
// pauses for a moment doesn't count. Unplugging, waiting for a schedule and a top-up that
// adds less than 3% stay quiet.
function trackCharge(prev, car, nowMs, holdMs) {
    const status = chargeStatus(car);
    const level = num(car, "battery_level");
    const limit = num(car, "charge_limit_soc");
    // A charge under way means the next finish or stop belongs to a new charge.
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

    // A charge that added less than 3% is the car topping itself up, not worth a word.
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
            // Reaching the limit is how TeslaMate before 1.28 says Complete, so it's
            // treated the same way, including the new session that follows.
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
    // An empty status says nothing new, so the previous one stands.
    if (status !== "") session.status = status;
    return { session: session, events: events, released: released };
}

// The other half of notifyStep(): things left open and the unlocked car, with a timer that
// only runs while nobody is in the car; tires and updates, which notify on the next
// snapshot. old is what was tracked before this snapshot, as {id: {since, done}}, and first
// says that this snapshot only records what's already the case. Returns what is tracked
// now, the events that are due, and the claim keys of what is fine again.
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
    // An item that's gone is forgotten only once its value says it's fine. A topic that went
    // empty keeps it, so the item doesn't notify again when the value comes back.
    const released = [];
    function release(key) {
        if (released.indexOf(key) < 0) released.push(key);
    }
    for (const id in old) {
        if (tracked.hasOwnProperty(id)) continue;
        if (isResolved(car, id, okGeofences)) release(itemKey(id));
        else tracked[id] = { since: old[id].since, done: old[id].done };
    }
    // Whatever is fine ends its claim even when this copy wasn't tracking it, such as right
    // after it started over, since another copy, or this one before the gap, may hold it.
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

// Which notifications a new snapshot calls for. Pass the state it returns back in with the
// next snapshot; prev is null at the start. opts = {leftOpenMs, staleMs, holdMs, okGeofences}.
// Returns {state, events, released}, where each event is {type, ...} and QML words it, and
// released lists the claim keys (see claimEvent) of what this snapshot shows is fine again.
//
// Notifications are for changes, so the first snapshot, and the first after a gap longer
// than staleMs (a suspend or a broker outage), only record what's already the case.
// Something left open, or the car unlocked with nobody inside, notifies once it has been
// that way for leftOpenMs while nobody is in the car, and only once until it's explicitly
// fine again. A low tire and an update notify right away, once. trackItems() does those,
// and trackCharge() has the rules for a charge.
function notifyStep(prev, car, nowMs, opts) {
    const { leftOpenMs = 10 * MINUTE, staleMs = 15 * MINUTE, holdMs = 3 * MINUTE, okGeofences = [] } = opts || {};
    // A clock set back would leave every timer in the future, so that starts over too.
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

// What makes an event from notifyStep() the same one, for copies of the widget that show
// the same car and see it on their own polls. A charge event is named by its type alone.
// Copies see a charge end at their own times, and the car's since can change in between:
// TeslaMate stops logging about 3 minutes after a charge stops, just when each copy's hold
// on that stop ends. notifyStep() releases the claim once the car charges again.
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

// The claim key, as eventKey() names it, for an id that notifyStep() tracks.
function itemKey(id) {
    const { type, part } = splitId(id);
    if (type === "unlocked") return eventKey({ type: "unlocked" });
    if (type === "tire") return eventKey({ type: "tires", items: [part] });
    if (type === "update") return eventKey({ type: "update", version: part });
    return eventKey({ type: "leftOpen", items: [{ id: id }] });
}

// The part of an event from notifyStep() that this copy of the widget should send, or null
// when other copies already sent all of it. claim(key, windowMs) is notifyhub.js's claim()
// for this car, true for the first copy to ask.
//
// Copies poll at their own times, so one can see a door and the trunk open on the same poll
// and another on two, and group them differently. Each thing left open, and each low tire, is
// claimed on its own, so it's still sent once. A claim lasts until notifyStep() releases it,
// when what it's for is fine again, so a door closed and left open again, or a new charge,
// is news however soon it happens. Copies see an event within a poll of each other, and the
// longest "While the car sleeps" setting puts polls an hour apart, so a claim nobody
// releases lasts two hours.
function claimEvent(event, claim) {
    const windowMs = 2 * HOUR;
    if (!event.items) return claim(eventKey(event), windowMs) ? event : null;
    const items = event.items.filter(item => claim(eventKey({ type: event.type, items: [item] }), windowMs));
    if (items.length === 0) return null;
    return Object.assign({}, event, { items: items });
}

// Breeze battery icon name for a level (0..100).
function batteryIcon(level, charging) {
    const step = level === null ? 50 : Math.max(0, Math.min(100, Math.round(level / 10) * 10));
    const name = "battery-" + (step < 10 ? "00" : step < 100 ? "0" : "") + step;
    return charging ? name + "-charging" : name;
}

// Tesla's paints by a word in their names, most specific first, so "MidnightCherryRed" isn't
// taken for Midnight Silver or for Red, and "Quicksilver" isn't taken for Silver. The colors
// are close to the paints rather than exact, and black is lifted a little so the drawing's
// shading still shows on it.
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

// The color to paint the car drawing for TeslaMate's exterior_color, such as "DeepBlue" or
// "PearlWhite", as "#rrggbb". A missing name, or one it doesn't know, gives "", which leaves
// the drawing in theme colors. Case, spaces and punctuation don't matter, since the car
// reports the same paint as "RedMulticoat" or "Red" depending on its age.
function paintColor(name) {
    const paint = String(name || "").toLowerCase().replace(/[^a-z]/g, "");
    for (const [word, color] of PAINTS) {
        if (paint.includes(word)) return color;
    }
    return "";
}

// How long to wait between polls, in ms. A sleeping car's values don't change, so once
// there's data and nobody has the popup open, the idle setting applies; it never polls
// faster than the normal rate. Without data it keeps trying at the normal rate, since the
// state isn't known yet.
function pollIntervalMs(refresh, idle, state, hasData, popupOpen) {
    const fast = Math.max(5, refresh || 15);
    const sleeping = state === "asleep" || state === "offline" || state === "suspended";
    if (hasData && !popupOpen && sleeping) return Math.max(fast, idle || 0) * SECOND;
    return fast * SECOND;
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
    const broker = { host: "", port: null, tls: null, user: "", password: "" };
    let rest = String(text || "").trim();
    const scheme = /^([a-z][a-z0-9+.-]*):\/\//i.exec(rest);
    if (scheme) {
        const name = scheme[1].toLowerCase();
        if (["mqtts", "ssl", "tls", "wss"].indexOf(name) >= 0) broker.tls = true;
        else if (["mqtt", "tcp", "ws"].indexOf(name) >= 0) broker.tls = false;
        rest = rest.slice(scheme[0].length);
    }
    rest = rest.split(/[\/?#]/)[0];
    // The last @ ends the credentials, so a password may contain one.
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
    } else if (rest.indexOf(":") >= 0 && rest.indexOf(":") === rest.lastIndexOf(":")) {
        // A single colon separates a port; more than one is a bare IPv6 address.
        port = rest.slice(rest.indexOf(":") + 1);
        rest = rest.slice(0, rest.indexOf(":"));
    }
    if (/^\d+$/.test(port)) {
        const number = parseInt(port, 10);
        if (number >= 1 && number <= 65535) broker.port = number;
    }
    broker.host = rest;
    return broker;
}

// TeslaMate's address as people type it, such as teslamate.local:4000, made into a URL a
// browser opens. Without a scheme, "teslamate.local:4000" would read as a URL whose scheme
// is "teslamate.local", so http:// goes in front. "" stays "", meaning no link.
function normalizeUrl(text) {
    const url = String(text || "").trim();
    if (!url) return "";
    return /^[a-z][a-z0-9+.-]*:\/\//i.test(url) ? url : "http://" + url;
}

// The mosquitto_sub call shared by the widget's poll and the settings page.
// options = {host, port, user, password, tls, caFile, topics, wait}; "" when there is no host.
// -W only starts counting once the connection is up, so coreutils timeout bounds a host
// that drops packets (exit 124). timeout exits 127 itself when mosquitto_sub is missing,
// which keeps the install hint working.
function mosquittoCommand(options) {
    options = options || {};
    const broker = parseBrokerHost(options.host);
    if (!broker.host) return "";
    const wait = Math.max(1, Math.round(options.wait || 2));
    const given = parseInt(options.port, 10);
    const port = broker.port || (given >= 1 && given <= 65535 ? given : 1883);
    let cmd = "timeout " + (wait + 10) + " mosquitto_sub -h " + shellQuote(broker.host) + " -p " + port;
    const topics = options.topics || [];
    for (const topic of topics) cmd += " -t " + shellQuote(topic);
    cmd += " -v -W " + wait;
    if (options.tls || broker.tls === true) {
        const caFile = String(options.caFile || "").trim();
        // Only an unquoted leading ~ expands, so a home-relative path keeps it outside
        // the quotes.
        if (caFile.indexOf("~/") === 0) cmd += " --cafile ~/" + shellQuote(caFile.slice(2));
        else if (caFile) cmd += " --cafile " + shellQuote(caFile);
        else cmd += " --tls-use-os-certs";
    }
    const user = options.user || broker.user;
    const password = options.password || broker.password;
    if (user) cmd += " -u " + shellQuote(user);
    // MQTT 3.1.1 has no password without a username, and mosquitto_sub refuses to start
    // with one ("Problem setting username and/or password."). A password left behind after
    // the username was cleared is dropped, so an anonymous broker still answers.
    if (user && password) cmd += " -P " + shellQuote(password);
    return cmd;
}

// Sorts a failed mosquitto_sub run into a kind that QML words for people, with the detail
// a message needs. kind "" means the run was fine, even if no messages arrived.
function mqttError(code, stderr, hasOutput) {
    const message = String(stderr || "").trim();
    const plain = message.replace(/^Error:\s*/, "");
    function result(kind, detail) {
        return { kind: kind, detail: detail || "" };
    }
    if (code === 127) return result("notInstalled");
    if (code === 124) return result("noAnswer");
    if (/Unknown option '--tls-use-os-certs'/.test(message)) return result("oldClient");
    if (/Problem setting TLS options/.test(message)) return result("caFile");
    if (code === 4 || code === 5 || /not authori[sz]ed|bad user name or password/i.test(message))
        return result("auth");
    if (/Lookup error/.test(message)) return result("lookup");
    if (/Error: Connection refused/.test(message)) return result("refused");
    if (/No route to host|Network is unreachable|Connection timed out/.test(message))
        return result("unreachable", plain);
    if (code === 14 || /Protocol error/.test(message)) return result("tls");
    // A TLS broker hangs up on a plain client without a word, and so does a plain broker
    // when the client talks TLS.
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

// The cars a "Find Cars" subscription to teslamate/cars/+/display_name and
// teslamate/+/cars/+/display_name turned up, as [{prefix, name}]. Sorted by namespace and
// then by car id as a number, so car 2 comes before car 10. TeslaMate's ids are numbers;
// anything else goes after them in text order, which keeps the order consistent.
function parseCars(out) {
    const all = parseMqtt(out, "");
    const re = /^(teslamate\/(?:([^\/]+)\/)?cars\/([^\/]+))\/display_name$/;
    const found = [];
    for (const topic in all) {
        const match = re.exec(topic);
        if (match) found.push({ prefix: match[1], name: all[topic], ns: match[2] || "", id: match[3] });
    }
    found.sort(function (a, b) {
        if (a.ns !== b.ns) return a.ns < b.ns ? -1 : 1;
        const an = /^\d+$/.test(a.id), bn = /^\d+$/.test(b.id);
        if (an !== bn) return an ? -1 : 1;
        if (an && Number(a.id) !== Number(b.id)) return Number(a.id) - Number(b.id);
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });
    return found.map(car => ({ prefix: car.prefix, name: car.name }));
}

// Plasma reads a notification's body as markup, so text with & or < in it, such as a
// software version, would otherwise break or turn into formatting.
function escapeMarkup(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
