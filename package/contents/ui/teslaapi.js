.pragma library

// The Tesla Fleet API source. Its replies are turned into the same values TeslaMate
// publishes over MQTT ({topic suffix: string}), so everything that reads root.car works
// unchanged, plus a few the API has that TeslaMate doesn't publish, under the API's own
// names. Kept separate from logic.js, which stays about TeslaMate's values.
// Proxies that serve the same URLs (a custom base URL) work the same way.

const MINUTE = 60 * 1000;
const KM_PER_MILE = 1.609344;

// In the order of the Region setting's choices. The last choice is a custom URL.
const REGIONS = [
    "https://fleet-api.prd.na.vn.cloud.tesla.com",
    "https://fleet-api.prd.eu.vn.cloud.tesla.com",
    "https://fleet-api.prd.cn.vn.cloud.tesla.cn"
];
const AUTH_URL = "https://fleet-auth.prd.vn.cloud.tesla.com";
// Teslemetry serves the Fleet API's URLs, from its cache where it can, with a long-lived
// token of its own that never needs renewing.
const TESLEMETRY_URL = "https://api.teslemetry.com";

// The API's base URL for a Region setting, without a trailing slash. A custom URL gets
// https:// if it has no scheme. "" when the custom URL is empty.
function baseUrl(region, custom) {
    const preset = REGIONS[Math.round(Number(region))];
    if (preset) return preset;
    let url = String(custom || "").trim().replace(/\/+$/, "");
    if (!url) return "";
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) url = "https://" + url;
    return url;
}

// The settings TeslaApiFetch.run() takes for a source of kind "fleet", from cfg (the
// widget's configuration, or the settings page's fields under the same names): the Fleet
// API itself, or Teslemetry. service names the source in messages.
function fleetOptions(key, cfg) {
    if (key === "teslemetry")
        return { service: "teslemetry", region: REGIONS.length, customUrl: TESLEMETRY_URL,
                 accessToken: String(cfg.teslemetryToken || ""), refreshToken: "", clientId: "", authUrl: "",
                 tokenExpiry: 0, vin: String(cfg.teslemetryVin || "") };
    return { service: "fleet", region: cfg.apiRegion, customUrl: String(cfg.apiBaseUrl || ""),
             accessToken: String(cfg.apiAccessToken || ""), refreshToken: String(cfg.apiRefreshToken || ""),
             clientId: String(cfg.apiClientId || ""), authUrl: String(cfg.apiAuthUrl || ""),
             tokenExpiry: Number(cfg.apiTokenExpiry) || 0, vin: String(cfg.apiVin || "") };
}

// Whether fleetOptions() are enough to read a car.
function fleetConfigured(o) {
    return baseUrl(o.region, o.customUrl) !== "" && o.accessToken.trim() !== "" && cleanVin(o.vin) !== "";
}

// The token endpoint's base, from the setting or Tesla's default. https:// is added if it
// has no scheme.
function authUrl(text) {
    let url = String(text || "").trim().replace(/\/+$/, "");
    if (!url) return AUTH_URL;
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(url)) url = "https://" + url;
    return url;
}

