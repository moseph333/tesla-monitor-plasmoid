// Unit tests for sources.js. Run with `make test`.
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

const S = load("sources.js");

const cfg = { refreshSeconds: 15, idleRefreshSeconds: 120, apiRefreshSeconds: 300, apiIdleRefreshSeconds: 900 };

test("byId knows TeslaMate over MQTT and the Fleet API", () => {
    assert.equal(S.byId(0).kind, "mqtt");
    assert.equal(S.byId(1).kind, "fleet");
    assert.equal(S.byId(1).sleepAware, true);
    assert.equal(S.byId(0).geofences, true);
    assert.equal(S.byId(1).geofences, false);
});

test("byId knows the TeslaMate API", () => {
    assert.equal(S.byId(2).key, "teslamateApi");
    assert.equal(S.byId(2).kind, "rest");
    assert.equal(S.byId(2).cloud, false);
    assert.equal(S.byId(2).geofences, true);
    assert.deepEqual(S.refreshSeconds(S.byId(2), cfg), { active: 15, idle: 120 });
});

test("byId knows Teslemetry, read like the Fleet API", () => {
    assert.equal(S.byId(3).key, "teslemetry");
    assert.equal(S.byId(3).kind, "fleet");
    assert.equal(S.byId(3).sleepAware, true);
    assert.deepEqual(S.refreshSeconds(S.byId(3), cfg), { active: 300, idle: 900 });
});

test("byId knows Tessie, an online service that lets the car sleep", () => {
    assert.equal(S.byId(4).key, "tessie");
    assert.equal(S.byId(4).kind, "rest");
    assert.equal(S.byId(4).cloud, true);
    assert.equal(S.byId(4).sleepAware, false);
    assert.equal(S.popupRefreshMs(S.byId(4)), 60000);
});

test("byId knows Home Assistant, read on the local network", () => {
    assert.equal(S.byId(5).key, "homeAssistant");
    assert.equal(S.byId(5).kind, "rest");
    assert.equal(S.byId(5).cloud, false);
    assert.equal(S.byId(5).geofences, true);
    assert.deepEqual(S.refreshSeconds(S.byId(5), cfg), { active: 15, idle: 120 });
});

test("byId falls back to TeslaMate over MQTT", () => {
    assert.equal(S.byId(99).id, 0);
    assert.equal(S.byId(-1).id, 0);
    assert.equal(S.byId(undefined).id, 0);
    assert.equal(S.byId("1").id, 1);
});

test("each source's id is its place in the table", () => {
    for (let i = 0; S.byId(i).id === i && i < 50; i++)
        assert.equal(typeof S.byId(i).name, "string");
});

test("refreshSeconds uses the source's own settings", () => {
    assert.deepEqual(S.refreshSeconds(S.byId(0), cfg), { active: 15, idle: 120 });
    assert.deepEqual(S.refreshSeconds(S.byId(1), cfg), { active: 300, idle: 900 });
});

test("a cloud source never polls more than once a minute", () => {
    const fast = Object.assign({}, cfg, { apiRefreshSeconds: 10, apiIdleRefreshSeconds: 20 });
    assert.deepEqual(S.refreshSeconds(S.byId(1), fast), { active: 60, idle: 60 });
});

test("popupRefreshMs is a minute for a cloud source", () => {
    assert.equal(S.popupRefreshMs(S.byId(0)), 5000);
    assert.equal(S.popupRefreshMs(S.byId(1)), 60000);
});
