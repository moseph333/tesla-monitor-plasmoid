.pragma library

// Which notifications were sent recently, shared by every copy of the widget. plasmashell
// runs all widgets in one QML engine and a library script exists once per engine, so
// without this a panel icon and a desktop card showing the same car would both notify.
// Kept out of logic.js so that file stays stateless.
const sent = {};

// True for the first caller with this key within windowMs, false after that. Each key
// keeps the window it was claimed with. Expired keys are dropped on each call, as are keys
// from the future, which a clock set back would leave.
function claim(key, nowMs, windowMs) {
    for (const old of Object.keys(sent)) {
        if (nowMs >= sent[old].until || nowMs < sent[old].at) delete sent[old];
    }
    if (sent.hasOwnProperty(key)) return false;
    sent[key] = { at: nowMs, until: nowMs + windowMs };
    return true;
}

// Ends a claim early, once what it was for is fine again.
function release(key) {
    delete sent[key];
}
