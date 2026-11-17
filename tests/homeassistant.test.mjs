// Unit tests for homeassistant.js. Run with `make test`.
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

const H = load("homeassistant.js");
const L = load("logic.js");
// The fixture's time: the charge ends at 09:30 and the status changed at 08:00.
const NOW = Date.parse("2026-11-16T09:00:00Z");

// The states fixture with entity changes: {entity_id: state or {state, attributes}}.
function states(changes) {
    const list = fixture("homeassistant_states.json");
    for (const id in changes || {}) {
        const change = typeof changes[id] === "string" ? { state: changes[id] } : changes[id];
        const found = list.find(e => e.entity_id === id);
        if (found) Object.assign(found, change, { attributes: Object.assign({}, found.attributes, change.attributes) });
        else list.push(Object.assign({ entity_id: id, attributes: {}, last_changed: "2026-11-16T08:00:00+00:00" }, change));
    }
    return list;
}

function close(actual, expected) {
    assert.ok(Math.abs(parseFloat(actual) - expected) < 1e-6, actual + " is not " + expected);
}

test("baseUrl adds http:// and drops a trailing /api", () => {
    assert.equal(H.baseUrl(" homeassistant.local:8123/ "), "http://homeassistant.local:8123");
    assert.equal(H.baseUrl("https://ha.example.com/api/"), "https://ha.example.com");
    assert.equal(H.baseUrl(""), "");
});

test("cleanPrefix takes the car's part of an entity ID or name", () => {
    assert.equal(H.cleanPrefix("blue_thunder"), "blue_thunder");
    assert.equal(H.cleanPrefix("sensor.blue_thunder_battery_level"), "blue_thunder");
    assert.equal(H.cleanPrefix("binary_sensor.blue_thunder_status"), "blue_thunder");
    assert.equal(H.cleanPrefix(" Blue Thunder "), "blue_thunder");
    assert.equal(H.cleanPrefix(""), "");
});

test("requestPath reads all states", () => {
    assert.equal(H.requestPath("data"), "/api/states");
    assert.equal(H.requestPath("cars"), "/api/states");
});

test("fromStates gives TeslaMate's values in km, bar and °C", () => {
    const v = H.fromStates(states(), "blue_thunder", NOW);
    assert.equal(v.display_name, "Blue Thunder");
    assert.equal(v.state, "charging");
    assert.equal(v.battery_level, "72");
    assert.equal(v.usable_battery_level, "70");
    close(v.rated_battery_range_km, 214.8 * 1.609344);
    close(v.est_battery_range_km, 187.2 * 1.609344);
    assert.equal(v.ideal_battery_range_km, undefined);
    assert.equal(v.charge_limit_soc, "80");
    assert.equal(v.charging_state, "Charging");
    assert.equal(v.plugged_in, "true");
    assert.equal(v.charger_power, "11");
    assert.equal(v.charger_voltage, "230");
    assert.equal(v.charger_actual_current, "16");
    assert.equal(v.charge_energy_added, "12.5");
    close(v.time_to_full_charge, 0.5);
    assert.equal(v.charge_port_door_open, "true");
    assert.equal(v.is_climate_on, "false");
    close(v.inside_temp, (65.3 - 32) * 5 / 9);
    close(v.outside_temp, (27.5 - 32) * 5 / 9);
    assert.equal(v.shift_state, undefined);
    assert.equal(v.speed, "0");
    assert.equal(v.power, "-11");
    close(v.odometer, 15441.3 * 1.609344);
    assert.equal(v.locked, "true");
    assert.equal(v.sentry_mode, "false");
    assert.equal(v.is_user_present, "false");
    assert.equal(v.frunk_open, "false");
    assert.equal(v.trunk_open, "false");
    assert.equal(v.geofence, "Home");
    assert.equal(v.active_route, "");
});

test("fromStates reads doors, windows and tires", () => {
    const v = H.fromStates(states(), "blue_thunder", NOW);
    assert.equal(v.driver_front_door_open, "true");
    assert.equal(v.passenger_rear_door_open, "false");
    assert.equal(v.doors_open, "true");
    assert.equal(v.windows_open, "false");
    assert.equal(v.driver_rear_window_open, "false");
    close(v.tpms_pressure_fl, 42.1 / 14.503773800722);
    close(v.tpms_pressure_rl, 34.8 / 14.503773800722);
    assert.equal(v.tpms_soft_warning_rl, "true");
    assert.equal(v.tpms_soft_warning_fl, "false");
    const types = L.attention(v, []).map(a => a.type);
    assert.ok(types.includes("door"));
    assert.ok(types.includes("tire"));
});

