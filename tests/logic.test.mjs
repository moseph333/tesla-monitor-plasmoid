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
