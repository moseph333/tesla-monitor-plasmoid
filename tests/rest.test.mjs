// Unit tests for rest.js. Run with `make test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const R = load("rest.js");

test("httpError classifies statuses", () => {
    assert.deepEqual(R.httpError(200, ""), { kind: "", detail: "", status: 200 });
    assert.equal(R.httpError(0, "").kind, "network");
    assert.equal(R.httpError(401, "").kind, "auth");
    assert.equal(R.httpError(403, "").kind, "forbidden");
    assert.equal(R.httpError(404, "").kind, "notFound");
    assert.equal(R.httpError(429, "").kind, "rateLimited");
    assert.equal(R.httpError(502, "").kind, "server");
    assert.equal(R.httpError(418, "").kind, "http");
});

test("httpError takes the message from a JSON body", () => {
    assert.equal(R.httpError(500, '{"error":"mqtt disconnected.. status not accessible!"}').detail,
                 "mqtt disconnected.. status not accessible!");
    assert.equal(R.httpError(401, '{"message":"Invalid authentication"}').detail, "Invalid authentication");
    assert.equal(R.httpError(400, '{"error":"invalid","error_description":"bad token"}').detail, "bad token");
    assert.equal(R.httpError(500, "<html>").detail, "");
    assert.equal(R.httpError(500, '{"error":{"code":1}}').detail, "");
});

test("host takes the host and port from a URL", () => {
    assert.equal(R.host("http://teslamate.local:8080"), "teslamate.local:8080");
    assert.equal(R.host("https://api.tessie.com/x?y"), "api.tessie.com");
    assert.equal(R.host("plain"), "plain");
});
