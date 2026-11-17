.pragma library

// The TeslaMate API source: TeslaMateApi (github.com/tobiasehlert/teslamateapi), a small
// HTTP service next to TeslaMate that answers with what TeslaMate publishes over MQTT. Its
// replies are turned back into TeslaMate's MQTT values ({topic suffix: string}), so the
// rest of the widget works unchanged, and nothing on this machine needs mosquitto_sub.
//
// It serves JSON from Go structs without omitempty, so a value it hasn't received yet
// arrives as 0, "" or false. Where 0 can't be real (a tire pressure, a charge limit), it is
// left out, which the widget reads as unknown.

const KM_PER_MILE = 1.609344;
const PSI_PER_BAR = 14.503773800722;

// TeslaMateApi lowercases charging_state; TeslaMate publishes Tesla's spelling.
const CHARGING_STATES = {
    charging: "Charging",
    complete: "Complete",
    disconnected: "Disconnected",
    nopower: "NoPower",
    starting: "Starting",
    stopped: "Stopped"
};

// The service's base URL as typed: trimmed, without a trailing slash or the /api/v1 that
// people copy along from its docs, with http:// if it has no scheme (it usually runs on
// the local network, on port 8080). "" when empty.
function baseUrl(text) {
    let url = String(text || "").trim().replace(/\/+$/, "").replace(/\/api(\/v1)?$/i, "");
    if (!url) return "";
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) url = "http://" + url;
    return url;
}

// A car ID as typed: a whole number from 1, or 0 when it isn't one.
function carId(value) {
    const n = Number(value);
    return isFinite(n) && n >= 1 && Math.floor(n) === n ? n : 0;
}

// The path for a request: "data" and "test" read the car's status, "cars" lists the cars.
function requestPath(request, id) {
    if (request === "cars") return "/api/v1/cars";
    return "/api/v1/cars/" + carId(id) + "/status";
}

function finite(v) {
    return typeof v === "number" && isFinite(v);
}

// A nullable text column, which may be a string, null, or {String, Valid}.
function text(v) {
    if (typeof v === "string") return v;
    if (v && typeof v === "object" && v.Valid && typeof v.String === "string") return v.String;
    return "";
}

// An RFC 3339 time as ISO in UTC, or "" for none. A time it never received is Go's zero
// time, year 1.
function isoTime(v) {
    const ms = Date.parse(typeof v === "string" ? v : "");
    if (isNaN(ms) || new Date(ms).getUTCFullYear() < 1971) return "";
    return new Date(ms).toISOString();
}

// The error message TeslaMateApi sends with HTTP 200 instead of data, or "".
function replyError(json) {
    return json && typeof json === "object" && typeof json.error === "string" ? json.error.trim() : "";
}

