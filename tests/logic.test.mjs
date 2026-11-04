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

test("unit conversions convert only when imperial and pass null through", () => {
    assert.equal(L.distance(100, false), 100);
    assert.ok(Math.abs(L.distance(100, true) - 62.1371) < 1e-9);
    assert.equal(L.distance(null, true), null);
    assert.equal(L.temperature(20, false), 20);
    assert.equal(L.temperature(20, true), 68);
    assert.equal(L.temperature(-40, true), -40);
    assert.equal(L.temperature(null, true), null);
    assert.equal(L.pressure(2.9, false), 2.9);
    assert.ok(Math.abs(L.pressure(2.9, true) - 42.06102) < 1e-9);
    assert.equal(L.pressure(null, true), null);
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

test("openings lists what is open in a stable order", () => {
    assert.deepEqual(L.openings({}), []);
    assert.deepEqual(L.openings({
        windows_open: "true", doors_open: "true", trunk_open: "true", frunk_open: "true",
    }), ["frunk", "trunk", "doors", "windows"]);
    assert.deepEqual(L.openings({ trunk_open: "false", doors_open: "true" }), ["doors"]);
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
