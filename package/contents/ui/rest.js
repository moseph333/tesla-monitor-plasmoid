.pragma library

// Shared by RestFetch.qml for the sources with a simple JSON API over HTTP. Each source's
// own paths and conversions live in its file (teslamateapi.js and so on).

// Classifies an HTTP result as {kind, detail, status} for QML to word. kind "" is success.
// status 0 means no reply: the host wasn't reached, or the request timed out. detail is
// the message in a JSON error body, if there is one.
function httpError(status, body) {
    let detail = "";
    try {
        const json = JSON.parse(body);
        const text = json && typeof json === "object"
            ? json.error_description || json.error || json.message || "" : "";
        detail = typeof text === "string" ? text.trim() : "";
    } catch (e) {
        detail = "";
    }
    function result(kind) {
        return { kind: kind, detail: kind ? detail : "", status: status };
    }
    if (status >= 200 && status < 300) return result("");
    if (status === 0) return result("network");
    if (status === 401) return result("auth");
    if (status === 403) return result("forbidden");
    if (status === 404) return result("notFound");
    if (status === 429) return result("rateLimited");
    if (status >= 500) return result("server");
    return result("http");
}

// The host (and port) of a URL, for messages.
function host(url) {
    const match = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#]+)/i.exec(String(url || ""));
    return match ? match[1] : String(url || "");
}
