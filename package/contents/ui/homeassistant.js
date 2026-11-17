.pragma library

// The Home Assistant source: the car's entities from Home Assistant's REST API, as Home
// Assistant's own Tesla Fleet, Teslemetry and Tessie integrations name them, turned into
// TeslaMate's values ({topic suffix: string}). The three share their entity keys, and Home
// Assistant names an entity <domain>.<car>_<name>, where <car> is the car's name and
// <name> the entity's English name, so the widget finds them by the car's part, the
// prefix. Home Assistant converts values to its own units and says which in each entity's
// unit_of_measurement; they go back to km, km/h, bar and °C here.

const KM_PER_MILE = 1.609344;
const PSI_PER_BAR = 14.503773800722;

const CHARGING_STATES = {
    charging: "Charging",
    complete: "Complete",
    disconnected: "Disconnected",
    no_power: "NoPower",
    starting: "Starting",
    stopped: "Stopped"
};

// Home Assistant's door, window and tire names, and TeslaMate's.
const SIDES = [["front_driver", "driver_front"], ["rear_driver", "driver_rear"],
               ["front_passenger", "passenger_front"], ["rear_passenger", "passenger_rear"]];
const TIRES = [["front_left", "fl"], ["front_right", "fr"], ["rear_left", "rl"], ["rear_right", "rr"]];

// Home Assistant's address as typed: trimmed, without a trailing slash or /api, with
// http:// if it has no scheme. "" when empty.
function baseUrl(text) {
    let url = String(text || "").trim().replace(/\/+$/, "").replace(/\/api$/i, "");
    if (!url) return "";
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) url = "http://" + url;
    return url;
}

// The car's part of its entity IDs, as typed: lower case, with anything but letters and
// digits as _, and without a domain or one of the car's entity names pasted along, so
// "sensor.my_car_battery_level" and "My Car" both give "my_car".
function cleanPrefix(text) {
    let p = String(text || "").trim().toLowerCase().replace(/^[a-z_]+\./, "");
    p = p.replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
    return p.replace(/_(usable_battery_level|battery_level|status|charging|lock|location)$/, "");
}

// Every request reads all states; there's no way to ask for one device's.
function requestPath(request) {
    return "/api/states";
}

function finite(v) {
    return typeof v === "number" && isFinite(v);
}

// The states for one car, as {"<domain>.<name>": {state, attributes, last_changed}}, without
// the ones Home Assistant can't read right now.
function carEntities(list, prefix) {
    const out = {};
    const p = cleanPrefix(prefix);
    if (!p || !Array.isArray(list)) return out;
    for (const entity of list) {
        if (!entity || typeof entity.entity_id !== "string") continue;
        const match = /^([a-z_]+)\.(.+)$/.exec(entity.entity_id);
        if (!match || !match[2].startsWith(p + "_")) continue;
        const state = typeof entity.state === "string" ? entity.state : "";
        if (state === "" || state === "unavailable" || state === "unknown") continue;
        out[match[1] + "." + match[2].slice(p.length + 1)] = entity;
    }
    return out;
}

function unit(entity) {
    const attrs = entity && entity.attributes;
    return attrs && typeof attrs.unit_of_measurement === "string" ? attrs.unit_of_measurement : "";
}

function number(entity) {
    if (!entity) return null;
    const n = parseFloat(entity.state);
    return isFinite(n) ? n : null;
}

// Values in Home Assistant's units, in TeslaMate's.
function toKm(value, u) {
    if (u === "mi") return value * KM_PER_MILE;
    if (u === "m") return value / 1000;
    if (u === "ft") return value * 0.0003048;
    return value;
}

function toKmh(value, u) {
    if (u === "mph") return value * KM_PER_MILE;
    if (u === "m/s") return value * 3.6;
    return value;
}

function toBar(value, u) {
    if (u === "psi") return value / PSI_PER_BAR;
    if (u === "kPa") return value / 100;
    if (u === "Pa") return value / 100000;
    return value;
}

