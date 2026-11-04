.pragma library

// The notifications sent recently, shared by every copy of the widget. plasmashell runs all
// its widgets in one QML engine, and a library script exists once per engine, so a panel
// icon and a desktop card that show the same car would otherwise both notify. This is kept
// out of logic.js so that file holds no state.
var sent = {};

// True for the first caller with this key within windowMs, false for the rest. Old keys are
// dropped as it goes, and so are keys from the future, which a clock set back would leave.
function claim(key, nowMs, windowMs) {
    for (var k in sent) {
        if (nowMs - sent[k] >= windowMs || nowMs < sent[k]) delete sent[k];
    }
    if (sent.hasOwnProperty(key)) return false;
    sent[key] = nowMs;
    return true;
}
