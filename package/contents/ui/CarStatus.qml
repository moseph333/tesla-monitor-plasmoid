pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic

// Top-down Model 3, nose up, showing everything about the car's body at once: a pressure
// reading beside each wheel, doors that swing out when open, windows, frunk, trunk,
// charge port, lock and Sentry. Hovering lists the same status as text.
// The drawing uses the car's real proportions: 1 unit = 10 mm, the body is 185 × 469.4
// and starts 12 units in from the left so the mirrors fit.
Item {
    id: status

    // Raw TeslaMate values keyed by topic suffix
    property var car: ({})
    // Each: { text: "42 psi", warn: bool }
    property var fl: ({ text: "—", warn: false })
    property var fr: ({ text: "—", warn: false })
    property var rl: ({ text: "—", warn: false })
    property var rr: ({ text: "—", warn: false })
    // TeslaMate names doors and windows by driver and passenger, not left and right.
    property bool rightHandDrive: false

    readonly property real boxWidth: 209
    readonly property real boxHeight: 470
    readonly property real ox: 12
    readonly property real gap: Kirigami.Units.smallSpacing * 2
    readonly property real labelWidth: Math.max(flLabel.implicitWidth, frLabel.implicitWidth,
                                                rlLabel.implicitWidth, rrLabel.implicitWidth)
    // Pixels per unit: as tall as the row allows, leaving room for the readings.
    readonly property real unit: Math.max(0, Math.min(height / boxHeight,
                                                      (width - 2 * (labelWidth + gap)) / boxWidth))
    function u(v) { return v * unit }

    readonly property string leftSeat: rightHandDrive ? "passenger" : "driver"
    readonly property string rightSeat: rightHandDrive ? "driver" : "passenger"
    readonly property var frunkOpen: Logic.triState(car, "frunk_open")
    readonly property var trunkOpen: Logic.triState(car, "trunk_open")
    readonly property var portOpen: Logic.triState(car, "charge_port_door_open")
    readonly property bool pluggedIn: Logic.bool(car, "plugged_in")
    readonly property var locked: Logic.triState(car, "locked")
    readonly property bool sentry: Logic.bool(car, "sentry_mode")

    function doorState(seat, row) {
        return Logic.partOpen(car, seat + "_" + row + "_door_open", "doors_open")
    }
    function windowState(seat, row) {
        return Logic.partOpen(car, seat + "_" + row + "_window_open", "windows_open")
    }

    readonly property color lineColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                Kirigami.Theme.textColor.b, 0.35)
    readonly property color faintColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                 Kirigami.Theme.textColor.b, 0.15)
    readonly property color glassColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                 Kirigami.Theme.textColor.b, 0.07)
    readonly property color openColor: Kirigami.Theme.neutralTextColor
    readonly property color openFill: Qt.rgba(openColor.r, openColor.g, openColor.b, 0.3)

    // Stroke for a part that can be open (true, or "some" when only the total is known).
    function edgeColor(open) {
        return open === true || open === "some" ? openColor : open === null ? faintColor : lineColor
    }

    // ---------- tooltip text ----------

    function openText(open) {
        return open === null ? "—" : (open ? i18n("Open") : i18n("Closed"))
    }

    // "Closed", "Driver front, Passenger rear open", "Open" (total only) or "—".
    function partsText(states) {
        const names = {
            driver_front: i18n("Driver front"), driver_rear: i18n("Driver rear"),
            passenger_front: i18n("Passenger front"), passenger_rear: i18n("Passenger rear")
        }
        const open = Object.keys(names).filter(k => states[k] === true).map(k => names[k])
        if (open.length > 0) return i18n("%1 open", open.join(", "))
        const values = Object.keys(names).map(k => states[k])
        if (values.indexOf("some") >= 0) return i18n("Open")
        if (values.every(v => v === false)) return i18n("Closed")
        return "—"
    }

    function partStates(fn) {
        const out = {}
        for (const seat of ["driver", "passenger"])
            for (const row of ["front", "rear"])
                out[seat + "_" + row] = fn(seat, row)
        return out
    }

    function summary() {
        const lines = []
        if (locked !== null) lines.push(locked ? i18n("Locked") : i18n("Unlocked"))
        lines.push(i18n("Doors: %1", partsText(partStates(doorState))))
        lines.push(i18n("Windows: %1", partsText(partStates(windowState))))
        lines.push(i18n("Frunk: %1", openText(frunkOpen)))
        lines.push(i18n("Trunk: %1", openText(trunkOpen)))
        lines.push(i18n("Charge port: %1", pluggedIn ? i18n("Plugged in") : openText(portOpen)))
        const sentryState = Logic.triState(car, "sentry_mode")
        lines.push(i18n("Sentry: %1", sentryState === null ? "—" : (sentryState ? i18n("On") : i18n("Off"))))
        const low = [[fl, i18n("front left")], [fr, i18n("front right")],
                     [rl, i18n("rear left")], [rr, i18n("rear right")]]
            .filter(t => t[0].warn).map(t => t[1])
        if (low.length > 0) lines.push(i18n("Low tire pressure: %1", low.join(", ")))
        return lines.join("\n")
    }

    implicitWidth: 2 * (labelWidth + gap) + Kirigami.Units.gridUnit * 3
    implicitHeight: Kirigami.Units.gridUnit * 7

    // ---------- parts ----------

    component Reading: PlasmaComponents3.Label {
        property var tire
        text: tire.text
        color: tire.warn ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        font.weight: tire.warn ? Font.Bold : Font.Normal
        font.features: { "tnum": 1 }
    }

    component Wheel: Rectangle {
        property bool onLeft
        property real axle   // y of the axle, in units
        property bool warn
        x: status.u(status.ox + (onLeft ? -8 : 169.5))
        y: status.u(axle - 33)
        width: status.u(23.5)
        height: status.u(66)
        radius: width * 0.4
        color: warn ? Kirigami.Theme.negativeTextColor : status.lineColor
    }

    component Window: Rectangle {
        property bool onLeft
        property real startY
        property real endY
        property var open
        readonly property bool shown: open === true || open === "some"
        x: status.u(status.ox + (onLeft ? 17 : 154))
        y: status.u(startY)
        width: status.u(14)
        height: status.u(endY - startY)
        radius: width * 0.4
        color: shown ? status.openFill : status.glassColor
        border.width: 1
        border.color: status.edgeColor(open)
    }

    // Hinged at its front edge. Swings out only when TeslaMate says which door is open.
    component Door: Rectangle {
        id: door
        property bool onLeft
        property real startY
        property real endY
        property var open
        readonly property bool shown: open === true || open === "some"
        property real swing: open === true ? 30 : 0
        Behavior on swing {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        x: status.u(status.ox + (onLeft ? 2 : 170))
        y: status.u(startY)
        width: status.u(13)
        height: status.u(endY - startY)
        radius: width * 0.35
        color: shown ? status.openFill : "transparent"
        border.width: 1
        // Closed doors are faint seams so the side doesn't read as three parallel lines.
        border.color: shown ? status.openColor : open === null ? "transparent" : status.faintColor
        transform: Rotation {
            origin.x: door.onLeft ? 0 : door.width
            origin.y: 0
            angle: door.onLeft ? door.swing : -door.swing
        }
    }

    // ---------- tire readings ----------

    Reading {
        id: flLabel
        tire: status.fl
        x: drawing.x + status.u(status.ox - 8) - width - status.gap
        y: drawing.y + status.u(84) - height / 2
    }
    Reading {
        id: rlLabel
        tire: status.rl
        x: drawing.x + status.u(status.ox - 8) - width - status.gap
        y: drawing.y + status.u(371.5) - height / 2
    }
    Reading {
        id: frLabel
        tire: status.fr
        x: drawing.x + status.u(status.ox + 193) + status.gap
        y: drawing.y + status.u(84) - height / 2
    }
    Reading {
        id: rrLabel
        tire: status.rr
        x: drawing.x + status.u(status.ox + 193) + status.gap
        y: drawing.y + status.u(371.5) - height / 2
    }

    // ---------- the car ----------

    Item {
        id: drawing
        anchors.centerIn: parent
        width: status.u(status.boxWidth)
        height: status.u(status.boxHeight)

        readonly property size pathScale: Qt.size(status.unit, status.unit)
        readonly property string bodyPath: "M 104.5 0 C 64 0 29 6 20.5 34 C 15.5 50 13 72 12.5 104 L 12 330 C 12 385 13.5 422 16.5 441 C 20.5 459 44 466.5 74 468.5 C 86 469.4 96 469.4 104.5 469.4 C 113 469.4 123 469.4 135 468.5 C 165 466.5 188.5 459 192.5 441 C 195.5 422 197 385 197 330 L 196.5 104 C 196 72 193.5 50 188.5 34 C 180 6 145 0 104.5 0 Z"
        // Windshield, roof and rear window
        readonly property string glassPath: "M 37 118 C 67 124 142 124 172 118 L 163 198 C 134 202 75 202 46 198 Z M 46 204 C 75 208 134 208 163 204 L 163 292 C 134 295 75 295 46 292 Z M 46 298 C 75 301 134 301 163 298 L 159 390 C 134 395 75 395 50 390 Z"
        readonly property string frunkPath: "M 104.5 9 C 70 9 40 14 33 38 L 35 110 C 67 116 142 116 174 110 L 176 38 C 169 14 139 9 104.5 9 Z"
        readonly property string trunkPath: "M 50 397 C 75 402 134 402 159 397 L 174 436 C 164 453 137 459 104.5 459 C 72 459 45 453 35 436 Z"
        // From the port on the left rear, out to the side
        readonly property string cablePath: "M 14 422 C 6 423 0 432 -2 450"

        HoverHandler { id: hover }
        PlasmaComponents3.ToolTip {
            visible: hover.hovered
            text: status.summary()
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Sentry: a red glow around the body
            ShapePath {
                fillColor: "transparent"
                strokeColor: status.sentry
                    ? Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g,
                              Kirigami.Theme.negativeTextColor.b, 0.35)
                    : "transparent"
                strokeWidth: Kirigami.Units.smallSpacing * 1.5
                joinStyle: ShapePath.RoundJoin
                scale: drawing.pathScale
                PathSvg { path: drawing.bodyPath }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: status.sentry ? Kirigami.Theme.negativeTextColor : status.lineColor
                strokeWidth: 1.5
                joinStyle: ShapePath.RoundJoin
                scale: drawing.pathScale
                PathSvg { path: drawing.bodyPath }
            }

            ShapePath {
                fillColor: status.glassColor
                strokeColor: status.lineColor
                strokeWidth: 1
                joinStyle: ShapePath.RoundJoin
                scale: drawing.pathScale
                PathSvg { path: drawing.glassPath }
            }

            ShapePath {
                fillColor: status.frunkOpen === true ? status.openFill : "transparent"
                strokeColor: status.edgeColor(status.frunkOpen)
                strokeWidth: 1
                joinStyle: ShapePath.RoundJoin
                scale: drawing.pathScale
                PathSvg { path: drawing.frunkPath }
            }

            ShapePath {
                fillColor: status.trunkOpen === true ? status.openFill : "transparent"
                strokeColor: status.edgeColor(status.trunkOpen)
                strokeWidth: 1
                joinStyle: ShapePath.RoundJoin
                scale: drawing.pathScale
                PathSvg { path: drawing.trunkPath }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: status.pluggedIn ? Kirigami.Theme.positiveTextColor : "transparent"
                strokeWidth: 2
                capStyle: ShapePath.RoundCap
                scale: drawing.pathScale
                PathSvg { path: drawing.cablePath }
            }
        }

        Window { onLeft: true; startY: 178; endY: 264; open: status.windowState(status.leftSeat, "front") }
        Window { onLeft: true; startY: 272; endY: 330; open: status.windowState(status.leftSeat, "rear") }
        Window { onLeft: false; startY: 178; endY: 264; open: status.windowState(status.rightSeat, "front") }
        Window { onLeft: false; startY: 272; endY: 330; open: status.windowState(status.rightSeat, "rear") }

        Wheel { onLeft: true; axle: 84; warn: status.fl.warn }
        Wheel { onLeft: false; axle: 84; warn: status.fr.warn }
        Wheel { onLeft: true; axle: 371.5; warn: status.rl.warn }
        Wheel { onLeft: false; axle: 371.5; warn: status.rr.warn }

        // The mirrors sit on the front doors and swing with them.
        Door {
            onLeft: true; startY: 152; endY: 266
            open: status.doorState(status.leftSeat, "front")
            Rectangle {
                x: -width; y: status.u(4)
                width: status.u(14); height: status.u(11)
                radius: height * 0.45
                color: "transparent"
                border.width: 1
                border.color: status.lineColor
            }
        }
        Door { onLeft: true; startY: 270; endY: 336; open: status.doorState(status.leftSeat, "rear") }
        Door {
            onLeft: false; startY: 152; endY: 266
            open: status.doorState(status.rightSeat, "front")
            Rectangle {
                x: parent.width; y: status.u(4)
                width: status.u(14); height: status.u(11)
                radius: height * 0.45
                color: "transparent"
                border.width: 1
                border.color: status.lineColor
            }
        }
        Door { onLeft: false; startY: 270; endY: 336; open: status.doorState(status.rightSeat, "rear") }

        // Charge port, always on the left rear. An open port is expected while plugged in.
        Rectangle {
            visible: status.pluggedIn || status.portOpen !== null
            x: status.u(status.ox + 8) - width / 2
            y: status.u(422) - height / 2
            width: Math.max(status.u(11), Kirigami.Units.smallSpacing * 1.5)
            height: width
            radius: width / 2
            color: status.pluggedIn ? Kirigami.Theme.positiveTextColor
                 : status.portOpen ? status.openColor
                 : "transparent"
            border.width: status.pluggedIn || status.portOpen ? 0 : 1
            border.color: status.lineColor
        }

        Kirigami.Icon {
            visible: status.locked !== null
            anchors.horizontalCenter: parent.horizontalCenter
            y: status.u(248) - height / 2
            width: Math.min(Kirigami.Units.iconSizes.small, status.u(80))
            height: width
            source: status.locked ? "object-locked" : "object-unlocked"
            color: status.locked ? Kirigami.Theme.textColor : Kirigami.Theme.neutralTextColor
            isMask: true
        }
    }
}