test("fromStates reads the software update", () => {
    const v = H.fromStates(states(), "blue_thunder", NOW);
    assert.equal(v.version, "2026.38.4");
    assert.equal(v.update_available, "true");
    assert.equal(v.update_version, "2026.38.6");
    assert.equal(v.install_perc, undefined);
    const installing = H.fromStates(states({ "update.blue_thunder_update": { attributes: { in_progress: true, update_percentage: 40 } } }),
                                    "blue_thunder", NOW);
    assert.equal(installing.state, "updating");
    assert.equal(installing.install_perc, "40");
    const none = H.fromStates(states({ "update.blue_thunder_update": "off" }), "blue_thunder", NOW);
    assert.equal(none.update_available, "false");
    assert.equal(none.update_version, "");
});

test("fromStates prefers the Tesla Fleet integration's version sensor", () => {
    const v = H.fromStates(states({ "sensor.blue_thunder_version": "2026.40.1" }), "blue_thunder", NOW);
    assert.equal(v.version, "2026.40.1");
});

test("fromStates reads metric units as they are", () => {
    const v = H.fromStates(states({
        "sensor.blue_thunder_battery_range": { state: "345.6", attributes: { unit_of_measurement: "km" } },
        "sensor.blue_thunder_tire_pressure_front_left": { state: "290", attributes: { unit_of_measurement: "kPa" } },
        "sensor.blue_thunder_inside_temperature": { state: "18.5", attributes: { unit_of_measurement: "°C" } },
        "sensor.blue_thunder_speed": { state: "80", attributes: { unit_of_measurement: "km/h" } }
    }), "blue_thunder", NOW);
    close(v.rated_battery_range_km, 345.6);
    close(v.tpms_pressure_fl, 2.9);
    close(v.inside_temp, 18.5);
    close(v.speed, 80);
});

test("fromStates reads Tessie's names", () => {
    const list = states().map(e => {
        if (e.entity_id === "sensor.blue_thunder_estimate_battery_range")
            return Object.assign({}, e, { entity_id: "sensor.blue_thunder_battery_range_estimate" });
        if (e.entity_id === "cover.blue_thunder_charge_port_door")
            return Object.assign({}, e, { entity_id: "binary_sensor.blue_thunder_charge_port_door", state: "on" });
        return e;
    });
    const v = H.fromStates(list, "blue_thunder", NOW);
    close(v.est_battery_range_km, 187.2 * 1.609344);
    assert.equal(v.charge_port_door_open, "true");
});

test("fromStates reads the state from the status, shift and charging", () => {
    const at = (changes) => H.fromStates(states(changes), "blue_thunder", NOW);
    assert.equal(at({ "binary_sensor.blue_thunder_status": "off" }).state, "asleep");
    assert.equal(at({ "binary_sensor.blue_thunder_status": "off" }).since, "2026-11-16T08:00:00.000Z");
    assert.equal(at({ "sensor.blue_thunder_shift_state": "d" }).state, "driving");
    assert.equal(at({ "sensor.blue_thunder_shift_state": "d" }).shift_state, "D");
    assert.equal(at({ "sensor.blue_thunder_charging": "complete" }).state, "online");
    assert.equal(at({ "sensor.blue_thunder_charging": "complete" }).since, "2026-11-16T08:00:00.000Z");
    assert.equal(at({ "sensor.blue_thunder_charging": "no_power" }).charging_state, "NoPower");
    assert.equal(at({ "sensor.blue_thunder_charging": "disconnected" }).plugged_in, "false");
    assert.equal(at({}).since, undefined);
});

test("fromStates reads Teslemetry's sentry mode sensor", () => {
    const list = states().filter(e => e.entity_id !== "switch.blue_thunder_sentry_mode");
    list.push({ entity_id: "sensor.blue_thunder_sentry_mode", state: "armed", attributes: {} });
    assert.equal(H.fromStates(list, "blue_thunder", NOW).sentry_mode, "true");
    list[list.length - 1].state = "off";
    assert.equal(H.fromStates(list, "blue_thunder", NOW).sentry_mode, "false");
});