// A /status reply as TeslaMate's values. Lengths, tire pressures and temperatures come in
// the units set in TeslaMate, which the reply names, and go back to km, bar and °C.
function fromStatus(json) {
    const data = json && typeof json === "object" && json.data ? json.data : null;
    const s = data && data.status && typeof data.status === "object" ? data.status : null;
    const out = {};
    if (!s) return out;
    const units = data.units || {};
    const miles = units.unit_of_length === "mi";
    const psi = units.unit_of_pressure === "psi";
    const fahrenheit = units.unit_of_temperature === "F";

    function put(key, value) {
        if (typeof value === "boolean") out[key] = value ? "true" : "false";
        else if (finite(value)) out[key] = String(value);
        else if (typeof value === "string") out[key] = value;
    }
    function positive(key, value) {
        if (finite(value) && value > 0) out[key] = String(value);
    }
    function km(key, value) {
        if (finite(value)) out[key] = String(miles ? value * KM_PER_MILE : value);
    }
    function celsius(key, value) {
        if (finite(value)) out[key] = String(fahrenheit ? (value - 32) * 5 / 9 : value);
    }
    function group(name) {
        const g = s[name];
        return g && typeof g === "object" ? g : {};
    }

    put("display_name", s.display_name || text(data.car && data.car.car_name));
    put("state", s.state);
    out.since = isoTime(s.state_since);
    km("odometer", s.odometer);

    const status = group("car_status");
    for (const key of ["healthy", "locked", "sentry_mode", "windows_open", "doors_open", "driver_front_door_open",
                       "driver_rear_door_open", "passenger_front_door_open", "passenger_rear_door_open",
                       "trunk_open", "frunk_open", "is_user_present"])
        put(key, status[key]);

    const details = group("car_details");
    if (details.model) put("model", details.model);
    put("exterior_color", group("car_exterior").exterior_color);
    put("geofence", group("car_geodata").geofence);

    const versions = group("car_versions");
    for (const key of ["version", "update_available", "update_version"])
        put(key, versions[key]);

    const driving = group("driving_details");
    put("shift_state", driving.shift_state);
    put("power", driving.power);
    km("speed", driving.speed);
    const route = driving.active_route && typeof driving.active_route === "object" ? driving.active_route : {};
    const destination = typeof route.destination === "string" ? route.destination.trim() : "";
    // distance_to_arrival holds TeslaMate's miles_to_arrival, which TeslaMateApi multiplies
    // by 0.621 when TeslaMate is set to miles, though it already was in miles.
    const distance = finite(route.distance_to_arrival)
        ? (miles ? route.distance_to_arrival * KM_PER_MILE : route.distance_to_arrival) : undefined;
    // The same JSON as TeslaMate's active_route topic.
    out.active_route = destination ? JSON.stringify({
        destination: destination,
        minutes_to_arrival: route.minutes_to_arrival,
        miles_to_arrival: distance,
        energy_at_arrival: route.energy_at_arrival,
        traffic_minutes_delay: route.traffic_minutes_delay
    }) : "";

    const climate = group("climate_details");
    put("is_climate_on", climate.is_climate_on);
    put("is_preconditioning", climate.is_preconditioning);
    put("climate_keeper_mode", climate.climate_keeper_mode);
    celsius("inside_temp", climate.inside_temp);
    celsius("outside_temp", climate.outside_temp);

    // Both 0 means TeslaMateApi has no battery values yet, not an empty battery.
    const battery = group("battery_details");
    if (battery.battery_level || battery.rated_battery_range) {
        put("battery_level", battery.battery_level);
        put("usable_battery_level", battery.usable_battery_level);
        km("rated_battery_range_km", battery.rated_battery_range);
        km("est_battery_range_km", battery.est_battery_range);
        km("ideal_battery_range_km", battery.ideal_battery_range);
    }

    const charging = group("charging_details");
    for (const key of ["plugged_in", "charge_energy_added", "charge_port_door_open", "charger_actual_current",
                       "charger_power", "charger_voltage", "charge_current_request", "charge_current_request_max",
                       "time_to_full_charge"])
        put(key, charging[key]);
    positive("charge_limit_soc", charging.charge_limit_soc);
    positive("charger_phases", charging.charger_phases);
    const state = typeof charging.charging_state === "string" ? charging.charging_state : "";
    if (state) out.charging_state = CHARGING_STATES[state.toLowerCase()] || state;
    out.scheduled_charging_start_time = isoTime(charging.scheduled_charging_start_time);

    const tpms = group("tpms_details");
    for (const tire of ["fl", "fr", "rl", "rr"]) {
        const p = tpms["tpms_pressure_" + tire];
        if (finite(p) && p > 0) out["tpms_pressure_" + tire] = String(psi ? p / PSI_PER_BAR : p);
        put("tpms_soft_warning_" + tire, tpms["tpms_soft_warning_" + tire]);
    }
    return out;
}

// A /cars reply as [{id, name, vin}], in the order given.
function parseCars(json) {
    const cars = json && json.data && Array.isArray(json.data.cars) ? json.data.cars : [];
    return cars.filter(c => c && carId(c.car_id))
        .map(c => ({ id: c.car_id, name: text(c.name), vin: text(c.car_details && c.car_details.vin) }));
}

// A parsed reply for a request, as RestFetch expects: {kind: "data" | "summary", values},
// {kind: "cars", cars}, or {error: {kind, detail}} when the reply carries an error.
function convert(request, json) {
    const error = replyError(json);
    if (error === "no info on this car ID") return { error: { kind: "noCar", detail: "" } };
    if (error) return { error: { kind: "service", detail: error } };
    if (request === "cars") return { kind: "cars", cars: parseCars(json) };
    const values = fromStatus(json);
    if (!values.state && !values.display_name) return { error: { kind: "noCar", detail: "" } };
    return { kind: request === "test" ? "summary" : "data", values: values };
}