// Whether tokens may be sent to a URL: https, or plain http only to this machine (a local
// proxy, or tools/fake-tesla-api.py). Anywhere else plain http would send the access or
// refresh token unencrypted, for anyone on the way to read.
function isSecureUrl(url) {
    const match = /^([a-z][a-z0-9+.-]*):\/\/(?:[^\/?#@]*@)?(\[[^\]]*\]|[^\/?#:]*)/i.exec(String(url || "").trim());
    if (!match) return false;
    const scheme = match[1].toLowerCase();
    if (scheme === "https") return true;
    if (scheme !== "http") return false;
    const host = match[2].toLowerCase().replace(/\.$/, "");
    return host === "localhost" || host === "[::1]" || /^127(\.\d{1,3}){3}$/.test(host);
}

// A VIN as typed: spaces dropped, upper case.
function cleanVin(text) {
    return String(text || "").replace(/\s+/g, "").toUpperCase();
}

// The endpoints vehicle_data is asked for. Location is only asked for when navigation is
// shown, since on recent firmware asking for it shows a location sharing icon in the car.
function vehicleDataPath(vin, withLocation) {
    const parts = ["charge_state", "climate_state", "drive_state", "vehicle_config", "vehicle_state"];
    if (withLocation) parts.push("location_data");
    return "/api/1/vehicles/" + encodeURIComponent(cleanVin(vin)) + "/vehicle_data?endpoints="
        + encodeURIComponent(parts.join(";"));
}

function vehiclePath(vin) {
    return "/api/1/vehicles/" + encodeURIComponent(cleanVin(vin));
}

// The body of a reply: its "response" member when it has one.
function unwrap(json) {
    if (json && typeof json === "object" && Object.prototype.hasOwnProperty.call(json, "response"))
        return json.response;
    return json;
}

function present(v) {
    return v !== undefined && v !== null;
}

function finite(v) {
    return typeof v === "number" && isFinite(v);
}

// What the API calls a model (vehicle_config.car_type) as TeslaMate's model topic.
// lychee and tamarind are the 2021 Model S and Model X.
function modelName(carType) {
    const type = String(carType || "").toLowerCase();
    if (type === "models" || type === "models2" || type === "lychee") return "S";
    if (type === "model3") return "3";
    if (type === "modelx" || type === "tamarind") return "X";
    if (type === "modely") return "Y";
    if (type.startsWith("cyber")) return "Cybertruck";
    return "";
}

// The software_update statuses that mean an update is waiting or on its way.
const UPDATE_PENDING = ["available", "scheduled", "downloading", "downloading_wifi_wait", "installing"];

// TeslaMate's state for an awake car: driving, charging, updating or online.
function awakeState(charge, drive, update) {
    if (update && update.status === "installing") return "updating";
    const shift = drive ? drive.shift_state : null;
    if (shift === "D" || shift === "R" || shift === "N") return "driving";
    const charging = charge ? charge.charging_state : "";
    if (charging === "Charging" || charging === "Starting") return "charging";
    return "online";
}

// A vehicle_data reply (with or without its "response" wrapper) as TeslaMate's values.
// Values the reply leaves out are left out here too, which the widget reads as unknown.
function fromVehicleData(json) {
    const v = unwrap(json);
    const out = {};
    if (!v || typeof v !== "object") return out;
    function put(key, value) {
        if (!present(value)) return;
        if (typeof value === "boolean") out[key] = value ? "true" : "false";
        else if (finite(value)) out[key] = String(value);
        else if (typeof value === "string") out[key] = value;
    }
    function miles(key, value) {
        if (finite(value)) out[key] = String(value * KM_PER_MILE);
    }
    // Doors, windows, frunk and trunk are numbers: 0 is closed.
    function open(key, value) {
        if (finite(value)) out[key] = value !== 0 ? "true" : "false";
    }

    const charge = v.charge_state || null;
    const climate = v.climate_state || null;
    const drive = v.drive_state || null;
    const config = v.vehicle_config || null;
    const vs = v.vehicle_state || null;
    const update = vs && vs.software_update ? vs.software_update : null;

    put("display_name", v.display_name || (vs && vs.vehicle_name) || "");
    const top = v.state;
    out.state = top === "asleep" || top === "offline" ? top : awakeState(charge, drive, update);

    if (config) {
        const model = modelName(config.car_type);
        if (model) out.model = model;
        put("exterior_color", config.exterior_color);
        if (present(config.sun_roof_installed)) out.sun_roof_installed = config.sun_roof_installed ? "true" : "false";
    }

    if (charge) {
        for (const key of ["battery_level", "usable_battery_level", "charge_limit_soc", "charger_power",
                           "charger_voltage", "charger_actual_current", "charger_phases",
                           "time_to_full_charge", "charge_energy_added", "charge_current_request",
                           "charge_current_request_max", "charge_port_door_open"])
            put(key, charge[key]);
        if (typeof charge.charging_state === "string" && charge.charging_state) {
            out.charging_state = charge.charging_state;
            out.plugged_in = charge.charging_state !== "Disconnected" ? "true" : "false";
        }
        // A unix time in seconds, only meaningful while a scheduled charge is pending.
        const start = charge.scheduled_charging_start_time;
        out.scheduled_charging_start_time = charge.scheduled_charging_pending && finite(start) && start > 0
            ? new Date(start * 1000).toISOString() : "";
        miles("rated_battery_range_km", charge.battery_range);
        miles("est_battery_range_km", charge.est_battery_range);
        miles("ideal_battery_range_km", charge.ideal_battery_range);
        // A DC fast charger, and whose. Not TeslaMate topics. The API says "<invalid>" for
        // none.
        put("fast_charger_present", charge.fast_charger_present);
        for (const key of ["fast_charger_type", "fast_charger_brand"])
            if (typeof charge[key] === "string" && charge[key].trim() && charge[key] !== "<invalid>")
                out[key] = charge[key].trim();
        // The range the charge adds per hour, in mph like every distance here.
        if (finite(charge.charge_rate)) out.charge_rate_kmh = String(charge.charge_rate * KM_PER_MILE);
        put("battery_heater_on", charge.battery_heater_on);
    }

    if (climate) {
        for (const key of ["inside_temp", "outside_temp", "is_climate_on", "is_preconditioning",
                           "climate_keeper_mode", "cabin_overheat_protection_actively_cooling",
                           "driver_temp_setting"])
            put(key, climate[key]);
        // Defrost mode is 0 when off; older cars only report the front defroster.
        if (climate.is_front_defroster_on === true || (finite(climate.defrost_mode) && climate.defrost_mode > 0))
            out.is_front_defroster_on = "true";
        else if (climate.is_front_defroster_on === false || climate.defrost_mode === 0)
            out.is_front_defroster_on = "false";
        // The battery heater shows up in either place, depending on the car.
        if (climate.battery_heater === true) out.battery_heater_on = "true";
        else if (climate.battery_heater === false && !out.battery_heater_on) out.battery_heater_on = "false";
    }

    if (drive) {
        out.shift_state = typeof drive.shift_state === "string" ? drive.shift_state : "";
        // The API reports mph; TeslaMate km/h.
        if (finite(drive.speed)) out.speed = String(drive.speed * KM_PER_MILE);
        put("power", drive.power);
        const destination = typeof drive.active_route_destination === "string"
            ? drive.active_route_destination.trim() : "";
        // The same JSON as TeslaMate's active_route topic, which also keeps miles.
        out.active_route = destination ? JSON.stringify({
            destination: destination,
            minutes_to_arrival: drive.active_route_minutes_to_arrival,
            miles_to_arrival: drive.active_route_miles_to_arrival,
            energy_at_arrival: drive.active_route_energy_at_arrival,
            traffic_minutes_delay: drive.active_route_traffic_minutes_delay
        }) : "";
    }

    if (vs) {
        for (const key of ["locked", "sentry_mode", "is_user_present", "service_mode", "sun_roof_percent_open"])
            put(key, vs[key]);
        miles("odometer", vs.odometer);
        if (typeof vs.car_version === "string") out.version = vs.car_version.trim().split(/\s+/)[0];
        const doors = { driver_front: vs.df, driver_rear: vs.dr, passenger_front: vs.pf, passenger_rear: vs.pr };
        const windows = { driver_front: vs.fd_window, driver_rear: vs.rd_window,
                          passenger_front: vs.fp_window, passenger_rear: vs.rp_window };
        for (const [kind, values] of [["door", doors], ["window", windows]]) {
            let known = 0;
            let anyOpen = false;
            for (const part in values) {
                open(part + "_" + kind + "_open", values[part]);
                if (finite(values[part])) {
                    known++;
                    if (values[part] !== 0) anyOpen = true;
                }
            }
            if (known > 0) out[kind + "s_open"] = anyOpen ? "true" : "false";
        }
        open("frunk_open", vs.ft);
        open("trunk_open", vs.rt);
        for (const tire of ["fl", "fr", "rl", "rr"]) {
            put("tpms_pressure_" + tire, vs["tpms_pressure_" + tire]);
            put("tpms_soft_warning_" + tire, vs["tpms_soft_warning_" + tire]);
        }
        if (update) {
            const status = typeof update.status === "string" ? update.status : "";
            out.update_available = UPDATE_PENDING.includes(status) ? "true" : "false";
            out.update_version = typeof update.version === "string" ? update.version.trim() : "";
            put("download_perc", update.download_perc);
            put("install_perc", update.install_perc);
        }
    }
    return out;
}

// GET /api/1/vehicles/{vin}, which never wakes the car, as {display_name, state}.
function fromVehicleSummary(json) {
    const v = unwrap(json);
    const out = {};
    if (!v || typeof v !== "object") return out;
    if (typeof v.display_name === "string" && v.display_name) out.display_name = v.display_name;
    if (typeof v.state === "string" && v.state) out.state = v.state;
    return out;
}

// GET /api/1/vehicles as [{vin, name, state}], in the order the API gives.
function parseVehicles(json) {
    const list = unwrap(json);
    if (!Array.isArray(list)) return [];
    return list.filter(v => v && typeof v.vin === "string" && v.vin)
        .map(v => ({ vin: v.vin, name: typeof v.display_name === "string" ? v.display_name : "",
                     state: typeof v.state === "string" ? v.state : "" }));
}

// A summary laid over the last full values, so the battery and the rest stay on show while
// the car sleeps. suspended means the widget is letting an awake car fall asleep.
function mergeSummary(last, summary, suspended) {
    const out = Object.assign({}, last || {});
    if (summary.display_name) out.display_name = summary.display_name;
    const state = summary.state || "";
    if (state === "online") out.state = suspended ? "suspended" : (out.state || "online");
    else if (state) out.state = state;
    return out;
}

// When the car's state began, as ISO, for TeslaMate's `since`. Only a change seen by this
// widget counts, so the first values have none rather than a wrong one.
function trackSince(prev, next, nowMs) {
    const was = prev && prev.state ? prev.state : "";
    if (!was || !next.state) return "";
    if (was === next.state) return prev.since || "";
    return new Date(nowMs).toISOString();
}

// Whether the car is doing something that keeps it awake anyway, so polling it doesn't cost
// it sleep: driving, charging, updating, climate on, someone inside, or a door, frunk or
// trunk open (the car doesn't sleep with those open).
function isBusy(car) {
    if (!car) return false;
    const state = car.state || "";
    if (state === "driving" || state === "charging" || state === "updating") return true;
    const keys = ["is_climate_on", "is_preconditioning", "is_user_present", "frunk_open", "trunk_open",
                  "driver_front_door_open", "driver_rear_door_open", "passenger_front_door_open",
                  "passenger_rear_door_open"];
    if (keys.some(key => car[key] === "true")) return true;
    return car.charging_state === "Charging" || car.charging_state === "Starting";
}

// Decides what the next poll asks the API for, and returns {request, state, suspended}:
//   "data"    vehicle_data (falls back to "asleep" on 408);
//   "check"   the summary, then vehicle_data if the car is awake;
//   "summary" the summary alone.
// prev is the returned state from the last call (null at the start), car the current values.
// opts = {idleMs, sleepWindowMs, forced}.
//
// Requests that reach the car stop it falling asleep, and each one is billed. So once an
// awake car has been idle for idleMs, only the summary is fetched for sleepWindowMs, as
// TeslaMate does, then one vehicle_data shows whether anything changed. forced (someone
// asked) fetches the data anyway, but never wakes a sleeping car.
function pollPlan(prev, car, nowMs, opts) {
    const { idleMs = 15 * MINUTE, sleepWindowMs = 21 * MINUTE, forced = false } = opts || {};
    const p = prev || {};
    const state = (car && car.state) || "";
    const asleep = state === "asleep" || state === "offline";
    let activeAt = typeof p.activeAt === "number" && p.activeAt <= nowMs ? p.activeAt : null;
    let suspendUntil = typeof p.suspendUntil === "number" && p.suspendUntil <= nowMs + sleepWindowMs
        ? p.suspendUntil : null;
    const wasAwake = p.lastState && p.lastState !== "asleep" && p.lastState !== "offline";
    const plan = request => ({
        request: request,
        state: { activeAt: activeAt, suspendUntil: suspendUntil, lastState: state },
        suspended: request === "summary"
    });

    if (state === "" || asleep) {
        activeAt = null;
        suspendUntil = null;
        return plan("check");
    }
    // Just woke up, or first seen awake: give it idleMs before letting it sleep.
    if (activeAt === null || !wasAwake || isBusy(car)) activeAt = nowMs;
    if (forced) return plan("data");
    if (suspendUntil !== null) {
        if (nowMs < suspendUntil) return plan("summary");
        // The window is over and the car is still awake: look once.
        suspendUntil = null;
        return plan("data");
    }
    if (nowMs - activeAt >= idleMs) {
        suspendUntil = nowMs + sleepWindowMs;
        return plan("summary");
    }
    return plan("data");
}

// The form body that trades a refresh token for new tokens.
function refreshTokenBody(clientId, refreshToken) {
    return "grant_type=refresh_token&client_id=" + encodeURIComponent(String(clientId || "").trim())
        + "&refresh_token=" + encodeURIComponent(String(refreshToken || "").trim());
}

// A token reply as {access, refresh, expiresAt}, or null if it has no access token. A reply
// without a refresh token keeps the old one.
function parseTokens(json, oldRefresh, nowMs) {
    if (!json || typeof json.access_token !== "string" || !json.access_token) return null;
    const seconds = finite(json.expires_in) ? json.expires_in : 8 * 3600;
    return {
        access: json.access_token,
        refresh: typeof json.refresh_token === "string" && json.refresh_token ? json.refresh_token : oldRefresh,
        expiresAt: nowMs + seconds * 1000
    };
}

// Whether the access token should be renewed before use: within 5 minutes of expiring.
// An unknown expiry (0) waits for the API to refuse it.
function needsRefresh(expiresAt, nowMs) {
    const at = Number(expiresAt);
    return at > 0 && nowMs >= at - 5 * MINUTE;
}

// Classifies an HTTP result as {kind, detail} for QML to word. kind "" is success.
// status 0 means no reply: the host wasn't reached, or the request timed out.
function apiError(status, body) {
    let detail = "";
    try {
        const json = JSON.parse(body);
        const text = json && typeof json === "object" ? json.error_description || json.error || "" : "";
        detail = typeof text === "string" ? text.trim() : "";
    } catch (e) {
        detail = "";
    }
    function result(kind, d) {
        return { kind: kind, detail: d === undefined ? detail : d };
    }
    if (status >= 200 && status < 300) return result("", "");
    if (status === 0) return result("network", "");
    if (status === 401) return result("auth");
    // Teslemetry, for a request its subscription or credits don't cover.
    if (status === 402) return result("payment");
    if (status === 403) return result("forbidden");
    if (status === 404) return result("notFound");
    if (status === 408) return result("asleep");
    // Fleet API answers from the wrong region with 421.
    if (status === 421) return result("region");
    if (status === 429) return result("rateLimited");
    if (status >= 500) return result("server", String(status));
    return result("http", detail || String(status));
}
