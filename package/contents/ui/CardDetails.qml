import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

// What the car is doing, beside the battery ring. The lines keep the same order whether it
// is charging, driving or parked: a figure and its caption, a title, a sentence and notes.
// Empty lines are left out.
//
// These are Columns, not layouts: a wrapping line only knows its height once it has its
// width, and a layout that needs more than two passes for that logs a polish loop on Qt
// 6.6.
Column {
    id: details

    // main.qml's root item, which has the car's state, and the card's Look.
    required property PlasmoidItem widget
    required property Look look

    // Regenerating, judged by the rounded kW shown, so "0 kW" never counts.
    readonly property bool regenerating: widget.power !== null && Math.round(widget.power) < 0

    // Breaks a line of " · "-separated parts between parts, never inside one, so no line
    // ends in a dot or splits "done by 4:00 PM". Lines fill from the last part backwards,
    // which puts the short line first: "+4.2 kWh" over "16 A · 230 V · 3 phases". The extra
    // pixel allows for the last letter's overhang, which FontMetrics doesn't count. It
    // measures against the column's width: a label reading its own width here would loop.
    function brokenBetweenParts(line, metrics) {
        metrics.font // re-evaluate when the font changes
        const lines = []
        for (const part of line.split(" · ").reverse()) {
            if (lines.length > 0 && metrics.advanceWidth(part + " · " + lines[0]) + 1 <= width)
                lines[0] = part + " · " + lines[0]
            else
                lines.unshift(part)
        }
        return lines.join("\n")
    }
    // Joins a sentence's last two words with a no-break space, so it doesn't end in a
    // one-word line. Only when the two fit on a line with some room: text that can't wrap
    // at a space is cut mid-word.
    function noBreakAtEnd(sentence, metrics) {
        metrics.font // re-evaluate when the font changes
        return sentence.replace(/[^ ]+ [^ ]+$/, words =>
            metrics.advanceWidth(words) + Kirigami.Units.smallSpacing <= width
                ? words.replace(" ", "\u00a0") : words)
    }

    // The charge port's status when not charging.
    function chargeStatusText() {
        switch (widget.chargeStatus) {
        case "complete": return i18n("Charging complete")
        case "stopped": return i18n("Charging stopped")
        case "scheduled": return i18n("Charging starts at %1", widget.clock(Date.parse(widget.car.scheduled_charging_start_time)))
        case "nopower": return i18n("Plugged in, charger has no power")
        case "plugged": return i18n("Plugged in")
        case "unplugged": return i18n("Not plugged in")
        default: return ""
        }
    }

    // The charging figure. The charger reports no power while starting, and can report 0 kW
    // for a slow charge, where current × voltage is used instead.
    function chargePowerText() {
        if (widget.chargeStatus === "starting") return i18n("Starting…")
        if (widget.chargerKw > 0) return widget.chargerKw + " kW"
        const amps = Logic.num(widget.car, "charger_actual_current")
        const volts = Logic.num(widget.car, "charger_voltage")
        if (amps > 0 && volts > 0) return (amps * volts / 1000).toLocaleString(Qt.locale(), "f", 1) + " kW"
        return i18n("Charging")
    }

    // When the charge will be done. The car's estimate counts from when it was published,
    // so this uses the last poll's time, not now, or the time would drift while data is
    // old.
    function chargeDoneText() {
        if (!widget.chargeRemainingText() || !widget.lastUpdated) return ""
        return i18nc("follows how long a charge still takes", "done by %1",
                     widget.clock(widget.lastUpdated.getTime() + widget.hoursToFull * 60 * 60 * 1000))
    }

    // The energy added so far, and what the charger supplies.
    function chargeSupplyText() {
        const parts = []
        const added = Logic.num(widget.car, "charge_energy_added")
        if (added !== null) parts.push("+" + added.toLocaleString(Qt.locale(), "f", 1) + " kWh")
        const amps = Logic.num(widget.car, "charger_actual_current")
        const volts = Logic.num(widget.car, "charger_voltage")
        if (amps !== null && volts !== null) {
            parts.push(amps + " A", volts + " V")
            const phases = Logic.showPhases(widget.car)
            // i18np() needs an integer for the plural form, and payload numbers are reals.
            if (phases !== null) parts.push(i18np("%1 phase", "%1 phases", phases | 0))
        }
        return parts.join(" · ")
    }

    // Shown when the car requests less current than the charger offers, which explains a
    // slow charge.
    function chargeRequestText() {
        const request = Logic.num(widget.car, "charge_current_request")
        const requestMax = Logic.num(widget.car, "charge_current_request_max")
        return request !== null && requestMax !== null && request < requestMax
            ? i18n("Requested %1 of %2 A", request, requestMax) : ""
    }

    // When the car arrives, and how much of that is traffic.
    function routeArrivalText() {
        const t = widget.route !== null && widget.route.minutes !== null ? Logic.formatHours(widget.route.minutes / 60) : ""
        if (!t) return ""
        const arriving = i18n("Arriving in %1", t)
        return widget.route.trafficMinutes >= 1
            ? arriving + " · " + i18n("+%1 traffic", Logic.formatHours(widget.route.trafficMinutes / 60)) : arriving
    }

    // How far is left, and the battery level expected on arrival.
    function routeRemainingText() {
        if (widget.route === null) return ""
        const parts = []
        if (widget.route.km !== null) parts.push(i18n("%1 to go", widget.fmtDistance(widget.route.km, true)))
        // Negative if the battery won't last to the destination.
        if (widget.route.energyAtArrival !== null) parts.push(i18n("%1% on arrival", widget.signed(widget.route.energyAtArrival)))
        return parts.join(" · ")
    }

    // The charge limit, and the range it gives if that can be worked out.
    function limitText() {
        if (widget.limit < 0) return ""
        const parts = [i18n("Limit %1%", widget.limit)]
        if (widget.limit > 0 && widget.level > 0 && widget.rangeKm !== null)
            parts.push(i18nc("the range a charge to the limit gives", "about %1",
                             widget.fmtDistance(widget.rangeKm / widget.level * widget.limit)))
        return parts.join(" · ")
    }

    // When a scheduled charge starts. Empty while the status line already says so.
    function scheduleText() {
        if (widget.chargeStatus === "scheduled") return ""
        const t = Date.parse(widget.car.scheduled_charging_start_time || "")
        return isNaN(t) ? "" : i18n("Scheduled %1", widget.shortTime(new Date(t)))
    }

    FontMetrics {
        id: titleMetrics
        font: title.font
    }
    FontMetrics {
        id: bodyMetrics
        font: body.font
    }
    FontMetrics {
        id: noteMetrics
        font: note.font
    }

    // The charger's power, or the battery's while driving (green when regenerating).
    PlasmaExtras.Heading {
        id: figure
        width: details.width
        visible: widget.charging || (widget.driving && widget.power !== null)
        level: 1
        wrapMode: Text.Wrap
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
        color: widget.charging || details.regenerating ? Kirigami.Theme.positiveTextColor
                                                     : Kirigami.Theme.textColor
        text: widget.charging ? details.chargePowerText()
            : widget.power !== null ? widget.signed(widget.power) + " kW" : ""
    }
    PlasmaComponents3.Label {
        width: details.width
        visible: !widget.charging && widget.driving && widget.power !== null
        wrapMode: Text.Wrap
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        opacity: look.secondary
        text: details.regenerating ? i18n("Regenerating") : i18n("Battery power")
    }

    // Space between the figure and the lines.
    Item {
        width: details.width
        height: Kirigami.Units.largeSpacing
        visible: figure.visible && detailLines.height > 0
    }

    Column {
        id: detailLines
        width: details.width
        spacing: Kirigami.Units.smallSpacing

        // The charge port's status when parked, or how long the charge will take. No power
        // is a neutral status, not a warning: smart and solar chargers report it every
        // evening.
        PlasmaComponents3.Label {
            id: title
            width: detailLines.width
            visible: !widget.driving && text !== ""
            wrapMode: Text.Wrap
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: widget.chargeStatus === "nopower" ? Kirigami.Theme.neutralTextColor
                                                   : Kirigami.Theme.textColor
            text: details.noBreakAtEnd(widget.charging ? widget.chargeRemainingText()
                                       : details.chargeStatusText(), titleMetrics)
        }
        // The destination, if navigation is on and there is a route. It gets two lines,
        // since it can be a whole address.
        PlasmaComponents3.Label {
            width: detailLines.width
            visible: !widget.charging && widget.route !== null
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.weight: Font.DemiBold
            text: widget.route !== null ? i18n("To %1", widget.route.destination) : ""
            textFormat: Text.PlainText
        }

        // When the charge is done, or when the car arrives.
        PlasmaComponents3.Label {
            id: body
            width: detailLines.width
            visible: text !== ""
            wrapMode: Text.Wrap
            font.features: { "tnum": 1 }
            text: details.brokenBetweenParts(widget.charging ? details.chargeDoneText()
                                             : details.routeArrivalText(), bodyMetrics)
        }

        // The charge's supply, else the route's remaining distance, else the limit.
        PlasmaComponents3.Label {
            id: note
            width: detailLines.width
            visible: text !== ""
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.features: { "tnum": 1 }
            opacity: look.secondary
            text: details.brokenBetweenParts(widget.charging ? details.chargeSupplyText()
                                             : widget.route !== null ? details.routeRemainingText()
                                             : details.limitText(), noteMetrics)
        }
        // What the car requests from the charger, or when a schedule starts.
        PlasmaComponents3.Label {
            width: detailLines.width
            visible: text !== ""
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.features: { "tnum": 1 }
            opacity: look.secondary
            text: widget.charging ? details.chargeRequestText()
                : widget.driving ? "" : details.scheduleText()
        }
    }
}
