import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

// What the car is doing, beside the battery ring. The same lines in the same order whether
// it charges, drives or is parked: a figure and its caption, then a title, a sentence and
// notes. A line with nothing to say is left out.
// They are stacked by columns and not by layouts. A line that wraps is only as high as it
// gets once it has its width, and a layout that needs more than two rounds to settle that
// logs a polish loop on Qt 6.6, as these did with a destination of two lines.
Column {
    id: details

    // main.qml's root item, which knows the car, and the card's Look.
    required property PlasmoidItem widget
    required property Look look

    // The car takes energy back. This goes by the whole kW the figure
    // shows, so "0 kW" is never called regenerating.
    readonly property bool regenerating: widget.power !== null && Math.round(widget.power) < 0

    // A line of parts joined by " · ", broken between its parts where it
    // is too long, so "done by" can't end a line that "4:00 PM" starts
    // and no line ends in a dot. The lines fill from the last part back,
    // which leaves the short line first: "+4.2 kWh" over "16 A · 230 V ·
    // 3 phases". Parts share a line when they fit with a pixel to spare,
    // since the layout also counts how far the last letter overhangs,
    // which FontMetrics doesn't. A part too long for a line wraps as any
    // text does. Every line is as wide as this column, and a label that
    // read its own width here would change it by setting its text.
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
    // A sentence that keeps its last two words together, so it doesn't
    // end in a line of one word. A time such as "7:00 AM" has a no-break
    // space of its own and counts as one word. The two words are only
    // joined when they fit in a line with a little to spare, since text
    // that can't wrap at a space is cut in the middle of a word.
    function noBreakAtEnd(sentence, metrics) {
        metrics.font // re-evaluate when the font changes
        return sentence.replace(/[^ ]+ [^ ]+$/, words =>
            metrics.advanceWidth(words) + Kirigami.Units.smallSpacing <= width
                ? words.replace(" ", "\u00a0") : words)
    }

    // The charge port's status for the card while it isn't charging.
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

    // The charging block's figure. The charger reports no power yet while it starts, and
    // current × voltage stands in when it reports 0 kW, as it can for a slow charge.
    function chargePowerText() {
        if (widget.chargeStatus === "starting") return i18n("Starting…")
        if (widget.chargerKw > 0) return widget.chargerKw + " kW"
        const amps = Logic.num(widget.car, "charger_actual_current")
        const volts = Logic.num(widget.car, "charger_voltage")
        if (amps > 0 && volts > 0) return (amps * volts / 1000).toLocaleString(Qt.locale(), "f", 1) + " kW"
        return i18n("Charging")
    }

    // While charging: when the limit is reached, on the line after how long that takes.
    // The car's estimate counts from when it was published, which the last poll is nearest
    // to, so the time doesn't creep later while data is old.
    function chargeDoneText() {
        if (!widget.chargeRemainingText() || !widget.lastUpdated) return ""
        return i18nc("follows how long a charge still takes", "done by %1",
                     widget.clock(widget.lastUpdated.getTime() + widget.hoursToFull * 60 * 60 * 1000))
    }

    // While charging: the energy added so far and what the charger supplies.
    function chargeSupplyText() {
        const parts = []
        const added = Logic.num(widget.car, "charge_energy_added")
        if (added !== null) parts.push("+" + added.toLocaleString(Qt.locale(), "f", 1) + " kWh")
        const amps = Logic.num(widget.car, "charger_actual_current")
        const volts = Logic.num(widget.car, "charger_voltage")
        if (amps !== null && volts !== null) {
            parts.push(amps + " A", volts + " V")
            const phases = Logic.showPhases(widget.car)
            // ki18n takes the plural form from an integer only, and a number read from a
            // payload is a real even when it's whole.
            if (phases !== null) parts.push(i18np("%1 phase", "%1 phases", phases | 0))
        }
        return parts.join(" · ")
    }

    // The car asks for less than the charger offers when its charge current has been
    // turned down, which explains a slow charge.
    function chargeRequestText() {
        const request = Logic.num(widget.car, "charge_current_request")
        const requestMax = Logic.num(widget.car, "charge_current_request_max")
        return request !== null && requestMax !== null && request < requestMax
            ? i18n("Requested %1 of %2 A", request, requestMax) : ""
    }

    // On a route: when the car arrives, and how much of that is traffic.
    function routeArrivalText() {
        const t = widget.route !== null && widget.route.minutes !== null ? Logic.formatHours(widget.route.minutes / 60) : ""
        if (!t) return ""
        const arriving = i18n("Arriving in %1", t)
        return widget.route.trafficMinutes >= 1
            ? arriving + " · " + i18n("+%1 traffic", Logic.formatHours(widget.route.trafficMinutes / 60)) : arriving
    }

    // On a route: how far it still is, and the battery level the car expects to arrive with.
    function routeRemainingText() {
        if (widget.route === null) return ""
        const parts = []
        if (widget.route.km !== null) parts.push(i18n("%1 to go", widget.fmtDistance(widget.route.km, true)))
        // Negative when the battery won't last as far as the destination.
        if (widget.route.energyAtArrival !== null) parts.push(i18n("%1% on arrival", widget.signed(widget.route.energyAtArrival)))
        return parts.join(" · ")
    }

    // The charge limit, with the range a charge to it gives when that can be worked out.
    function limitText() {
        if (widget.limit < 0) return ""
        const parts = [i18n("Limit %1%", widget.limit)]
        if (widget.limit > 0 && widget.level > 0 && widget.rangeKm !== null)
            parts.push(i18nc("the range a charge to the limit gives", "about %1",
                             widget.fmtDistance(widget.rangeKm / widget.level * widget.limit)))
        return parts.join(" · ")
    }

    // When a scheduled charge starts. The status line already says so while the car waits
    // for it.
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

    // What the charger supplies, or what the battery gives while driving,
    // in green when it takes it back.
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

    // Sets the lines apart from the figure, which is semi-bold as a title is.
    Item {
        width: details.width
        height: Kirigami.Units.largeSpacing
        visible: figure.visible && detailLines.height > 0
    }

    Column {
        id: detailLines
        width: details.width
        spacing: Kirigami.Units.smallSpacing

        // The charge port's status while parked, or how long the charge
        // still takes, which is the answer then. With the time it is done
        // on a line of its own, the block has as many lines at any time
        // of day. Smart and solar chargers report no power every evening,
        // so that's a neutral status rather than a warning.
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
        // Where the car is going, when navigation is turned on and it has a
        // route. A destination can be a whole address, so it gets two lines.
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

        // A route takes the limit's place while driving, and a charge takes
        // both.
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
        // What the car asks of the charger, or when a schedule starts.
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
