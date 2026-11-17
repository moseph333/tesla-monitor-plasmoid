import QtQuick

// Wording shared by the card, its tooltip and the car drawing. logic.js can't call i18n(),
// so it returns keys and this turns them into text.
QtObject {
    id: texts

    // TeslaMate's door and window names, worded for use in a sentence.
    function partNames() {
        return {
            driver_front: i18n("driver front"), driver_rear: i18n("driver rear"),
            passenger_front: i18n("passenger front"), passenger_rear: i18n("passenger rear")
        }
    }

    // "Closed", "driver front, passenger rear open", "At least one open" (total only) or
    // "—".
    function partsText(states) {
        const names = texts.partNames()
        const open = Object.keys(names).filter(k => states[k] === true).map(k => names[k])
        if (open.length > 0) return i18n("%1 open", open.join(", "))
        const values = Object.keys(names).map(k => states[k])
        if (values.includes("some")) return i18n("At least one open")
        if (values.every(v => v === false)) return i18n("Closed")
        return "—"
    }

    // A models.js key as the model's name.
    function modelName(key) {
        switch (key) {
        case "s": return i18nc("a car model", "Model S")
        case "3": return i18nc("a car model", "Model 3")
        case "x": return i18nc("a car model", "Model X")
        case "y": return i18nc("a car model", "Model Y")
        case "cybertruck": return i18nc("a car model", "Cybertruck")
        default: return ""
        }
    }

    // The model with its trim from Models.trimKey(), such as "Model 3 Performance", or ""
    // when the trim is unknown.
    function modelWithTrim(modelKey, trimKey) {
        const model = texts.modelName(modelKey)
        switch (trimKey) {
        case "plaid": return i18nc("a car model and its trim", "%1 Plaid", model)
        case "performance": return i18nc("a car model and its trim", "%1 Performance", model)
        case "dual": return i18nc("a car model and its trim", "%1 Dual Motor", model)
        default: return ""
        }
    }

    // Lower case: used inside sentences.
    function tireName(pos) {
        switch (pos) {
        case "fl": return i18n("front left")
        case "fr": return i18n("front right")
        case "rl": return i18n("rear left")
        case "rr": return i18n("rear right")
        default: return pos
        }
    }

    // One line per type of item from Logic.attention(), in its order. Doors, windows and
    // tires come as one item per part and share a line.
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
        return types.map(type => texts.attentionLine(type, partsOf[type])).filter(line => line !== "")
    }

    // The line for one type of item and its parts.
    function attentionLine(type, parts) {
        switch (type) {
        case "door": return i18n("Doors: %1", texts.partsText(texts.openStates(parts)))
        case "window": return i18n("Windows: %1", texts.partsText(texts.openStates(parts)))
        case "frunk": return i18n("Frunk open")
        case "trunk": return i18n("Trunk open")
        case "sunroof": return i18n("Sunroof open")
        case "port": return i18n("Charge port open, no cable")
        case "unlocked": return i18n("Unlocked with nobody inside")
        case "tire": return i18n("Low tire pressure: %1", parts.map(pos => texts.tireName(pos)).join(", "))
        case "unhealthy": return i18n("TeslaMate is having trouble reaching the car")
        case "service": return i18n("Service mode is on")
        default: return ""
        }
    }

    // partsText()'s input from a list of open parts. "some" means only the total is known.
    function openStates(parts) {
        const states = {}
        for (const part in texts.partNames())
            states[part] = parts.includes("some") ? "some" : parts.includes(part)
        return states
    }
}
