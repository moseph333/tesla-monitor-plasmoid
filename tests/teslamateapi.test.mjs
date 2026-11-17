// Unit tests for teslamateapi.js. Run with `make test`.
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

const T = load("teslamateapi.js");
const L = load("logic.js");

// The status fixture with changes made by edit(data).
function status(edit) {
    const json = fixture("teslamateapi_status.json");
    if (edit) edit(json.data);
    return json;
}

function close(actual, expected) {
    assert.ok(Math.abs(parseFloat(actual) - expected) < 1e-6, actual + " is not " + expected);
}

test("baseUrl adds http:// and drops a trailing /api/v1", () => {
    assert.equal(T.baseUrl(" teslamate.local:8080/ "), "http://teslamate.local:8080");
    assert.equal(T.baseUrl("https://tm.example.com/api/v1/"), "https://tm.example.com");
    assert.equal(T.baseUrl("http://10.0.0.5:8080/api"), "http://10.0.0.5:8080");
    assert.equal(T.baseUrl(""), "");
});

test("requestPath asks for a car's status or the cars", () => {
    assert.equal(T.requestPath("data", 1), "/api/v1/cars/1/status");
    assert.equal(T.requestPath("test", "2"), "/api/v1/cars/2/status");
    assert.equal(T.requestPath("cars", 1), "/api/v1/cars");
});

test("carId takes whole numbers from 1", () => {
    assert.equal(T.carId(3), 3);
    assert.equal(T.carId("2"), 2);
    assert.equal(T.carId(0), 0);
    assert.equal(T.carId(1.5), 0);
    assert.equal(T.carId("x"), 0);
});

test("fromStatus gives TeslaMate's values", () => {
    const v = T.fromStatus(status());
    assert.equal(v.display_name, "Blue Thunder");
    assert.equal(v.state, "online");
    assert.equal(v.since, "2026-11-16T08:30:00.000Z");
    assert.equal(v.battery_level, "72");
    assert.equal(v.usable_battery_level, "70");
    close(v.rated_battery_range_km, 345.6);
    close(v.est_battery_range_km, 301.2);
    close(v.ideal_battery_range_km, 352.1);
    close(v.odometer, 24850.6);
    assert.equal(v.charging_state, "Charging");
    assert.equal(v.plugged_in, "true");
    assert.equal(v.charge_limit_soc, "80");
    assert.equal(v.charger_phases, "3");
    assert.equal(v.time_to_full_charge, "1.25");
    assert.equal(v.scheduled_charging_start_time, "");
    assert.equal(v.healthy, "true");
    assert.equal(v.locked, "true");
    assert.equal(v.doors_open, "true");
    assert.equal(v.driver_front_door_open, "true");
    assert.equal(v.windows_open, "false");
    assert.equal(v.model, "3");
    assert.equal(v.exterior_color, "DeepBlue");
    assert.equal(v.geofence, "Home");
    assert.equal(v.version, "2026.38.4");
    assert.equal(v.update_available, "true");
    assert.equal(v.update_version, "2026.38.6");
    assert.equal(v.shift_state, "P");
    close(v.inside_temp, 18.5);
    close(v.outside_temp, -2.5);
    assert.equal(v.active_route, "");
});

test("fromStatus reads TeslaMate's climate keeper mode", () => {
    assert.equal(T.fromStatus(status()).climate_keeper_mode, "off");
    const dog = T.fromStatus(status(d => {
        Object.assign(d.status.climate_details, { is_climate_on: true, climate_keeper_mode: "dog" });
    }));
    assert.equal(dog.climate_keeper_mode, "dog");
    assert.equal(L.climateMode(dog), "dog");
});

test("fromStatus reads the trim, the wheels and the spoiler", () => {
    const v = T.fromStatus(status());
    assert.equal(v.trim_badging, "74D");
    assert.equal(v.wheel_type, "Pinwheel18");
    assert.equal(v.spoiler_type, "None");
    // Nullable columns TeslaMate has no value for.
    const none = T.fromStatus(status(d => {
        d.status.car_details.trim_badging = null;
        d.status.car_exterior.wheel_type = { String: "", Valid: false };
    }));
    assert.equal(none.trim_badging, "");
    assert.equal(none.wheel_type, "");
});

test("fromStatus leaves out a tire pressure TeslaMateApi hasn't received", () => {
    const v = T.fromStatus(status());
    close(v.tpms_pressure_fl, 2.9);
    close(v.tpms_pressure_rl, 2.4);
    assert.equal(v.tpms_pressure_rr, undefined);
    assert.equal(v.tpms_soft_warning_rl, "true");
});