function toCelsius(value, u) {
    return u === "°F" ? (value - 32) * 5 / 9 : value;
}

function toMiles(value, u) {
    return u === "mi" ? value : toKm(value, u) / KM_PER_MILE;
}

// Minutes from now until a time sensor's moment, or a duration sensor's value in minutes.
function minutesUntil(entity, nowMs) {
    const n = number(entity);
    if (n !== null && /^-?[0-9.]+$/.test(entity.state.trim())) {
        const u = unit(entity);
        if (u === "h") return n * 60;
        if (u === "s") return n / 60;
        if (u === "d") return n * 1440;
        return n;
    }
    const at = Date.parse(entity ? entity.state : "");
    return isNaN(at) ? null : Math.max(0, (at - nowMs) / 60000);
}

// The car's name, from an entity's friendly name without the entity's own name.
function carName(e) {
    const names = [["binary_sensor.status", / Status$/], ["sensor.battery_level", / Battery level$/i],
                   ["lock.lock", / Lock$/]];
    for (const [key, suffix] of names) {
        const attrs = e[key] && e[key].attributes;
        const name = attrs && typeof attrs.friendly_name === "string" ? attrs.friendly_name : "";
        if (name && suffix.test(name)) return name.replace(suffix, "").trim();
    }
    return "";
}

// Whether a fast charger type is a DC fast charger: true for a Supercharger, CCS or
// CHAdeMO, false for none or an AC charger (ACSingleWireCAN), null for a type not known.
function fastCharger(type) {
    const t = String(type || "").toLowerCase();
    if (!t) return null;
    if (t === "<invalid>" || t.startsWith("ac")) return false;
    return /supercharger|combo|ccs|chademo/.test(t) ? true : null;
}

// A zone as TeslaMate's geofence: Home Assistant says "home" for its home zone and the
// zone's name for others.
function zone(state) {
    if (state === "not_home") return "";
    if (state === "home") return "Home";
    return state;
}

