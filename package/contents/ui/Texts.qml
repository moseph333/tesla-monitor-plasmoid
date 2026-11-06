import QtQuick

// Wording shared by the card, its tooltip and the car drawing. logic.js can't call i18n(),
// so it hands over keys and this turns them into sentences.
QtObject {
    id: texts

    // "Closed", "driver front, passenger rear open", "At least one open" (total only) or "—".
    function partsText(states) {
        const names = {
            driver_front: i18n("driver front"), driver_rear: i18n("driver rear"),
            passenger_front: i18n("passenger front"), passenger_rear: i18n("passenger rear")
        }
        const open = Object.keys(names).filter(k => states[k] === true).map(k => names[k])
        if (open.length > 0) return i18n("%1 open", open.join(", "))
        const values = Object.keys(names).map(k => states[k])
        if (values.indexOf("some") >= 0) return i18n("At least one open")
        if (values.every(v => v === false)) return i18n("Closed")
        return "—"
    }

    // Lower case, since it's used inside sentences.
    function tireName(pos) {
        switch (pos) {
        case "fl": return i18n("front left")
        case "fr": return i18n("front right")
        case "rl": return i18n("rear left")
        case "rr": return i18n("rear right")
        default: return pos
        }
    }

    // One line per kind of item from Logic.attention(), in its order. Doors, windows and
    // tires each come as one item per part, and share a line.
    function attentionLines(items) {
        const types = []
        const partsOf = {}
        for (const item of items) {
            if (!partsOf[item.type]) {
                partsOf[item.type] = []
                types.push(item.type)
            }
            partsOf[item.type].push(item.part)
        }
        // A "some" item means only the total is known, which partsText words as such.
        function states(list) {
            const out = {}
            for (const p of ["driver_front", "driver_rear", "passenger_front", "passenger_rear"])
                out[p] = list.indexOf("some") >= 0 ? "some" : list.indexOf(p) >= 0
            return out
        }
        const lines = []
        for (const type of types) {
            const list = partsOf[type]
            switch (type) {
            case "door": lines.push(i18n("Doors: %1", texts.partsText(states(list)))); break
            case "window": lines.push(i18n("Windows: %1", texts.partsText(states(list)))); break
            case "frunk": lines.push(i18n("Frunk open")); break
            case "trunk": lines.push(i18n("Trunk open")); break
            case "sunroof": lines.push(i18n("Sunroof open")); break
            case "port": lines.push(i18n("Charge port open, no cable")); break
            case "unlocked": lines.push(i18n("Unlocked with nobody inside")); break
            case "tire": lines.push(i18n("Low tire pressure: %1", list.map(p => texts.tireName(p)).join(", "))); break
            case "unhealthy": lines.push(i18n("TeslaMate is having trouble reaching the car")); break
            case "service": lines.push(i18n("Service mode is on")); break
            }
        }
        return lines
    }
}
