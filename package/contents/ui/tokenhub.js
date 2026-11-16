.pragma library

// Tesla API tokens renewed by any copy of the widget, shared by all of them. Renewing
// invalidates the old refresh token and its access tokens, so two copies set up with the
// same tokens would otherwise lock each other out. plasmashell runs all widgets in one QML
// engine and a library script exists once per engine (see notifyhub.js).

// Old refresh token -> the {access, refresh, expiresAt} it was traded for.
const renewed = {};
// Refresh token -> when a copy started renewing it, so others wait instead of racing.
const renewing = {};

// The newest tokens descended from this refresh token, or null if it is the newest.
function latest(refresh) {
    let found = null;
    let key = refresh;
    // A cycle can't happen with real tokens; the limit only guards against one.
    for (let i = 0; i < 50 && key && renewed.hasOwnProperty(key); i++) {
        found = renewed[key];
        key = found.refresh;
    }
    return found;
}

// True if this caller may renew the refresh token now; false while another copy is doing
// so (for up to 30 seconds).
function begin(refresh, nowMs) {
    const started = renewing[refresh];
    if (started !== undefined && nowMs >= started && nowMs - started < 30000) return false;
    renewing[refresh] = nowMs;
    return true;
}

// Records a renewal, or ends a failed one when tokens is null.
function finish(oldRefresh, tokens) {
    delete renewing[oldRefresh];
    if (tokens) renewed[oldRefresh] = tokens;
}