// /api/states as one car's TeslaMate values. nowMs turns the times Home Assistant gives
// for the end of a charge and the arrival into durations.
function fromStates(list, prefix, nowMs) {
    const e = carEntities(list, prefix);
    const out = {};
    function on(key) {
        return e[key] ? e[key].state === "on" : null;
    }
    function flag(key, value) {
        if (value !== null && value !== undefined) out[key] = value ? "true" : "false";
    }
    function put(key, value) {
        if (finite(value)) out[key] = String(value);
    }
    function measure(key, entity, convert) {
        const n = number(entity);
        if (n !== null) out[key] = String(convert ? convert(n, unit(entity)) : n);
    }

    const name = carName(e);
    if (name) out.display_name = name;

    // Tessie's integration has no battery level, and calls the usable level "Battery level".
    measure("battery_level", e["sensor.battery_level"]);
    measure("usable_battery_level", e["sensor.usable_battery_level"]);
    measure("rated_battery_range_km", e["sensor.battery_range"], toKm);
    measure("est_battery_range_km", e["sensor.estimate_battery_range"] || e["sensor.battery_range_estimate"], toKm);
    measure("ideal_battery_range_km", e["sensor.ideal_battery_range"] || e["sensor.battery_range_ideal"], toKm);
    measure("charge_limit_soc", e["number.charge_limit"]);

    const charging = e["sensor.charging"] ? e["sensor.charging"].state : "";
    if (charging) {
        out.charging_state = CHARGING_STATES[charging] || charging;
        out.plugged_in = charging !== "disconnected" ? "true" : "false";
    }
    measure("charger_power", e["sensor.charger_power"]);
    measure("charger_voltage", e["sensor.charger_voltage"]);
    measure("charger_actual_current", e["sensor.charger_current"]);
    measure("charge_energy_added", e["sensor.charge_energy_added"]);
    if (e["sensor.time_to_full_charge"]) {
        const minutes = minutesUntil(e["sensor.time_to_full_charge"], nowMs);
        if (minutes !== null) out.time_to_full_charge = String(minutes / 60);
    }
    // Off by default in Home Assistant. Only the type is given, so whether it's a DC fast
    // charger is read from that.
    const fastType = e["sensor.fast_charger_type"] ? e["sensor.fast_charger_type"].state.trim() : "";
    if (fastType && fastType !== "<invalid>") out.fast_charger_type = fastType;
    flag("fast_charger_present", fastCharger(fastType));
    measure("charge_rate_kmh", e["sensor.charge_rate"], toKmh);
    const port = e["cover.charge_port_door"];
    if (port) flag("charge_port_door_open", port.state === "open" || port.state === "opening");
    else flag("charge_port_door_open", on("binary_sensor.charge_port_door"));

    const climate = e["climate.climate"];
    if (climate) {
        flag("is_climate_on", climate.state !== "off");
        // Dog, camp and keep mode are the climate's presets. The Tessie integration calls
        // keep "on", the others "keep".
        const preset = climate.attributes && typeof climate.attributes.preset_mode === "string"
            ? climate.attributes.preset_mode : "";
        if (preset) out.climate_keeper_mode = preset === "keep" ? "on" : preset;
    }
    flag("cabin_overheat_protection_actively_cooling", on("binary_sensor.cabin_overheat_protection_actively_cooling"));
    flag("is_front_defroster_on", e["switch.defrost"] ? on("switch.defrost") : on("switch.defrost_mode"));
    measure("driver_temp_setting", e["sensor.driver_temperature_setting"], toCelsius);
    flag("is_preconditioning", on("binary_sensor.preconditioning"));
    flag("battery_heater_on", on("binary_sensor.battery_heater"));
    measure("inside_temp", e["sensor.inside_temperature"], toCelsius);
    measure("outside_temp", e["sensor.outside_temperature"], toCelsius);

    const shift = e["sensor.shift_state"] ? e["sensor.shift_state"].state.toUpperCase() : "";
    if (shift) out.shift_state = shift;
    measure("speed", e["sensor.speed"], toKmh);
    measure("power", e["sensor.power"]);
    measure("odometer", e["sensor.odometer"], toKm);

    const lock = e["lock.lock"];
    if (lock && (lock.state === "locked" || lock.state === "unlocked")) flag("locked", lock.state === "locked");
    if (e["switch.sentry_mode"]) flag("sentry_mode", e["switch.sentry_mode"].state === "on");
    else if (e["sensor.sentry_mode"]) flag("sentry_mode", e["sensor.sentry_mode"].state !== "off");
    flag("is_user_present", on("binary_sensor.user_present"));
    for (const [cover, key] of [["frunk", "frunk_open"], ["trunk", "trunk_open"]]) {
        const c = e["cover." + cover];
        if (c) flag(key, c.state === "open" || c.state === "opening");
    }
    const sunroof = e["cover.sunroof"];
    if (sunroof) {
        out.sun_roof_installed = "true";
        const position = sunroof.attributes ? sunroof.attributes.current_position : null;
        put("sun_roof_percent_open", finite(position) ? position : (sunroof.state === "closed" ? 0 : null));
    }
    for (const kind of ["door", "window"]) {
        let known = 0;
        let anyOpen = false;
        for (const [ha, tm] of SIDES) {
            const open = on("binary_sensor." + ha + "_" + kind);
            if (open === null) continue;
            known++;
            anyOpen = anyOpen || open;
            flag(tm + "_" + kind + "_open", open);
        }
        if (known > 0) out[kind + "s_open"] = anyOpen ? "true" : "false";
    }
    for (const [ha, tm] of TIRES) {
        measure("tpms_pressure_" + tm, e["sensor.tire_pressure_" + ha], toBar);
        flag("tpms_soft_warning_" + tm, on("binary_sensor.tire_pressure_warning_" + ha));
    }

    const update = e["update.update"];
    const attrs = update && update.attributes ? update.attributes : {};
    const installing = attrs.in_progress === true || finite(attrs.in_progress);
    if (e["sensor.version"]) out.version = e["sensor.version"].state;
    else if (typeof attrs.installed_version === "string") out.version = attrs.installed_version;
    if (update) {
        out.update_available = update.state === "on" ? "true" : "false";
        out.update_version = update.state === "on" && typeof attrs.latest_version === "string"
            ? attrs.latest_version : "";
        if (installing) put("install_perc", finite(attrs.update_percentage) ? attrs.update_percentage
                                              : finite(attrs.in_progress) ? attrs.in_progress : null);
    }

    const destination = e["sensor.destination"] ? e["sensor.destination"].state.trim() : "";
    function routeValue(key, convert) {
        const entity = e["sensor." + key];
        const n = number(entity);
        return n === null ? undefined : convert ? convert(entity) : n;
    }
    // The same JSON as TeslaMate's active_route topic, which keeps miles.
    out.active_route = destination ? JSON.stringify({
        destination: destination,
        minutes_to_arrival: e["sensor.time_to_arrival"]
            ? (minutesUntil(e["sensor.time_to_arrival"], nowMs) ?? undefined) : undefined,
        miles_to_arrival: routeValue("distance_to_arrival", x => toMiles(number(x), unit(x))),
        energy_at_arrival: routeValue("state_of_charge_at_arrival"),
        traffic_minutes_delay: routeValue("traffic_delay")
    }) : "";

    const tracker = e["device_tracker.location"];
    if (tracker) out.geofence = zone(tracker.state);

    // Awake or not from the status; then what TeslaMate would call it.
    const status = on("binary_sensor.status");
    if (status === false) {
        out.state = "asleep";
    } else if (status === true || hasValues(out)) {
        if (installing) out.state = "updating";
        else if (shift === "D" || shift === "R" || shift === "N") out.state = "driving";
        else if (out.charging_state === "Charging" || out.charging_state === "Starting") out.state = "charging";
        else if (status === true) out.state = "online";
    }
    // When the car woke or fell asleep, if that's what it's doing.
    const changed = e["binary_sensor.status"] ? Date.parse(e["binary_sensor.status"].last_changed) : NaN;
    if (!isNaN(changed) && (out.state === "asleep" || out.state === "online"))
        out.since = new Date(changed).toISOString();
    return out;
}