test("fromStatus converts TeslaMate's imperial units back", () => {
    const v = T.fromStatus(status(d => {
        d.units = { unit_of_length: "mi", unit_of_pressure: "psi", unit_of_temperature: "F" };
        d.status.battery_details.rated_battery_range = 200;
        d.status.odometer = 10000;
        d.status.driving_details.speed = 50;
        d.status.tpms_details.tpms_pressure_fl = 42;
        d.status.climate_details.inside_temp = 68;
        d.status.climate_details.outside_temp = 32;
    }));
    close(v.rated_battery_range_km, 200 * 1.609344);
    close(v.odometer, 16093.44);
    close(v.speed, 80.4672);
    close(v.tpms_pressure_fl, 42 / 14.503773800722);
    close(v.inside_temp, 20);
    close(v.outside_temp, 0);
});

test("fromStatus rebuilds TeslaMate's active_route in miles", () => {
    const route = d => Object.assign(d.status.driving_details.active_route, {
        destination: "Office", energy_at_arrival: 61, distance_to_arrival: 12.5,
        minutes_to_arrival: 18.2, traffic_minutes_delay: 2
    });
    const km = JSON.parse(T.fromStatus(status(route)).active_route);
    assert.deepEqual(km, { destination: "Office", minutes_to_arrival: 18.2, miles_to_arrival: 12.5,
                           energy_at_arrival: 61, traffic_minutes_delay: 2 });
    // Set to miles, TeslaMateApi shrinks the miles once more.
    const mi = JSON.parse(T.fromStatus(status(d => {
        route(d);
        d.units.unit_of_length = "mi";
        d.status.driving_details.active_route.distance_to_arrival = 12.5 / 1.609344;
    })).active_route);
    close(mi.miles_to_arrival, 12.5);
    // logic.js reads it like TeslaMate's own topic.
    const parsed = L.activeRoute({ active_route: T.fromStatus(status(route)).active_route });
    assert.equal(parsed.destination, "Office");
});

test("fromStatus treats a battery TeslaMateApi hasn't heard of as unknown", () => {
    const v = T.fromStatus(status(d => {
        Object.assign(d.status.battery_details, { battery_level: 0, rated_battery_range: 0,
                                                  est_battery_range: 0, ideal_battery_range: 0, usable_battery_level: 0 });
        d.status.charging_details.charge_limit_soc = 0;
        d.status.charging_details.charger_phases = 0;
        d.status.state_since = "0001-01-01T00:00:00Z";
    }));
    assert.equal(v.battery_level, undefined);
    assert.equal(v.rated_battery_range_km, undefined);
    assert.equal(v.charge_limit_soc, undefined);
    assert.equal(v.charger_phases, undefined);
    assert.equal(v.since, "");
});

test("fromStatus keeps an unknown charging state as it is", () => {
    const v = T.fromStatus(status(d => { d.status.charging_details.charging_state = "nopower"; }));
    assert.equal(v.charging_state, "NoPower");
    const w = T.fromStatus(status(d => { d.status.charging_details.charging_state = "Something"; }));
    assert.equal(w.charging_state, "Something");
});

test("fromStatus reads the car's name when TeslaMateApi has no display_name", () => {
    const v = T.fromStatus(status(d => { d.status.display_name = ""; }));
    assert.equal(v.display_name, "Blue Thunder");
});

test("fromStatus ignores replies without a status", () => {
    assert.deepEqual(T.fromStatus(null), {});
    assert.deepEqual(T.fromStatus({ error: "x" }), {});
    assert.deepEqual(T.fromStatus({ data: {} }), {});
});

test("TeslaMate API values work with logic.js", () => {
    const v = T.fromStatus(status());
    assert.equal(L.chargeStatus(v), "charging");
    const types = L.attention(v, []).map(a => a.type);
    assert.ok(types.includes("door"));
    assert.ok(types.includes("tire"));
    assert.ok(!types.includes("unhealthy"));
});

test("parseCars lists the cars with their names and VINs", () => {
    assert.deepEqual(T.parseCars(fixture("teslamateapi_cars.json")), [
        { id: 1, name: "Blue Thunder", vin: "5YJ3E1EA0KF000001" },
        { id: 2, name: "", vin: "7SAYGDEE0PF000002" }
    ]);
    assert.deepEqual(T.parseCars({ data: { cars: [{ name: { String: "Red", Valid: true }, car_id: 3 }] } }),
                     [{ id: 3, name: "Red", vin: "" }]);
    assert.deepEqual(T.parseCars({}), []);
});

test("convert reads errors that TeslaMateApi sends with HTTP 200", () => {
    assert.deepEqual(T.convert("data", { error: "no info on this car ID" }), { error: { kind: "noCar", detail: "" } });
    assert.deepEqual(T.convert("data", { error: "Unable to load cars." }),
                     { error: { kind: "service", detail: "Unable to load cars." } });
    assert.deepEqual(T.convert("data", { data: {} }), { error: { kind: "noCar", detail: "" } });
});

test("convert gives data, a summary for a test, or the cars", () => {
    assert.equal(T.convert("data", status()).kind, "data");
    const summary = T.convert("test", status());
    assert.equal(summary.kind, "summary");
    assert.equal(summary.values.display_name, "Blue Thunder");
    assert.equal(T.convert("cars", fixture("teslamateapi_cars.json")).cars.length, 2);
});
