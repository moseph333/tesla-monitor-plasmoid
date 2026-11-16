.pragma library

// The Tessie source (developer.tessie.com). Tessie keeps the car's latest state and serves
// it in the Tesla Fleet API's vehicle_data shape, without the "response" wrapper, so the
// conversion is teslaapi.js fromVehicleData(), which RestFetch passes in. Tessie doesn't
// bill each request and answers from its own copy, so asking doesn't keep the car awake.

const BASE_URL = "https://api.tessie.com";

// A VIN as typed: spaces dropped, upper case. (The same as teslaapi.js cleanVin().)
function cleanVin(text) {
    return String(text || "").replace(/\s+/g, "").toUpperCase();
}

// The path for a request: "data" reads the car's latest state, "test" whether it's
// awake, and "cars" lists the account's cars.
function requestPath(request, vin) {
    if (request === "cars") return "/vehicles";
    const car = "/" + encodeURIComponent(cleanVin(vin));
    return request === "test" ? car + "/status" : car + "/state?use_cache=true";
}

// GET /{vin}/status as TeslaMate's state.
function stateFromStatus(json) {
    const status = json && typeof json.status === "string" ? json.status : "";
    if (status === "asleep") return "asleep";
    if (status === "waiting_for_sleep") return "suspended";
    if (status === "awake") return "online";
    return "";
}

// GET /vehicles as [{vin, name, state}], in the order given.
function parseVehicles(json) {
    const list = json && Array.isArray(json.results) ? json.results : [];
    return list.filter(v => v && typeof v.vin === "string" && v.vin).map(v => {
        const last = v.last_state && typeof v.last_state === "object" ? v.last_state : {};
        return { vin: v.vin, name: typeof last.display_name === "string" ? last.display_name : "",
                 state: typeof last.state === "string" ? last.state : "" };
    });
}

// A parsed reply for a request, as RestFetch expects. fromVehicleData is teslaapi.js's.
function convert(request, json, fromVehicleData) {
    if (request === "cars") return { kind: "cars", cars: parseVehicles(json) };
    if (request === "test") {
        const state = stateFromStatus(json);
        if (!state) return { error: { kind: "badJson", detail: "" } };
        return { kind: "summary", values: { state: state } };
    }
    if (!json || typeof json !== "object" || (!json.charge_state && !json.vehicle_state))
        return { error: { kind: "badJson", detail: "" } };
    return { kind: "data", values: fromVehicleData(json) };
}