// Whether values hold anything about the car beyond its name.
function hasValues(values) {
    return Object.keys(values).some(key => key !== "display_name" && key !== "active_route");
}

// The cars in /api/states as [{prefix, name}]: prefixes with a battery level and a
// charging state or lock, so a phone's battery level isn't taken for a car.
function findCars(list) {
    const cars = [];
    if (!Array.isArray(list)) return cars;
    const ids = {};
    for (const entity of list)
        if (entity && typeof entity.entity_id === "string") ids[entity.entity_id] = entity;
    for (const id in ids) {
        const match = /^sensor\.(.+)_battery_level$/.exec(id);
        if (!match || /_usable$/.test(match[1])) continue;
        const p = match[1];
        if (!ids["sensor." + p + "_charging"] && !ids["lock." + p + "_lock"]) continue;
        cars.push({ prefix: p, name: carName({ "sensor.battery_level": ids[id], "binary_sensor.status": ids["binary_sensor." + p + "_status"] }) });
    }
    return cars;
}

// A parsed reply for a request, as RestFetch expects.
function convert(request, json, prefix, nowMs) {
    if (!Array.isArray(json)) return { error: { kind: "badJson", detail: "" } };
    if (request === "cars") return { kind: "cars", cars: findCars(json) };
    const values = fromStates(json, prefix, nowMs);
    if (!hasValues(values)) return { error: { kind: "noEntities", detail: cleanPrefix(prefix) } };
    return { kind: request === "test" ? "summary" : "data", values: values };
}
