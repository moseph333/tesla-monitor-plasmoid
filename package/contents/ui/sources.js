.pragma library

// The data sources the widget can read the car from, in the order of the dataSource
// setting's values. main.qml and the settings page ask this table what a source is like
// instead of testing for each source by number.
//   key         a name for the source in code
//   kind        "mqtt" (MqttFetch), "fleet" (TeslaApiFetch) or "rest" (RestFetch)
//   cloud       billed or rate-limited online service: polled in minutes, never under 1
//   sleepAware  reaching the car keeps it awake, so polls follow teslaapi.js pollPlan()
//   geofences   reports a named place as TeslaMate's geofence, which "Unlocked is OK at" needs

const MQTT = 0;
const FLEET = 1;
const TESLAMATE_API = 2;
const TESLEMETRY = 3;
const TESSIE = 4;
const HOME_ASSISTANT = 5;

const SOURCES = [
    { id: MQTT, key: "mqtt", kind: "mqtt", name: "TeslaMate", cloud: false, sleepAware: false, geofences: true },
    { id: FLEET, key: "fleet", kind: "fleet", name: "Tesla Fleet API", cloud: true, sleepAware: true,
      geofences: false },
    { id: TESLAMATE_API, key: "teslamateApi", kind: "rest", name: "TeslaMate API", cloud: false, sleepAware: false,
      geofences: true },
    // Whether Teslemetry's cache ever reaches a sleeping car isn't documented, so it is
    // polled as carefully as the Fleet API.
    { id: TESLEMETRY, key: "teslemetry", kind: "fleet", name: "Teslemetry", cloud: true, sleepAware: true,
      geofences: false },
    // Answers from its own copy of the car's state, so polling doesn't keep the car awake.
    // Its saved locations are geofences.
    { id: TESSIE, key: "tessie", kind: "rest", name: "Tessie", cloud: true, sleepAware: false, geofences: true },
    // Reads what Home Assistant's own Tesla integration already fetched; zones are geofences.
    { id: HOME_ASSISTANT, key: "homeAssistant", kind: "rest", name: "Home Assistant", cloud: false,
      sleepAware: false, geofences: true }
];

// The source for a dataSource value. An unknown value reads as TeslaMate over MQTT, the
// default.
function byId(id) {
    return SOURCES[Math.round(Number(id))] || SOURCES[MQTT];
}

// The web page the car's name opens, as {url, name}: TeslaMate's address from the Display
// settings for the TeslaMate sources, Home Assistant's own address, or the service's site.
// The Fleet API has no page of its own, so its url is "". The url is as typed; main.qml
// normalizes it.
function webLink(source, cfg) {
    switch (source.key) {
    case "mqtt":
    case "teslamateApi":
        return { url: String(cfg.teslamateUrl || ""), name: "TeslaMate" };
    case "homeAssistant":
        return { url: String(cfg.haUrl || ""), name: "Home Assistant" };
    case "tessie":
        return { url: "https://my.tessie.com", name: "Tessie" };
    case "teslemetry":
        return { url: "https://teslemetry.com/console", name: "Teslemetry" };
    default:
        return { url: "", name: "" };
    }
}

// The poll rates for a source in seconds, as {active, idle}. Cloud sources have their own
// settings, in minutes on the settings page, and never poll more than once a minute.
function refreshSeconds(source, cfg) {
    if (source.cloud)
        return { active: Math.max(60, cfg.apiRefreshSeconds), idle: Math.max(60, cfg.apiIdleRefreshSeconds) };
    return { active: cfg.refreshSeconds, idle: cfg.idleRefreshSeconds };
}

// How long after the last update opening the popup fetches again, in milliseconds: at
// most once a minute for a cloud source.
function popupRefreshMs(source) {
    return source.cloud ? 60 * 1000 : 5000;
}
