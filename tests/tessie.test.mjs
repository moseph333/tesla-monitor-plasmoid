// Unit tests for tessie.js. Run with `make test`.
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

const T = load("tessie.js");
const Api = load("teslaapi.js");

test("requestPath reads the state from Tessie's cache", () => {
    assert.equal(T.requestPath("data", "5yj3 e1ea0kf000001"), "/5YJ3E1EA0KF000001/state?use_cache=true");
    assert.equal(T.requestPath("test", "5YJ3E1EA0KF000001"), "/5YJ3E1EA0KF000001/status");
    assert.equal(T.requestPath("cars", ""), "/vehicles");
});

test("convert reads Tessie's state like the Fleet API's vehicle_data", () => {
    const result = T.convert("data", fixture("tessie_state.json"), Api.fromVehicleData);
    const fleet = Api.fromVehicleData(fixture("vehicle_data_parked.json"));
    assert.equal(result.kind, "data");
    assert.deepEqual(result.values, fleet);
    assert.equal(result.values.display_name, "Blue Thunder");
    assert.ok(result.values.battery_level);
});

test("convert keeps a sleeping car's last values", () => {
    const json = fixture("tessie_state.json");
    json.state = "asleep";
    const result = T.convert("data", json, Api.fromVehicleData);
    assert.equal(result.values.state, "asleep");
    assert.ok(result.values.battery_level);
});

test("convert turns the status into TeslaMate's state", () => {
    assert.deepEqual(T.convert("test", { status: "awake" }, Api.fromVehicleData),
                     { kind: "summary", values: { state: "online" } });
    assert.equal(T.convert("test", { status: "asleep" }).values.state, "asleep");
    assert.equal(T.convert("test", { status: "waiting_for_sleep" }).values.state, "suspended");
    assert.deepEqual(T.convert("test", {}), { error: { kind: "badJson", detail: "" } });
});

test("convert lists the account's cars", () => {
    assert.deepEqual(T.convert("cars", fixture("tessie_vehicles.json")).cars, [
        { vin: "5YJ3E1EA0KF000001", name: "Blue Thunder", state: "online" },
        { vin: "7SAYGDEE0PF000002", name: "Old Y", state: "asleep" }
    ]);
    assert.deepEqual(T.parseVehicles({ results: [{ vin: "" }, null, { vin: "X" }] }), [{ vin: "X", name: "", state: "" }]);
    assert.deepEqual(T.parseVehicles({}), []);
});

test("convert refuses a reply that isn't a car's state", () => {
    assert.deepEqual(T.convert("data", { error: "x" }, Api.fromVehicleData), { error: { kind: "badJson", detail: "" } });
});
