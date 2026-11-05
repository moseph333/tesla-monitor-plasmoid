.pragma library

// The notifications sent recently, shared by every copy of the widget. plasmashell runs all
// its widgets in one QML engine, and a library script exists once per engine, so a panel
// icon and a desktop card that show the same car would otherwise both notify. This is kept
// out of logic.js so that file holds no state.
var sent = {};

// True for the first caller with this key within windowMs, false for the rest. Each key keeps
// the window it was claimed with, so a short window for one event can't drop another event's
// key early. Old keys are dropped as it goes, and so are keys from the future, which a clock
// set back would leave.
function claim(key, nowMs, windowMs) {
    for (var k in sent) {
        if (nowMs >= sent[k].until || nowMs < sent[k].at) delete sent[k];
    }
    if (sent.hasOwnProperty(key)) return false;
    sent[key] = { at: nowMs, until: nowMs + windowMs };
    return true;
}

// Ends a claim before its window does, once what it was for is fine again, so the next time
// it happens is news.
function release(key) {
    delete sent[key];
}
