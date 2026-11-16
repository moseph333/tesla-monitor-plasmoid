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
