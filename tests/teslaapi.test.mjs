// Unit tests for teslaapi.js. Run with `make test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// The same loader as logic.test.mjs: drop the QML pragma and return the functions.
function load(file) {
    const src = readFileSync(new URL("../package/contents/ui/" + file, import.meta.url), "utf8")
        .replace(/^\.pragma library\s*$/m, "");
    const names = [...src.matchAll(/^function (\w+)\s*\(/gm)].map(m => m[1]);
    return new Function(src + "\nreturn {" + names.join(",") + "};")();
}

function fixture(name) {
    return JSON.parse(readFileSync(new URL("fixtures/" + name, import.meta.url), "utf8"));
}

const Api = load("teslaapi.js");
const L = load("logic.js");
const MINUTE = 60 * 1000;

// The parked fixture with changes made by edit(response).
function parked(edit) {
    const json = fixture("vehicle_data_parked.json");
    if (edit) edit(json.response);
    return json;
}

function close(actual, expected) {
    assert.ok(Math.abs(parseFloat(actual) - expected) < 1e-6, actual + " is not " + expected);
}

test("baseUrl picks a region, or cleans up a custom URL", () => {
    assert.equal(Api.baseUrl(0, "x"), "https://fleet-api.prd.na.vn.cloud.tesla.com");
    assert.equal(Api.baseUrl(1, ""), "https://fleet-api.prd.eu.vn.cloud.tesla.com");
    assert.equal(Api.baseUrl(2, ""), "https://fleet-api.prd.cn.vn.cloud.tesla.cn");
    assert.equal(Api.baseUrl(3, " api.example.com/ "), "https://api.example.com");
    assert.equal(Api.baseUrl(3, "http://localhost:8080//"), "http://localhost:8080");
    assert.equal(Api.baseUrl(3, "  "), "");
});

test("authUrl defaults to Tesla's token server", () => {
    assert.equal(Api.authUrl(""), "https://fleet-auth.prd.vn.cloud.tesla.com");
    assert.equal(Api.authUrl(" http://localhost:9/ "), "http://localhost:9");
});

test("vehicle paths use the cleaned VIN and only ask for location when wanted", () => {
    assert.equal(Api.cleanVin(" 5yj3 e1ea0kf000001 "), "5YJ3E1EA0KF000001");
    assert.equal(Api.vehiclePath("5yj3e1ea0kf000001"), "/api/1/vehicles/5YJ3E1EA0KF000001");
    const plain = decodeURIComponent(Api.vehicleDataPath("v", false));
    assert.equal(plain, "/api/1/vehicles/V/vehicle_data?endpoints="
        + "charge_state;climate_state;drive_state;vehicle_config;vehicle_state");
    assert.ok(decodeURIComponent(Api.vehicleDataPath("v", true)).endsWith(";location_data"));
});

test("fromVehicleData gives TeslaMate's values for a parked car", () => {
    const car = Api.fromVehicleData(parked());
    assert.equal(car.display_name, "Blue Thunder");
    assert.equal(car.state, "online");
    assert.equal(car.model, "3");
    assert.equal(car.exterior_color, "DeepBlue");
    assert.equal(car.version, "2025.32.6");
    assert.equal(car.battery_level, "72");
    assert.equal(car.usable_battery_level, "71");
    assert.equal(car.charge_limit_soc, "80");
    assert.equal(car.charging_state, "Disconnected");
    assert.equal(car.plugged_in, "false");
    assert.equal(car.charge_port_door_open, "false");
    assert.equal(car.scheduled_charging_start_time, "");
    assert.equal(car.charger_phases, undefined);
    close(car.rated_battery_range_km, 200 * 1.609344);
    close(car.est_battery_range_km, 160 * 1.609344);
    close(car.ideal_battery_range_km, 220 * 1.609344);
    close(car.odometer, 10000 * 1.609344);
    assert.equal(car.inside_temp, "21.5");
    assert.equal(car.is_climate_on, "false");
    assert.equal(car.locked, "true");
    assert.equal(car.is_user_present, "false");
    assert.equal(car.driver_front_door_open, "false");
    assert.equal(car.passenger_rear_window_open, "false");
    assert.equal(car.doors_open, "false");
    assert.equal(car.windows_open, "false");
    assert.equal(car.frunk_open, "false");
    assert.equal(car.trunk_open, "false");
    assert.equal(car.tpms_pressure_rl, "2.875");
    assert.equal(car.tpms_soft_warning_fl, "false");
    assert.equal(car.update_available, "false");
    assert.equal(car.update_version, "");
    assert.equal(car.shift_state, "");
    assert.equal(car.speed, undefined);
    assert.equal(car.active_route, "");
    assert.equal(car.sun_roof_installed, undefined);
    // Neither exists in the API.
    assert.equal(car.geofence, undefined);
    assert.equal(car.healthy, undefined);
});

test("fromVehicleData accepts the reply without its response wrapper, and junk", () => {
    assert.equal(Api.fromVehicleData(parked().response).battery_level, "72");
    assert.deepEqual(Api.fromVehicleData(null), {});
    assert.deepEqual(Api.fromVehicleData({ response: null }), {});
});

test("a parked car reads as parked and needing nothing", () => {
    const car = Api.fromVehicleData(parked());
    assert.deepEqual(L.attention(car, []), []);
    assert.equal(L.chargeStatus(car), "unplugged");
    assert.equal(L.isDriving(car), false);
});

test("fromVehicleData derives TeslaMate's state", () => {
    const state = edit => Api.fromVehicleData(parked(edit)).state;
    assert.equal(state(r => { r.drive_state.shift_state = "D"; }), "driving");
    assert.equal(state(r => { r.drive_state.shift_state = "R"; }), "driving");
    assert.equal(state(r => { r.drive_state.shift_state = "N"; }), "driving");
    assert.equal(state(r => { r.drive_state.shift_state = "P"; }), "online");
    assert.equal(state(r => { r.charge_state.charging_state = "Charging"; }), "charging");
    assert.equal(state(r => { r.charge_state.charging_state = "Starting"; }), "charging");
    assert.equal(state(r => { r.vehicle_state.software_update.status = "installing"; }), "updating");
    assert.equal(state(r => { r.state = "asleep"; }), "asleep");
    assert.equal(state(r => { r.state = "offline"; }), "offline");
});

test("a charging car reads as charging, with the charger's details", () => {
    const car = Api.fromVehicleData(parked(r => {
        Object.assign(r.charge_state, {
            charging_state: "Charging", charger_power: 11, charger_voltage: 230,
            charger_actual_current: 16, charger_phases: 3, time_to_full_charge: 1.5,
            charge_port_door_open: true
        });
    }));
    assert.equal(car.state, "charging");
    assert.equal(car.plugged_in, "true");
    assert.equal(L.chargeStatus(car), "charging");
    assert.equal(L.showPhases(car), 3);
    assert.equal(L.num(car, "time_to_full_charge"), 1.5);
    // An open port is expected while plugged in.
    assert.deepEqual(L.attention(car, []), []);
});

test("a scheduled charge's start time becomes ISO, so it reads as scheduled", () => {
    const car = Api.fromVehicleData(parked(r => {
        Object.assign(r.charge_state, {
            charging_state: "Stopped", scheduled_charging_pending: true,
            scheduled_charging_start_time: 1763330400
        });
    }));
    assert.equal(car.scheduled_charging_start_time, "2025-11-16T22:00:00.000Z");
    assert.equal(L.chargeStatus(car), "scheduled");
});

test("open doors, windows, frunk and trunk become TeslaMate's topics and warnings", () => {
    const car = Api.fromVehicleData(parked(r => {
        Object.assign(r.vehicle_state, { df: 1, pr: 1, fp_window: 2, ft: 1, rt: 1, locked: false });
    }));
    assert.equal(car.driver_front_door_open, "true");
    assert.equal(car.passenger_rear_door_open, "true");
    assert.equal(car.driver_rear_door_open, "false");
    assert.equal(car.passenger_front_window_open, "true");
    assert.equal(car.doors_open, "true");
    assert.equal(car.windows_open, "true");
    const ids = L.attention(car, []).map(item => item.id);
    assert.deepEqual(ids, ["unlocked", "door:driver_front", "door:passenger_rear", "window:passenger_front",
                           "frunk", "trunk"]);
});

test("a tire warning and a sunroof pass through", () => {
    const car = Api.fromVehicleData(parked(r => {
        r.vehicle_state.tpms_soft_warning_fr = true;
        r.vehicle_config.sun_roof_installed = 1;
        r.vehicle_state.sun_roof_percent_open = 15;
    }));
    assert.equal(car.sun_roof_installed, "true");
    assert.deepEqual(L.attention(car, []).map(item => item.id), ["tire:fr", "sunroof"]);
});

test("software updates map to TeslaMate's update topics", () => {
    const update = (status, extra) => Api.fromVehicleData(parked(r => {
        Object.assign(r.vehicle_state.software_update, { status: status, version: "2025.38.1" }, extra);
    }));
    assert.deepEqual(L.updateProgress(update("available")), { phase: "available", percent: null });
    assert.deepEqual(L.updateProgress(update("downloading", { download_perc: 40 })),
                     { phase: "downloading", percent: 40 });
    assert.equal(update("scheduled").update_available, "true");
    assert.equal(update("available").update_version, "2025.38.1");
    const installing = update("installing", { install_perc: 30 });
    assert.equal(installing.state, "updating");
    assert.deepEqual(L.updateProgress(installing), { phase: "installing", percent: 30 });
    assert.equal(update("").update_available, "false");
});

test("driving converts mph to km/h and keeps the route in TeslaMate's JSON", () => {
    const car = Api.fromVehicleData(parked(r => {
        Object.assign(r.drive_state, {
            shift_state: "D", speed: 50, power: 25,
            active_route_destination: " Home ", active_route_minutes_to_arrival: 12.5,
            active_route_miles_to_arrival: 8, active_route_energy_at_arrival: 65,
            active_route_traffic_minutes_delay: 2
        });
    }));
    assert.equal(car.state, "driving");
    close(car.speed, 50 * 1.609344);
    assert.equal(car.power, "25");
    const route = L.activeRoute(car);
    assert.equal(route.destination, "Home");
    assert.equal(route.minutes, 12.5);
    assert.equal(route.trafficMinutes, 2);
    assert.equal(route.energyAtArrival, 65);
    close(route.km, 8 * 1.609344);
});

test("modelName maps the API's car types to TeslaMate's", () => {
    const cases = { models: "S", models2: "S", lychee: "S", model3: "3", modelx: "X", tamarind: "X",
                    modely: "Y", cybertruck: "Cybertruck", "": "", roadster: "" };
    for (const type in cases) assert.equal(Api.modelName(type), cases[type], type);
});

test("fromVehicleSummary and parseVehicles read the vehicle list", () => {
    const list = fixture("vehicles.json");
    assert.deepEqual(Api.parseVehicles(list), [
        { vin: "5YJ3E1EA0KF000001", name: "Blue Thunder", state: "online" },
        { vin: "7SAYGDEE0PA000002", name: "", state: "asleep" }
    ]);
    assert.deepEqual(Api.parseVehicles({ response: null }), []);
    assert.deepEqual(Api.fromVehicleSummary({ response: list.response[0] }),
                     { display_name: "Blue Thunder", state: "online" });
    assert.deepEqual(Api.fromVehicleSummary({ response: list.response[1] }), { state: "asleep" });
});

test("mergeSummary keeps the last values and changes only the name and state", () => {
    const last = Api.fromVehicleData(parked());
    const asleep = Api.mergeSummary(last, { state: "asleep" }, false);
    assert.equal(asleep.state, "asleep");
    assert.equal(asleep.battery_level, "72");
    assert.equal(last.state, "online", "the last values are not changed");
    assert.equal(Api.mergeSummary(last, { state: "online" }, true).state, "suspended");
    assert.equal(Api.mergeSummary(last, { state: "online" }, false).state, "online");
    assert.equal(Api.mergeSummary({}, { state: "online", display_name: "X" }, false).display_name, "X");
    assert.deepEqual(Api.mergeSummary(null, { state: "offline" }, false), { state: "offline" });
});

test("trackSince only counts a change this widget saw", () => {
    const t = Date.parse("2026-11-16T10:00:00Z");
    assert.equal(Api.trackSince({}, { state: "online" }, t), "");
    assert.equal(Api.trackSince({ state: "online" }, { state: "asleep" }, t), "2026-11-16T10:00:00.000Z");
    assert.equal(Api.trackSince({ state: "asleep", since: "S" }, { state: "asleep" }, t), "S");
    assert.equal(Api.trackSince({ state: "asleep" }, { state: "asleep" }, t), "");
});

test("isBusy counts what keeps the car awake anyway", () => {
    const idle = Api.fromVehicleData(parked());
    assert.equal(Api.isBusy(idle), false);
    assert.equal(Api.isBusy(null), false);
    for (const change of [{ state: "driving" }, { state: "charging" }, { is_climate_on: "true" },
                          { is_user_present: "true" }, { trunk_open: "true" },
                          { passenger_front_door_open: "true" }, { charging_state: "Starting" }])
        assert.equal(Api.isBusy(Object.assign({}, idle, change)), true, JSON.stringify(change));
    assert.equal(Api.isBusy(Object.assign({}, idle, { driver_front_window_open: "true" })), false);
});

test("pollPlan checks before asking a car of unknown or sleeping state for data", () => {
    assert.equal(Api.pollPlan(null, {}, 0).request, "check");
    const asleep = Api.pollPlan({ activeAt: 0, suspendUntil: 5, lastState: "online" }, { state: "asleep" }, 10);
    assert.equal(asleep.request, "check");
    assert.deepEqual(asleep.state, { activeAt: null, suspendUntil: null, lastState: "asleep" });
    // Asking never wakes it.
    assert.equal(Api.pollPlan(null, { state: "offline" }, 0, { forced: true }).request, "check");
});

test("pollPlan lets an idle car fall asleep, then looks once and lets it sleep again", () => {
    const idle = Api.fromVehicleData(parked());
    let t = 1000 * MINUTE;
    let plan = Api.pollPlan(null, idle, t);
    assert.equal(plan.request, "data");
    // Idle for under 15 minutes: keep asking.
    t += 10 * MINUTE;
    plan = Api.pollPlan(plan.state, idle, t);
    assert.equal(plan.request, "data");
    // 15 minutes idle: only the summary, for 21 minutes.
    t += 5 * MINUTE;
    plan = Api.pollPlan(plan.state, idle, t);
    assert.equal(plan.request, "summary");
    assert.equal(plan.suspended, true);
    const suspended = Object.assign({}, idle, { state: "suspended" });
    t += 15 * MINUTE;
    plan = Api.pollPlan(plan.state, suspended, t);
    assert.equal(plan.request, "summary");
    // Someone asks: the data, without ending the window.
    const forced = Api.pollPlan(plan.state, suspended, t, { forced: true });
    assert.equal(forced.request, "data");
    assert.equal(forced.state.suspendUntil, plan.state.suspendUntil);
    // The window is over and the car still awake: one look, then sleep again.
    t += 6 * MINUTE;
    plan = Api.pollPlan(plan.state, suspended, t);
    assert.equal(plan.request, "data");
    assert.equal(plan.state.suspendUntil, null);
    t += 5 * MINUTE;
    plan = Api.pollPlan(plan.state, idle, t);
    assert.equal(plan.request, "summary");
});

test("pollPlan keeps asking while the car is busy, and after it wakes", () => {
    const idle = Api.fromVehicleData(parked());
    const driving = Object.assign({}, idle, { state: "driving" });
    let t = 0;
    let plan = Api.pollPlan(null, driving, t);
    for (let i = 0; i < 10; i++) {
        t += 5 * MINUTE;
        plan = Api.pollPlan(plan.state, driving, t);
        assert.equal(plan.request, "data");
    }
    // Parked: the idle time counts from the last busy poll.
    t += 5 * MINUTE;
    plan = Api.pollPlan(plan.state, idle, t);
    assert.equal(plan.request, "data");
    t += 11 * MINUTE;
    plan = Api.pollPlan(plan.state, idle, t);
    assert.equal(plan.request, "summary");
    // Asleep, then awake again: a fresh 15 minutes.
    t += 30 * MINUTE;
    plan = Api.pollPlan(plan.state, Object.assign({}, idle, { state: "asleep" }), t);
    assert.equal(plan.request, "check");
    t += 60 * MINUTE;
    plan = Api.pollPlan(plan.state, idle, t);
    assert.equal(plan.request, "data");
    t += 10 * MINUTE;
    plan = Api.pollPlan(plan.state, idle, t);
    assert.equal(plan.request, "data");
});

test("pollPlan survives a clock set back", () => {
    const idle = Api.fromVehicleData(parked());
    const plan = Api.pollPlan({ activeAt: 10 * MINUTE, suspendUntil: 500 * MINUTE, lastState: "online" },
                              idle, 0);
    assert.equal(plan.request, "data");
    assert.equal(plan.state.activeAt, 0);
    assert.equal(plan.state.suspendUntil, null);
});

test("refreshTokenBody encodes the form", () => {
    assert.equal(Api.refreshTokenBody(" id ", "a+b/c="),
                 "grant_type=refresh_token&client_id=id&refresh_token=a%2Bb%2Fc%3D");
});

test("parseTokens reads a token reply and keeps the old refresh token if none came", () => {
    assert.deepEqual(Api.parseTokens({ access_token: "A", refresh_token: "R2", expires_in: 28800 }, "R1", 1000),
                     { access: "A", refresh: "R2", expiresAt: 1000 + 28800 * 1000 });
    assert.deepEqual(Api.parseTokens({ access_token: "A" }, "R1", 0),
                     { access: "A", refresh: "R1", expiresAt: 8 * 3600 * 1000 });
    assert.equal(Api.parseTokens({ error: "invalid_grant" }, "R1", 0), null);
    assert.equal(Api.parseTokens(null, "R1", 0), null);
});

test("needsRefresh renews within 5 minutes of expiry, and never for an unknown expiry", () => {
    assert.equal(Api.needsRefresh(0, 1e12), false);
    assert.equal(Api.needsRefresh(10 * MINUTE, 4 * MINUTE), false);
    assert.equal(Api.needsRefresh(10 * MINUTE, 5 * MINUTE), true);
    assert.equal(Api.needsRefresh(10 * MINUTE, 11 * MINUTE), true);
});

test("apiError classifies HTTP results", () => {
    assert.deepEqual(Api.apiError(200, ""), { kind: "", detail: "" });
    assert.deepEqual(Api.apiError(0, ""), { kind: "network", detail: "" });
    assert.deepEqual(Api.apiError(401, '{"error":"invalid bearer token"}'),
                     { kind: "auth", detail: "invalid bearer token" });
    assert.equal(Api.apiError(403, "").kind, "forbidden");
    assert.equal(Api.apiError(404, "").kind, "notFound");
    assert.deepEqual(Api.apiError(408, '{"response":null,"error":"vehicle unavailable"}'),
                     { kind: "asleep", detail: "vehicle unavailable" });
    assert.equal(Api.apiError(421, "").kind, "region");
    assert.equal(Api.apiError(429, "").kind, "rateLimited");
    assert.deepEqual(Api.apiError(503, "<html>"), { kind: "server", detail: "503" });
    assert.deepEqual(Api.apiError(418, '{"error_description":"teapot"}'), { kind: "http", detail: "teapot" });
    assert.deepEqual(Api.apiError(418, ""), { kind: "http", detail: "418" });
});
