// Unit tests for the widget's ".pragma library" scripts. Run with `make test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// The scripts are plain functions behind a QML pragma, so the pragma is dropped and the
// source runs in this realm, which keeps deepEqual's prototype checks meaningful.
function load(file) {
    const src = readFileSync(new URL("../package/contents/ui/" + file, import.meta.url), "utf8")
        .replace(/^\.pragma library\s*$/m, "");
    const names = [...src.matchAll(/^function (\w+)\s*\(/gm)].map(m => m[1]);
    return new Function(src + "\nreturn {" + names.join(",") + "};")();
}

const L = load("logic.js");

test("parseMqtt strips the prefix and ignores other topics", () => {
    const out = [
        "teslamate/cars/1/battery_level 72",
        "teslamate/cars/1/display_name My Model 3",
        "teslamate/cars/10/battery_level 15",
        "teslamate/cars/2/battery_level 40",
        "other/topic 1",
    ].join("\n");
    assert.deepEqual(L.parseMqtt(out, "teslamate/cars/1"), {
        battery_level: "72",
        display_name: "My Model 3",
    });
});

test("parseMqtt keeps spaces in the payload and reads a bare topic as empty", () => {
    const out = "p/geofence  Home  Garage \np/version";
    assert.deepEqual(L.parseMqtt(out, "p"), { geofence: " Home  Garage ", version: "" });
});

test("parseMqtt reads mosquitto_sub's (null) for an empty publish as an empty value", () => {
    const out = "p/geofence (null)\np/display_name (null) car";
    assert.deepEqual(L.parseMqtt(out, "p"), { geofence: "", display_name: "(null) car" });
});

test("parseMqtt tolerates CRLF line endings", () => {
    assert.deepEqual(L.parseMqtt("p/a 1\r\np/b 2\r\n", "p"), { a: "1", b: "2" });
});

test("parseMqtt tolerates a trailing slash on the prefix", () => {
    assert.deepEqual(L.parseMqtt("p/x/a 1", "p/x/"), { a: "1" });
    assert.deepEqual(L.parseMqtt("p/x/a 1", "p/x//"), { a: "1" });
});

test("parseMqtt keeps full topics with an empty or missing prefix", () => {
    const out = "teslamate/cars/1/display_name A\nteslamate/x/cars/2/display_name B";
    const full = {
        "teslamate/cars/1/display_name": "A",
        "teslamate/x/cars/2/display_name": "B",
    };
    assert.deepEqual(L.parseMqtt(out, ""), full);
    assert.deepEqual(L.parseMqtt(out, null), full);
    assert.deepEqual(L.parseMqtt(out, undefined), full);
});

test("parseMqtt skips the prefix topic itself and handles empty output", () => {
    assert.deepEqual(L.parseMqtt("p/ 1\n\n", "p"), {});
    assert.deepEqual(L.parseMqtt("", "p"), {});
    assert.deepEqual(L.parseMqtt(null, "p"), {});
    assert.deepEqual(L.parseMqtt(undefined, "p"), {});
});

test("num parses numbers and treats missing, empty and junk as null", () => {
    const car = { a: "72", b: "3.5", c: "", d: "abc", e: "-12" };
    assert.equal(L.num(car, "a"), 72);
    assert.equal(L.num(car, "b"), 3.5);
    assert.equal(L.num(car, "e"), -12);
    assert.equal(L.num(car, "c"), null);
    assert.equal(L.num(car, "d"), null);
    assert.equal(L.num(car, "missing"), null);
    assert.equal(L.num(null, "a"), null);
});

test("bool is true only for the text true", () => {
    const car = { t: "true", f: "false", e: "", x: "1" };
    assert.equal(L.bool(car, "t"), true);
    assert.equal(L.bool(car, "f"), false);
    assert.equal(L.bool(car, "e"), false);
    assert.equal(L.bool(car, "x"), false);
    assert.equal(L.bool(car, "missing"), false);
    assert.equal(L.bool(null, "t"), false);
});

test("triState is null until the value is true or false", () => {
    const car = { t: "true", f: "false", e: "", x: "yes" };
    assert.equal(L.triState(car, "t"), true);
    assert.equal(L.triState(car, "f"), false);
    assert.equal(L.triState(car, "e"), null);
    assert.equal(L.triState(car, "x"), null);
    assert.equal(L.triState(car, "missing"), null);
    assert.equal(L.triState(undefined, "t"), null);
});

test("partOpen prefers the part's own topic over the total", () => {
    assert.equal(L.partOpen({ own: "false", total: "true" }, "own", "total"), false);
    assert.equal(L.partOpen({ own: "true", total: "false" }, "own", "total"), true);
});

test("partOpen falls back to the total: some, false or null", () => {
    assert.equal(L.partOpen({ total: "true" }, "own", "total"), "some");
    assert.equal(L.partOpen({ own: "", total: "true" }, "own", "total"), "some");
    assert.equal(L.partOpen({ total: "false" }, "own", "total"), false);
    assert.equal(L.partOpen({ total: "" }, "own", "total"), null);
    assert.equal(L.partOpen({}, "own", "total"), null);
});

test("distance converts only to miles and passes null through", () => {
    assert.equal(L.distance(100, "km"), 100);
    assert.ok(Math.abs(L.distance(100, "mi") - 62.1371) < 1e-9);
    assert.equal(L.distance(0, "mi"), 0);
    assert.equal(L.distance(null, "mi"), null);
    assert.equal(L.distance(null, "km"), null);
});

test("temperature converts only to Fahrenheit and passes null through", () => {
    assert.equal(L.temperature(20, "C"), 20);
    assert.equal(L.temperature(20, "F"), 68);
    assert.equal(L.temperature(-40, "F"), -40);
    assert.equal(L.temperature(0, "F"), 32);
    assert.equal(L.temperature(null, "F"), null);
    assert.equal(L.temperature(null, "C"), null);
});

test("pressure converts to psi or kPa and passes null through", () => {
    assert.equal(L.pressure(2.9, "bar"), 2.9);
    assert.ok(Math.abs(L.pressure(2.9, "psi") - 42.06102) < 1e-9);
    assert.ok(Math.abs(L.pressure(2.9, "kPa") - 290) < 1e-9);
    assert.equal(L.pressure(null, "psi"), null);
    assert.equal(L.pressure(null, "kPa"), null);
    assert.equal(L.pressure(null, "bar"), null);
});

test("resolveUnits follows the measurement system on Automatic", () => {
    assert.deepEqual(L.resolveUnits(0, 0, 0, 0), { distance: "km", temperature: "C", pressure: "bar" });
    assert.deepEqual(L.resolveUnits(0, 0, 0, 1), { distance: "mi", temperature: "F", pressure: "psi" });
    assert.deepEqual(L.resolveUnits(0, 0, 0, 2), { distance: "mi", temperature: "C", pressure: "psi" });
});

test("resolveUnits lets each setting override the locale", () => {
    assert.deepEqual(L.resolveUnits(1, 1, 1, 1), { distance: "km", temperature: "C", pressure: "bar" });
    assert.deepEqual(L.resolveUnits(2, 2, 2, 0), { distance: "mi", temperature: "F", pressure: "psi" });
    assert.deepEqual(L.resolveUnits(0, 2, 3, 0), { distance: "km", temperature: "F", pressure: "kPa" });
    assert.deepEqual(L.resolveUnits(1, 0, 0, 2), { distance: "km", temperature: "C", pressure: "psi" });
    assert.deepEqual(L.resolveUnits(0, 0, 3, 1), { distance: "mi", temperature: "F", pressure: "kPa" });
});

test("resolveUnits treats unknown settings and systems as Automatic and metric", () => {
    assert.deepEqual(L.resolveUnits(7, -1, 9, 0), { distance: "km", temperature: "C", pressure: "bar" });
    assert.deepEqual(L.resolveUnits(undefined, undefined, undefined, undefined),
        { distance: "km", temperature: "C", pressure: "bar" });
    assert.deepEqual(L.resolveUnits(0, 0, 0, 5), { distance: "km", temperature: "C", pressure: "bar" });
});

test("unitMigration does nothing once it has run", () => {
    assert.equal(L.unitMigration(true, "broker", true), null);
    assert.equal(L.unitMigration(true, "", false), null);
});

test("unitMigration leaves a new widget on Automatic", () => {
    assert.deepEqual(L.unitMigration(false, "", true), { unitsMigrated: true });
    assert.deepEqual(L.unitMigration(false, "   ", false), { unitsMigrated: true });
    assert.deepEqual(L.unitMigration(false, undefined, true), { unitsMigrated: true });
});

test("unitMigration keeps an existing widget's units", () => {
    assert.deepEqual(L.unitMigration(false, "broker.lan", true),
        { unitsMigrated: true, distanceUnit: 2, temperatureUnit: 2, pressureUnit: 2 });
    assert.deepEqual(L.unitMigration(false, " broker.lan ", false),
        { unitsMigrated: true, distanceUnit: 1, temperatureUnit: 1, pressureUnit: 1 });
});

test("unitMigration's units resolve to what the imperial checkbox showed", () => {
    for (const ms of [0, 1, 2]) {
        const imp = L.unitMigration(false, "h", true);
        assert.deepEqual(L.resolveUnits(imp.distanceUnit, imp.temperatureUnit, imp.pressureUnit, ms),
            { distance: "mi", temperature: "F", pressure: "psi" });
        const met = L.unitMigration(false, "h", false);
        assert.deepEqual(L.resolveUnits(met.distanceUnit, met.temperatureUnit, met.pressureUnit, ms),
            { distance: "km", temperature: "C", pressure: "bar" });
    }
});

test("formatHours shows hours and zero-padded minutes", () => {
    assert.equal(L.formatHours(0.75), "45m");
    assert.equal(L.formatHours(1 + 20 / 60), "1h 20m");
    assert.equal(L.formatHours(1.05), "1h 03m");
    assert.equal(L.formatHours(2), "2h 00m");
    assert.equal(L.formatHours(0), "");
    assert.equal(L.formatHours(-1), "");
    assert.equal(L.formatHours(null), "");
});

test("formatSince counts minutes, hours and days, at least 1m", () => {
    const t0 = Date.parse("2026-01-01T12:00:00Z");
    const iso = "2026-01-01T12:00:00Z";
    assert.equal(L.formatSince(iso, t0 + 30 * 1000), "1m");
    assert.equal(L.formatSince(iso, t0 + 125 * 1000), "2m");
    assert.equal(L.formatSince(iso, t0 + 3600 * 1000), "1h");
    assert.equal(L.formatSince(iso, t0 + 23.9 * 3600 * 1000), "23h");
    assert.equal(L.formatSince(iso, t0 + 2 * 86400 * 1000), "2d");
    assert.equal(L.formatSince(iso, t0 - 60 * 1000), "1m");
    assert.equal(L.formatSince("", t0), "");
    assert.equal(L.formatSince("not a date", t0), "");
});

test("isDriving counts the driving state and an online car in D or R", () => {
    assert.equal(L.isDriving({ state: "driving" }), true);
    assert.equal(L.isDriving({ state: "online", shift_state: "D" }), true);
    assert.equal(L.isDriving({ state: "online", shift_state: "R" }), true);
    assert.equal(L.isDriving({ state: "online", shift_state: "P" }), false);
    assert.equal(L.isDriving({ state: "online", shift_state: "" }), false);
    assert.equal(L.isDriving({ state: "asleep", shift_state: "D" }), false);
    assert.equal(L.isDriving({}), false);
    assert.equal(L.isDriving(null), false);
});

test("chargeStatus maps TeslaMate's charging_state", () => {
    assert.equal(L.chargeStatus({ charging_state: "Charging" }), "charging");
    assert.equal(L.chargeStatus({ charging_state: "Starting" }), "starting");
    assert.equal(L.chargeStatus({ charging_state: "Complete" }), "complete");
    assert.equal(L.chargeStatus({ charging_state: "NoPower", plugged_in: "true" }), "nopower");
    assert.equal(L.chargeStatus({ charging_state: "Disconnected", plugged_in: "true" }), "unplugged");
});

test("chargeStatus tells a stop from a wait for a scheduled start", () => {
    assert.equal(L.chargeStatus({ charging_state: "Stopped" }), "stopped");
    assert.equal(L.chargeStatus({ charging_state: "Stopped", scheduled_charging_start_time: "" }), "stopped");
    assert.equal(L.chargeStatus({ charging_state: "Stopped", scheduled_charging_start_time: "junk" }), "stopped");
    assert.equal(L.chargeStatus({
        charging_state: "Stopped", scheduled_charging_start_time: "2026-01-01T23:00:00Z",
    }), "scheduled");
});

test("chargeStatus reads an unknown charging_state from plugged_in", () => {
    assert.equal(L.chargeStatus({ charging_state: "Mystery", plugged_in: "true" }), "plugged");
    assert.equal(L.chargeStatus({ charging_state: "Mystery", plugged_in: "false" }), "unplugged");
    assert.equal(L.chargeStatus({ charging_state: "Mystery" }), "unplugged");
});

test("chargeStatus falls back to the state and charger power before TeslaMate 1.28", () => {
    assert.equal(L.chargeStatus({ state: "charging" }), "charging");
    assert.equal(L.chargeStatus({ state: "online", charger_power: "7" }), "charging");
    assert.equal(L.chargeStatus({ charging_state: "", charger_power: "11", plugged_in: "true" }), "charging");
    assert.equal(L.chargeStatus({ state: "online", charger_power: "0", plugged_in: "true" }), "plugged");
    assert.equal(L.chargeStatus({ state: "online", plugged_in: "false" }), "unplugged");
    assert.equal(L.chargeStatus({ state: "online", plugged_in: "" }), "");
    assert.equal(L.chargeStatus({}), "");
    assert.equal(L.chargeStatus(null), "");
});

test("usableIfCold shows the usable level only when more than 2 points are held back", () => {
    assert.equal(L.usableIfCold({ battery_level: "68", usable_battery_level: "65" }), 65);
    assert.equal(L.usableIfCold({ battery_level: "67", usable_battery_level: "65" }), null);
    assert.equal(L.usableIfCold({ battery_level: "66", usable_battery_level: "65" }), null);
    assert.equal(L.usableIfCold({ battery_level: "65", usable_battery_level: "65" }), null);
    assert.equal(L.usableIfCold({ battery_level: "68" }), null);
    assert.equal(L.usableIfCold({ usable_battery_level: "65" }), null);
    assert.equal(L.usableIfCold({ battery_level: "68", usable_battery_level: "" }), null);
    assert.equal(L.usableIfCold({}), null);
});

test("updateProgress reports installing while the car updates", () => {
    assert.deepEqual(L.updateProgress({ state: "updating", install_perc: "45" }),
        { phase: "installing", percent: 45 });
    assert.deepEqual(L.updateProgress({ state: "updating", install_perc: "0" }),
        { phase: "installing", percent: null });
    assert.deepEqual(L.updateProgress({ state: "updating", update_available: "false" }),
        { phase: "installing", percent: null });
});

test("updateProgress reports a download or install under way", () => {
    assert.deepEqual(L.updateProgress({ update_available: "true", download_perc: "45" }),
        { phase: "downloading", percent: 45 });
    assert.deepEqual(L.updateProgress({ update_available: "true", download_perc: "100", install_perc: "20" }),
        { phase: "installing", percent: 20 });
});

test("updateProgress shows an update as available at 0 or 100", () => {
    const available = { phase: "available", percent: null };
    assert.deepEqual(L.updateProgress({ update_available: "true" }), available);
    assert.deepEqual(L.updateProgress({ update_available: "true", download_perc: "100" }), available);
    assert.deepEqual(L.updateProgress({ update_available: "true", download_perc: "0", install_perc: "0" }), available);
    assert.deepEqual(L.updateProgress({ update_available: "true", install_perc: "100" }), available);
});

test("updateProgress is empty without an update", () => {
    const none = { phase: "", percent: null };
    assert.deepEqual(L.updateProgress({ update_available: "false", download_perc: "45" }), none);
    assert.deepEqual(L.updateProgress({ update_available: "" }), none);
    assert.deepEqual(L.updateProgress({}), none);
    assert.deepEqual(L.updateProgress(null), none);
});

test("carryHealthy takes a fresh value", () => {
    assert.deepEqual(L.carryHealthy("false", "true", 1000, 5000, 600000), { value: "false", seenAt: 5000 });
    assert.deepEqual(L.carryHealthy("true", undefined, null, 5000, 600000), { value: "true", seenAt: 5000 });
    assert.deepEqual(L.carryHealthy("", "false", 1000, 5000, 600000), { value: "", seenAt: 5000 });
});

test("carryHealthy keeps the last value for up to maxAgeMs after it arrived", () => {
    const seen = 1000;
    assert.deepEqual(L.carryHealthy(undefined, "false", seen, seen + 60000, 600000),
        { value: "false", seenAt: seen });
    assert.deepEqual(L.carryHealthy(undefined, "false", seen, seen + 600000, 600000),
        { value: "false", seenAt: seen });
});

test("carryHealthy drops the value after maxAgeMs or without one", () => {
    const gone = { value: undefined, seenAt: null };
    assert.deepEqual(L.carryHealthy(undefined, "false", 1000, 1000 + 600001, 600000), gone);
    assert.deepEqual(L.carryHealthy(undefined, "false", null, 5000, 600000), gone);
    assert.deepEqual(L.carryHealthy(undefined, undefined, 1000, 2000, 600000), gone);
});

test("geofenceList splits, trims and lower-cases the names", () => {
    assert.deepEqual(L.geofenceList("Home, Work"), ["home", "work"]);
    assert.deepEqual(L.geofenceList(" Home ,, My Garage ,"), ["home", "my garage"]);
    assert.deepEqual(L.geofenceList(""), []);
    assert.deepEqual(L.geofenceList("  , "), []);
    assert.deepEqual(L.geofenceList(undefined), []);
});

// A parked, locked car with everything closed, as a base the attention tests change.
const closed = {
    state: "online", shift_state: "", healthy: "true", service_mode: "false",
    locked: "true", is_user_present: "false", geofence: "",
    tpms_soft_warning_fl: "false", tpms_soft_warning_fr: "false",
    tpms_soft_warning_rl: "false", tpms_soft_warning_rr: "false",
    doors_open: "false", windows_open: "false", frunk_open: "false", trunk_open: "false",
    driver_front_door_open: "false", driver_rear_door_open: "false",
    passenger_front_door_open: "false", passenger_rear_door_open: "false",
    driver_front_window_open: "false", driver_rear_window_open: "false",
    passenger_front_window_open: "false", passenger_rear_window_open: "false",
    sun_roof_installed: "true", sun_roof_percent_open: "0",
    charge_port_door_open: "false", plugged_in: "false",
};
const ids = (car, ok) => L.attention(car, ok || []).map(i => i.id);

test("parts reads each door or window, preferring its own topic over the total", () => {
    assert.deepEqual(L.parts(closed, "door"), {
        driver_front: false, driver_rear: false, passenger_front: false, passenger_rear: false,
    });
    assert.deepEqual(L.parts({ ...closed, doors_open: "true", passenger_rear_door_open: "true" }, "door"), {
        driver_front: false, driver_rear: false, passenger_front: false, passenger_rear: true,
    });
    assert.deepEqual(L.parts({ windows_open: "true", driver_front_window_open: "" }, "window"), {
        driver_front: "some", driver_rear: "some", passenger_front: "some", passenger_rear: "some",
    });
    assert.deepEqual(L.parts({}, "door"), {
        driver_front: null, driver_rear: null, passenger_front: null, passenger_rear: null,
    });
});

test("attention is empty for a closed, locked car", () => {
    assert.deepEqual(L.attention(closed, []), []);
    assert.deepEqual(L.attention({}, []), []);
    assert.deepEqual(L.attention(null, []), []);
});

test("attention lists everything, most severe first", () => {
    const car = {
        ...closed, healthy: "false", service_mode: "true", tpms_soft_warning_rr: "true",
        tpms_soft_warning_fl: "true", locked: "false", passenger_rear_door_open: "true",
        driver_front_window_open: "true", frunk_open: "true", trunk_open: "true",
        sun_roof_percent_open: "15", charge_port_door_open: "true",
    };
    assert.deepEqual(L.attention(car, []), [
        { id: "unhealthy", type: "unhealthy", part: "" },
        { id: "service", type: "service", part: "" },
        { id: "tire:fl", type: "tire", part: "fl" },
        { id: "tire:rr", type: "tire", part: "rr" },
        { id: "unlocked", type: "unlocked", part: "" },
        { id: "door:passenger_rear", type: "door", part: "passenger_rear" },
        { id: "window:driver_front", type: "window", part: "driver_front" },
        { id: "frunk", type: "frunk", part: "" },
        { id: "trunk", type: "trunk", part: "" },
        { id: "sunroof", type: "sunroof", part: "" },
        { id: "port", type: "port", part: "" },
    ]);
});

test("attention names open parts, or says some when only the total is known", () => {
    assert.deepEqual(ids({ ...closed, driver_front_door_open: "true", passenger_front_door_open: "true" }),
        ["door:driver_front", "door:passenger_front"]);
    assert.deepEqual(ids({ doors_open: "true", windows_open: "true" }), ["door:some", "window:some"]);
    assert.deepEqual(L.attention({ windows_open: "true" }, []),
        [{ id: "window:some", type: "window", part: "some" }]);
    // A part's own topic beats the total, and one named part replaces "some".
    assert.deepEqual(ids({ doors_open: "true", driver_rear_door_open: "true" }), ["door:driver_rear"]);
    assert.deepEqual(ids({ ...closed, doors_open: "true" }), []);
});

test("attention reads healthy and service mode only when they say so", () => {
    assert.deepEqual(ids({ ...closed, healthy: "false" }), ["unhealthy"]);
    assert.deepEqual(ids({ ...closed, healthy: "true" }), []);
    assert.deepEqual(ids({ ...closed, healthy: "" }), []);
    assert.deepEqual(ids({ ...closed, service_mode: "true" }), ["service"]);
});

test("attention lists low tires in position order", () => {
    assert.deepEqual(ids({ ...closed, tpms_soft_warning_rl: "true", tpms_soft_warning_fr: "true" }),
        ["tire:fr", "tire:rl"]);
});

test("attention counts unlocked only when nobody is inside and the car isn't driving", () => {
    const unlocked = { ...closed, locked: "false" };
    assert.deepEqual(ids(unlocked), ["unlocked"]);
    assert.deepEqual(ids({ ...unlocked, is_user_present: "true" }), []);
    assert.deepEqual(ids({ ...unlocked, is_user_present: "" }), []);
    assert.deepEqual(ids({ ...unlocked, is_user_present: undefined }), []);
    assert.deepEqual(ids({ ...unlocked, state: "driving" }), []);
    assert.deepEqual(ids({ ...unlocked, shift_state: "D" }), []);
    assert.deepEqual(ids({ ...closed, locked: "" }), []);
});

test("attention skips unlocked at an OK geofence, whatever its case", () => {
    const unlocked = { ...closed, locked: "false", geofence: " Home " };
    assert.deepEqual(ids(unlocked, L.geofenceList("home, Work")), []);
    assert.deepEqual(ids({ ...unlocked, geofence: "WORK" }, L.geofenceList("home, Work")), []);
    assert.deepEqual(ids({ ...unlocked, geofence: "Shop" }, L.geofenceList("home, Work")), ["unlocked"]);
    assert.deepEqual(ids({ ...unlocked, geofence: "" }, L.geofenceList("home")), ["unlocked"]);
    assert.deepEqual(L.attention(unlocked).map(i => i.id), ["unlocked"]);
});

test("attention ignores a sunroof the car doesn't have and an open port with a cable", () => {
    assert.deepEqual(ids({ ...closed, sun_roof_percent_open: "30" }), ["sunroof"]);
    assert.deepEqual(ids({ ...closed, sun_roof_installed: "", sun_roof_percent_open: "30" }), ["sunroof"]);
    assert.deepEqual(ids({ ...closed, sun_roof_installed: "false", sun_roof_percent_open: "30" }), []);
    assert.deepEqual(ids({ ...closed, charge_port_door_open: "true" }), ["port"]);
    assert.deepEqual(ids({ ...closed, charge_port_door_open: "true", plugged_in: "true" }), []);
});

test("isResolved needs a value that says so, not a missing one", () => {
    assert.equal(L.isResolved({ tpms_soft_warning_fl: "false" }, "tire:fl", []), true);
    assert.equal(L.isResolved({}, "tire:fl", []), false);
    assert.equal(L.isResolved({ tpms_soft_warning_fl: "" }, "tire:fl", []), false);
    assert.equal(L.isResolved({ frunk_open: "false" }, "frunk", []), true);
    assert.equal(L.isResolved({}, "trunk", []), false);
    assert.equal(L.isResolved({ update_available: "false" }, "update:2026.2", []), true);
    assert.equal(L.isResolved({}, "update:2026.2", []), false);
    assert.equal(L.isResolved({}, "unhealthy", []), true);
});

test("isResolved reads doors and windows, all four for some", () => {
    assert.equal(L.isResolved({ driver_front_door_open: "false" }, "door:driver_front", []), true);
    assert.equal(L.isResolved({ doors_open: "false" }, "door:driver_front", []), true);
    assert.equal(L.isResolved({}, "door:driver_front", []), false);
    assert.equal(L.isResolved({ doors_open: "false" }, "door:some", []), true);
    assert.equal(L.isResolved(closed, "window:some", []), true);
    assert.equal(L.isResolved({ ...closed, driver_rear_window_open: "", windows_open: "" }, "window:some", []), false);
    assert.equal(L.isResolved({ driver_front_door_open: "false" }, "door:some", []), false);
});

test("isResolved treats a closed port or a cable as fine, and an empty sunroof as unknown", () => {
    assert.equal(L.isResolved({ charge_port_door_open: "false" }, "port", []), true);
    assert.equal(L.isResolved({ charge_port_door_open: "true", plugged_in: "true" }, "port", []), true);
    assert.equal(L.isResolved({ charge_port_door_open: "" }, "port", []), false);
    assert.equal(L.isResolved({ sun_roof_percent_open: "0" }, "sunroof", []), true);
    assert.equal(L.isResolved({ sun_roof_installed: "false", sun_roof_percent_open: "" }, "sunroof", []), true);
    assert.equal(L.isResolved({ sun_roof_percent_open: "" }, "sunroof", []), false);
});

test("isResolved ends unlocked when locked, occupied, driving or at an OK geofence", () => {
    const unlocked = { ...closed, locked: "false" };
    assert.equal(L.isResolved(unlocked, "unlocked", []), false);
    assert.equal(L.isResolved({ ...unlocked, locked: "true" }, "unlocked", []), true);
    assert.equal(L.isResolved({ ...unlocked, locked: "" }, "unlocked", []), false);
    assert.equal(L.isResolved({ ...unlocked, is_user_present: "true" }, "unlocked", []), true);
    assert.equal(L.isResolved({ ...unlocked, state: "driving" }, "unlocked", []), true);
    assert.equal(L.isResolved({ ...unlocked, geofence: "HOME" }, "unlocked", ["home"]), true);
});

test("batteryIcon rounds to Breeze's 10% steps", () => {
    assert.equal(L.batteryIcon(72, false), "battery-070");
    assert.equal(L.batteryIcon(75, false), "battery-080");
    assert.equal(L.batteryIcon(4, false), "battery-000");
    assert.equal(L.batteryIcon(5, false), "battery-010");
    assert.equal(L.batteryIcon(100, false), "battery-100");
    assert.equal(L.batteryIcon(120, false), "battery-100");
    assert.equal(L.batteryIcon(-5, false), "battery-000");
    assert.equal(L.batteryIcon(null, false), "battery-050");
    assert.equal(L.batteryIcon(60, true), "battery-060-charging");
});

test("shellQuote single-quotes and escapes embedded quotes", () => {
    assert.equal(L.shellQuote("abc"), "'abc'");
    assert.equal(L.shellQuote("it's"), "'it'\\''s'");
    assert.equal(L.shellQuote("a b;$(rm)"), "'a b;$(rm)'");
    assert.equal(L.shellQuote(1883), "'1883'");
});

test("parseBrokerHost reads a plain host and host:port", () => {
    const none = { port: null, tls: null, user: "", password: "" };
    assert.deepEqual(L.parseBrokerHost("host"), { host: "host", ...none });
    assert.deepEqual(L.parseBrokerHost("  192.168.1.5  "), { host: "192.168.1.5", ...none });
    assert.deepEqual(L.parseBrokerHost("host:1884"), { ...none, host: "host", port: 1884 });
    assert.deepEqual(L.parseBrokerHost(""), { host: "", ...none });
    assert.deepEqual(L.parseBrokerHost(undefined), { host: "", ...none });
});

test("parseBrokerHost takes a full URL apart", () => {
    assert.deepEqual(L.parseBrokerHost("mqtts://u:p@h:8883/x"),
        { host: "h", port: 8883, tls: true, user: "u", password: "p" });
    assert.deepEqual(L.parseBrokerHost("SSL://broker.lan?x=1#y"),
        { host: "broker.lan", port: null, tls: true, user: "", password: "" });
    assert.equal(L.parseBrokerHost("tls://h").tls, true);
    assert.equal(L.parseBrokerHost("wss://h").tls, true);
    assert.equal(L.parseBrokerHost("mqtt://h").tls, false);
    assert.equal(L.parseBrokerHost("tcp://h").tls, false);
    assert.equal(L.parseBrokerHost("ws://h").tls, false);
    assert.deepEqual(L.parseBrokerHost("http://h:1883"),
        { host: "h", port: 1883, tls: null, user: "", password: "" });
});

test("parseBrokerHost splits credentials at the last @", () => {
    assert.deepEqual(L.parseBrokerHost("u:p@ss@h"),
        { host: "h", port: null, tls: null, user: "u", password: "p@ss" });
    assert.deepEqual(L.parseBrokerHost("me@h"),
        { host: "h", port: null, tls: null, user: "me", password: "" });
    assert.deepEqual(L.parseBrokerHost("user@"),
        { host: "", port: null, tls: null, user: "user", password: "" });
});

test("parseBrokerHost handles IPv6 with and without brackets", () => {
    assert.deepEqual(L.parseBrokerHost("[fd00::1]:1883"),
        { host: "fd00::1", port: 1883, tls: null, user: "", password: "" });
    assert.deepEqual(L.parseBrokerHost("[fd00::1]"),
        { host: "fd00::1", port: null, tls: null, user: "", password: "" });
    assert.deepEqual(L.parseBrokerHost("fd00::1"),
        { host: "fd00::1", port: null, tls: null, user: "", password: "" });
    assert.deepEqual(L.parseBrokerHost("mqtts://[::1]:8883/"),
        { host: "::1", port: 8883, tls: true, user: "", password: "" });
});

test("parseBrokerHost drops a port that isn't a number or is out of range", () => {
    assert.deepEqual(L.parseBrokerHost("h:abc"),
        { host: "h", port: null, tls: null, user: "", password: "" });
    assert.equal(L.parseBrokerHost("h:70000").port, null);
    assert.equal(L.parseBrokerHost("h:0").port, null);
    assert.equal(L.parseBrokerHost("h:65535").port, 65535);
    assert.equal(L.parseBrokerHost("h:").port, null);
    assert.equal(L.parseBrokerHost("h:").host, "h");
});

test("parseBrokerHost leaves no host for a bare scheme", () => {
    assert.deepEqual(L.parseBrokerHost("mqtt://"),
        { host: "", port: null, tls: false, user: "", password: "" });
    assert.equal(L.parseBrokerHost("mqtts:///path").host, "");
});

test("mosquittoCommand builds the base command inside timeout", () => {
    assert.equal(
        L.mosquittoCommand({ host: "broker", port: 1883, topics: ["teslamate/cars/1/#"], wait: 2 }),
        "timeout 12 mosquitto_sub -h 'broker' -p 1883 -t 'teslamate/cars/1/#' -v -W 2");
    assert.equal(
        L.mosquittoCommand({ host: "broker", port: 1883, topics: ["t/#"], wait: 3 }),
        "timeout 13 mosquitto_sub -h 'broker' -p 1883 -t 't/#' -v -W 3");
});

test("mosquittoCommand defaults the wait and the port", () => {
    assert.equal(L.mosquittoCommand({ host: "h", topics: ["t/#"] }),
        "timeout 12 mosquitto_sub -h 'h' -p 1883 -t 't/#' -v -W 2");
    assert.equal(L.mosquittoCommand({ host: "h", port: "1; rm -rf ~", topics: ["t/#"] }),
        "timeout 12 mosquitto_sub -h 'h' -p 1 -t 't/#' -v -W 2");
    assert.equal(L.mosquittoCommand({ host: "h", port: 0, topics: [], wait: 0.2 }),
        "timeout 11 mosquitto_sub -h 'h' -p 1883 -v -W 1");
});

test("mosquittoCommand quotes credentials and lists several topics", () => {
    assert.equal(
        L.mosquittoCommand({
            host: "h", port: 1883, user: "me", password: "it's", wait: 2,
            topics: ["teslamate/cars/+/display_name", "teslamate/+/cars/+/display_name"],
        }),
        "timeout 12 mosquitto_sub -h 'h' -p 1883"
        + " -t 'teslamate/cars/+/display_name' -t 'teslamate/+/cars/+/display_name'"
        + " -v -W 2 -u 'me' -P 'it'\\''s'");
});

test("mosquittoCommand takes the port, TLS and credentials from the host", () => {
    assert.equal(
        L.mosquittoCommand({ host: "mqtts://u:p@h:8884/", port: 1883, topics: ["t/#"], wait: 2 }),
        "timeout 12 mosquitto_sub -h 'h' -p 8884 -t 't/#' -v -W 2 --tls-use-os-certs -u 'u' -P 'p'");
    assert.equal(
        L.mosquittoCommand({ host: "u:p@h", user: "form", password: "secret", topics: [], wait: 2 }),
        "timeout 12 mosquitto_sub -h 'h' -p 1883 -v -W 2 -u 'form' -P 'secret'");
});

test("mosquittoCommand adds TLS with system certificates or a CA file", () => {
    const base = { host: "h", port: 8883, topics: ["t/#"], wait: 2, tls: true };
    const head = "timeout 12 mosquitto_sub -h 'h' -p 8883 -t 't/#' -v -W 2";
    assert.equal(L.mosquittoCommand(base), head + " --tls-use-os-certs");
    assert.equal(L.mosquittoCommand({ ...base, caFile: "  " }), head + " --tls-use-os-certs");
    assert.equal(L.mosquittoCommand({ ...base, caFile: "/etc/ssl/my ca.pem" }),
        head + " --cafile '/etc/ssl/my ca.pem'");
    assert.equal(L.mosquittoCommand({ ...base, caFile: "~/certs/ca.pem" }),
        head + " --cafile ~/'certs/ca.pem'");
    assert.equal(L.mosquittoCommand({ ...base, tls: false, caFile: "/ca.pem" }), head);
});

test("mosquittoCommand returns nothing without a usable host", () => {
    assert.equal(L.mosquittoCommand({ host: "", topics: ["t/#"] }), "");
    assert.equal(L.mosquittoCommand({ host: "   ", topics: ["t/#"] }), "");
    assert.equal(L.mosquittoCommand({ host: "mqtt://", topics: ["t/#"] }), "");
    assert.equal(L.mosquittoCommand({}), "");
    assert.equal(L.mosquittoCommand(undefined), "");
});

test("mqttError treats a timed-out run as fine", () => {
    const ok = { kind: "", detail: "" };
    assert.deepEqual(L.mqttError(27, "Timed out\n", false), ok);
    assert.deepEqual(L.mqttError(0, "Timed out", false), ok);
    assert.deepEqual(L.mqttError(27, "Timed out", true), ok);
    assert.deepEqual(L.mqttError(0, "", false), ok);
    assert.deepEqual(L.mqttError(0, "something odd", true), ok);
});

test("mqttError recognizes a missing client and an unanswered connect", () => {
    assert.equal(L.mqttError(127, "timeout: failed to run command 'mosquitto_sub'", false).kind, "notInstalled");
    assert.equal(L.mqttError(124, "", false).kind, "noAnswer");
});

test("mqttError recognizes TLS setup problems", () => {
    assert.equal(L.mqttError(1, "Error: Unknown option '--tls-use-os-certs'.", false).kind, "oldClient");
    assert.equal(L.mqttError(1, "Error: Problem setting TLS options: File not found.", false).kind, "caFile");
    assert.equal(L.mqttError(14, "Error: Protocol error", false).kind, "tls");
    assert.equal(L.mqttError(1, "Error: Protocol error", false).kind, "tls");
    assert.equal(L.mqttError(14, "", false).kind, "tls");
    assert.equal(L.mqttError(255, "", false).kind, "handshake");
    assert.equal(L.mqttError(255, "  \n", false).kind, "handshake");
});

test("mqttError recognizes rejected credentials", () => {
    assert.equal(L.mqttError(5, "Connection error: Connection Refused: not authorised.", false).kind, "auth");
    assert.equal(L.mqttError(4, "", false).kind, "auth");
    assert.equal(L.mqttError(1, "Connection Refused: bad user name or password.", false).kind, "auth");
    assert.equal(L.mqttError(1, "Error: Not authorized", false).kind, "auth");
});

test("mqttError recognizes lookup, refused and unreachable hosts", () => {
    assert.equal(L.mqttError(1, "Error: Unable to connect (Lookup error.).", false).kind, "lookup");
    assert.equal(L.mqttError(1, "Error: Connection refused", false).kind, "refused");
    assert.deepEqual(L.mqttError(1, "Error: No route to host", false),
        { kind: "unreachable", detail: "No route to host" });
    assert.deepEqual(L.mqttError(1, "Error: Network is unreachable", false),
        { kind: "unreachable", detail: "Network is unreachable" });
    assert.equal(L.mqttError(1, "Error: Connection timed out", false).kind, "unreachable");
});

test("mqttError reports a denied subscription and other complaints without output", () => {
    assert.deepEqual(L.mqttError(0, "All subscription requests were denied.", false),
        { kind: "denied", detail: "" });
    assert.deepEqual(L.mqttError(27, "Error: Something new", false),
        { kind: "other", detail: "Something new" });
});

test("mqttError passes other failures through, or names the exit code", () => {
    assert.deepEqual(L.mqttError(1, "Error: Out of memory.", false),
        { kind: "other", detail: "Out of memory." });
    assert.deepEqual(L.mqttError(3, "", false), { kind: "exit", detail: "3" });
    assert.deepEqual(L.mqttError(255, "Error: weird", false), { kind: "other", detail: "weird" });
});

test("parseCars finds cars with and without a namespace", () => {
    const out = [
        "teslamate/cars/1/display_name Red",
        "teslamate/home/cars/3/display_name Blue",
        "teslamate/cars/1/battery_level 72",
        "teslamate/cars/1/display_name/extra x",
        "other/cars/4/display_name Nope",
    ].join("\n");
    assert.deepEqual(L.parseCars(out), [
        { prefix: "teslamate/cars/1", name: "Red" },
        { prefix: "teslamate/home/cars/3", name: "Blue" },
    ]);
});

test("parseCars sorts by namespace, then by car id as a number", () => {
    const out = [
        "teslamate/b/cars/1/display_name B1",
        "teslamate/cars/10/display_name Ten",
        "teslamate/a/cars/2/display_name A2",
        "teslamate/cars/2/display_name Two",
        "teslamate/cars/x/display_name X",
        "teslamate/cars/9b/display_name Nine",
    ].join("\n");
    assert.deepEqual(L.parseCars(out).map(c => c.prefix), [
        "teslamate/cars/2",
        "teslamate/cars/10",
        "teslamate/cars/9b",
        "teslamate/cars/x",
        "teslamate/a/cars/2",
        "teslamate/b/cars/1",
    ]);
});

test("parseCars keeps a car with an empty name and handles no output", () => {
    assert.deepEqual(L.parseCars("teslamate/cars/1/display_name (null)\n"),
        [{ prefix: "teslamate/cars/1", name: "" }]);
    assert.deepEqual(L.parseCars("teslamate/cars/1/display_name"),
        [{ prefix: "teslamate/cars/1", name: "" }]);
    assert.deepEqual(L.parseCars(""), []);
    assert.deepEqual(L.parseCars(undefined), []);
});