test("fromStates reads a fast charger's type and the charge rate", () => {
    const v = H.fromStates(states({
        "sensor.blue_thunder_fast_charger_type": "Supercharger",
        "sensor.blue_thunder_charge_rate": { state: "300", attributes: { unit_of_measurement: "mph" } }
    }), "blue_thunder", NOW);
    assert.equal(v.fast_charger_type, "Supercharger");
    assert.equal(v.fast_charger_present, "true");
    close(v.charge_rate_kmh, 300 * 1.609344);
    assert.equal(L.chargerKind(v), "supercharger");
    const metric = H.fromStates(states({
        "sensor.blue_thunder_charge_rate": { state: "52", attributes: { unit_of_measurement: "km/h" } }
    }), "blue_thunder", NOW);
    assert.equal(metric.charge_rate_kmh, "52");
});

test("fastCharger tells DC from AC by the type, and doesn't guess", () => {
    assert.equal(H.fastCharger("Supercharger"), true);
    assert.equal(H.fastCharger("Combo"), true);
    assert.equal(H.fastCharger("CHAdeMO"), true);
    assert.equal(H.fastCharger("ACSingleWireCAN"), false);
    assert.equal(H.fastCharger("<invalid>"), false);
    assert.equal(H.fastCharger("MCSingleWireCAN"), null);
    assert.equal(H.fastCharger(""), null);
    // Without the entity (off by default), nothing is said.
    const v = H.fromStates(states(), "blue_thunder", NOW);
    assert.equal(v.fast_charger_present, undefined);
    assert.equal(v.fast_charger_type, undefined);
    assert.equal(v.charge_rate_kmh, undefined);
});

test("fromStates reads the battery heater", () => {
    assert.equal(H.fromStates(states({ "binary_sensor.blue_thunder_battery_heater": "on" }), "blue_thunder", NOW)
        .battery_heater_on, "true");
    assert.equal(H.fromStates(states({ "binary_sensor.blue_thunder_battery_heater": "off" }), "blue_thunder", NOW)
        .battery_heater_on, "false");
    assert.equal(H.fromStates(states(), "blue_thunder", NOW).battery_heater_on, undefined);
});

test("fromStates rebuilds TeslaMate's active_route in miles", () => {
    const v = H.fromStates(states({
        "sensor.blue_thunder_destination": "Office",
        "sensor.blue_thunder_time_to_arrival": "2026-11-16T09:20:00+00:00",
        "sensor.blue_thunder_distance_to_arrival": { state: "20", attributes: { unit_of_measurement: "km" } },
        "sensor.blue_thunder_state_of_charge_at_arrival": { state: "61", attributes: { unit_of_measurement: "%" } },
        "sensor.blue_thunder_traffic_delay": { state: "2", attributes: { unit_of_measurement: "min" } }
    }), "blue_thunder", NOW);
    const route = JSON.parse(v.active_route);
    assert.equal(route.destination, "Office");
    close(route.minutes_to_arrival, 20);
    close(route.miles_to_arrival, 20 / 1.609344);
    assert.equal(route.energy_at_arrival, 61);
    assert.equal(route.traffic_minutes_delay, 2);
    assert.equal(L.activeRoute({ active_route: v.active_route }).destination, "Office");
});

test("fromStates reads the location's zone as the geofence", () => {
    const at = state => H.fromStates(states({ "device_tracker.blue_thunder_location": state }), "blue_thunder", NOW).geofence;
    assert.equal(at("not_home"), "");
    assert.equal(at("Work"), "Work");
});

test("fromStates finds nothing for another prefix", () => {
    assert.deepEqual(H.fromStates(states(), "nobody", NOW), { active_route: "" });
    assert.deepEqual(H.fromStates(states(), "", NOW), { active_route: "" });
    assert.equal(H.fromStates(states(), "red_y", NOW).state, "asleep");
});

test("findCars lists cars, not phones", () => {
    assert.deepEqual(H.findCars(fixture("homeassistant_states.json")), [
        { prefix: "blue_thunder", name: "Blue Thunder" },
        { prefix: "red_y", name: "Red Y" }
    ]);
    assert.deepEqual(H.findCars({}), []);
});

test("convert gives data, a summary for a test, the cars, or what's missing", () => {
    assert.equal(H.convert("data", states(), "blue_thunder", NOW).kind, "data");
    assert.equal(H.convert("test", states(), "blue_thunder", NOW).kind, "summary");
    assert.equal(H.convert("cars", states(), "", NOW).cars.length, 2);
    assert.deepEqual(H.convert("data", states(), "Nobody", NOW), { error: { kind: "noEntities", detail: "nobody" } });
    assert.deepEqual(H.convert("data", { message: "API running." }, "x", NOW), { error: { kind: "badJson", detail: "" } });
});
