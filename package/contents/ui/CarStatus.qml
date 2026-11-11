pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic

// Top-down Model 3 showing everything about the car's body at once: a pressure reading at
// each wheel, doors that swing out when open, windows, frunk, trunk, charge port, lock and
// Sentry. Hovering lists the same status as text.
// The car lies on its side with its nose to the right, like the panel icon, or stands nose
// up, whichever draws it larger in the room the item has.
// The body, mirrors and axles use the car's real dimensions: 1 unit = 10 mm, the body is
// 185 × 469.4 and starts 12 units in from the left so the mirrors fit. The wheels sit
// further out than the real track so they stay visible from above.
Item {
    id: root

    // Raw TeslaMate values keyed by topic suffix
    property var car: ({})
    // Each: { value: "42", unit: "psi", text: "42 psi", warn: bool }
    property var fl: ({ value: "—", unit: "", text: "—", warn: false })
    property var fr: ({ value: "—", unit: "", text: "—", warn: false })
    property var rl: ({ value: "—", unit: "", text: "—", warn: false })
    property var rr: ({ value: "—", unit: "", text: "—", warn: false })
    // The body color as "#rrggbb", or "" to draw the car in theme colors.
    property string paint: ""
    // TeslaMate names doors and windows by driver and passenger, not left and right.
    property bool rightHandDrive: false

    // Whether the body is drawn in the car's paint. Nothing looks different for it yet.
    readonly property bool painted: paint !== ""

    // ---------- state ----------

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

    // ---------- colors and lines ----------

    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color lineColor: look.tint(textColor, 0.35)
    readonly property color faintColor: look.tint(textColor, 0.15)
    readonly property color glassColor: look.tint(textColor, 0.07)
    readonly property color tireColor: lineColor
    // A low tire and its reading
    readonly property color lowColor: Kirigami.Theme.negativeTextColor
    readonly property color openColor: Kirigami.Theme.neutralTextColor
    readonly property color openFill: look.tint(openColor, 0.3)
    readonly property color pluggedColor: Kirigami.Theme.positiveTextColor
    readonly property color lockedColor: textColor
    readonly property color unlockedColor: Kirigami.Theme.neutralTextColor
    readonly property color sentryColor: Kirigami.Theme.negativeTextColor

    // Stroke for a part that can be open (true, or "some" when only the total is known).
    function edgeColor(open) {
        return open === true || open === "some" ? openColor : open === null ? faintColor : lineColor
    }
    // The charge port is green with a cable in it, orange when open and empty, a ring when
    // closed, and not drawn while TeslaMate hasn't reported it.
    readonly property color portFill: pluggedIn ? pluggedColor : portOpen ? openColor : "transparent"
    readonly property color portLine: pluggedIn || portOpen !== false ? "transparent" : lineColor

    // The width of the line around a part, around the body, and of the cable.
    readonly property real lineWidth: 1
    readonly property real bodyLineWidth: 1.5
    readonly property real cableWidth: 2

    // ---------- the car, in units, nose up ----------

    readonly property real boxWidth: 209
    readonly property real boxHeight: 470
    readonly property real frontAxle: 84
    readonly property real rearAxle: 371.5
    // The box ends at the mirror tips. The wheels' outer faces are this far inside it.
    readonly property real wheelInset: 4
    // A door is this wide. An open one swings doorSwing degrees around its front edge: the
    // rear corner of a front door, which is 114 long and hinged 14 inside the box, is then
    // doorReach outside the box (114 × sin 30° − 14).
    readonly property real doorWidth: 13
    readonly property real doorSwing: 30
    readonly property real doorReach: 43
    // How far a reading above or below a wheel may reach towards the middle of the car: an
    // open rear door, 13 wide and 66 long from its hinge at 270, ends this far ahead of the
    // rear axle (371.5 − 270 − 13 × sin 30° − 66 × cos 30°).
    readonly property real readingReach: 37.8

    // The car's two sides mirror each other. A part of the left side that reaches from x0
    // to x1 across the car lies between these two places on either side, on whole pixels.
    // The right side's part is the left one's mirror image, taken after rounding: rounded
    // on its own, an edge that falls on half a pixel goes the same way on both sides, and
    // one of the two parts ends up a pixel wider than the other.
    function side(onLeft, x0, x1) {
        return onLeft ? [snap(x0), snap(x1)] : [boxWidth - snap(x1), boxWidth - snap(x0)]
    }

    // The outline of a rectangle with rounded corners, from x0 to x1 across the car and
    // from y0 to y1 along it, and of a circle, as SVG paths.
    function roundedRect(x0, y0, x1, y1, radius) {
        const r = Math.max(0, Math.min(radius, (x1 - x0) / 2, (y1 - y0) / 2))
        return ["M", x0 + r, y0, "H", x1 - r, "A", r, r, 0, 0, 1, x1, y0 + r,
                "V", y1 - r, "A", r, r, 0, 0, 1, x1 - r, y1,
                "H", x0 + r, "A", r, r, 0, 0, 1, x0, y1 - r,
                "V", y0 + r, "A", r, r, 0, 0, 1, x0 + r, y0, "Z"].join(" ")
    }
    function circle(cx, cy, r) {
        return ["M", cx - r, cy, "A", r, r, 0, 1, 0, cx + r, cy,
                "A", r, r, 0, 1, 0, cx - r, cy, "Z"].join(" ")
    }
    // The same rectangle with its edges on whole pixels, and half the width of the line
    // around it further in, so that the straight edges fill whole pixels and are sharp.
    function box(x0, y0, x1, y1, radius, line) {
        const d = inUnits(line / 2)
        return roundedRect(snap(x0) + d, snap(y0) + d, snap(x1) - d, snap(y1) - d, radius)
    }

    // The body's flanks and the edges of the roof are long straight lines along the car.
    // They are moved, by less than half a pixel, to where such a line fills whole pixels.
    readonly property real flank: crisp(12.25, bodyLineWidth)
    readonly property real roofEdge: crisp(46, lineWidth)
    readonly property string bodyPath: [
        "M 104.5 0 C 64 0 29 6 20.5 34 C 15.5 50 13 72", flank, "104 L", flank, "330",
        "C", flank, "385 13.5 422 16.5 441 C 20.5 459 44 466.5 74 468.5 C 86 469.4 96 469.4 104.5 469.4",
        "C 113 469.4 123 469.4 135 468.5 C 165 466.5 188.5 459 192.5 441",
        "C 195.5 422", boxWidth - flank, "385", boxWidth - flank, "330 L", boxWidth - flank, "104",
        "C 196 72 193.5 50 188.5 34 C 180 6 145 0 104.5 0 Z"
    ].join(" ")
    readonly property string frunkPath: "M 104.5 9 C 70 9 40 14 33 38 L 35 110 C 67 116 142 116 174 110 L 176 38 C 169 14 139 9 104.5 9 Z"
    readonly property string trunkPath: "M 50 397 C 75 402 134 402 159 397 L 174 436 C 164 453 137 459 104.5 459 C 72 459 45 453 35 436 Z"
    // Windshield, roof and rear window
    readonly property string glassPath: [
        "M 37 118 C 67 124 142 124 172 118 L", boxWidth - roofEdge, "198 C 134 202 75 202", roofEdge, "198 Z",
        "M", roofEdge, "204 C 75 208 134 208", boxWidth - roofEdge, "204",
        "L", boxWidth - roofEdge, "292 C 134 295 75 295", roofEdge, "292 Z",
        "M", roofEdge, "298 C 75 301 134 301", boxWidth - roofEdge, "298 L 159 390 C 134 395 75 395 50 390 Z"
    ].join(" ")
    // Tires, windows and doors are rounded at their corners by a share of their width, and
    // mirrors by a share of their length.
    function tirePath(onLeft, axle) {
        const w = 23.5
        const [left, right] = side(onLeft, wheelInset, wheelInset + w)
        return box(left, axle - 33, right, axle + 33, w * 0.4, 0)
    }
    function windowPath(onLeft, from, to) {
        const w = 14
        const [left, right] = side(onLeft, 29, 29 + w)
        return box(left, from, right, to, w * 0.4, lineWidth)
    }
    // A door that is w wide and l long once it is on whole pixels, and the mirror on a
    // front door, both measured from the door's own front left corner.
    function doorPath(w, l) {
        return box(0, 0, w, l, doorWidth * 0.35, lineWidth)
    }
    function mirrorPath(onLeft, w) {
        const r = (15 - 4) * 0.45
        return onLeft ? box(-14, 4, 0, 15, r, lineWidth) : box(w, 4, w + 14, 15, r, lineWidth)
    }
    // The charge port is always on the left rear. It keeps a size that can be seen when the
    // car gets small, and then moves back to stay clear of the rear wheel.
    readonly property real portRadius: Math.max(5.5, inUnits(Kirigami.Units.smallSpacing * 0.75))
    readonly property real portY: Math.max(422, rearAxle + 33 + inUnits(1) + portRadius)
    readonly property string portPath: circle(20, portY, portRadius)
    // From the port out to the side
    readonly property string cablePath: "M 14 422 C 6 423 0 432 -2 450"

    // The signs on the glass, on a grid of 20 × 20: a padlock, the same with its shackle
    // lifted out, and a camera's lens for Sentry.
    readonly property string padlockBody: "M 6 9 H 14 A 2 2 0 0 1 16 11 V 16 A 2 2 0 0 1 14 18 H 6 A 2 2 0 0 1 4 16 V 11 A 2 2 0 0 1 6 9 Z M 9 13 A 1 1 0 0 1 11 13 V 14 A 1 1 0 0 1 9 14 Z"
    readonly property string lockPath: "M 6 9 V 6 A 4 4 0 0 1 14 6 V 9 H 12 V 6 A 2 2 0 0 0 8 6 V 9 Z " + padlockBody
    readonly property string unlockPath: "M 6 9 V 4 A 4 4 0 0 1 14 4 V 6 H 12 V 4 A 2 2 0 0 0 8 4 V 9 Z " + padlockBody
    readonly property string sentryPath: "M 2 10 A 8 8 0 1 0 18 10 A 8 8 0 1 0 2 10 Z M 4 10 A 6 6 0 1 0 16 10 A 6 6 0 1 0 4 10 Z M 7 10 A 3 3 0 1 0 13 10 A 3 3 0 1 0 7 10 Z"

    // ---------- scale and orientation ----------

    // The item's size in whole pixels: what the car and its readings have to fit in.
    readonly property int wholeWidth: Math.floor(width)
    readonly property int wholeHeight: Math.floor(height)
    // A line is drawn half outside its shape, and a part can be a pixel off once it's on
    // whole pixels. This keeps what is on the edge of the drawing inside the item.
    readonly property real pad: 2
    // The space between a wheel and the reading beside it. A reading above or below its
    // wheel is closer, since a line of text brings space of its own, and stays that far
    // from an open door too.
    readonly property real gap: Kirigami.Units.smallSpacing * 2
    readonly property real lineGap: Kirigami.Units.smallSpacing
    readonly property real readingWidth: Math.max(flReading.width, frReading.width,
                                                  rlReading.width, rrReading.width)
    readonly property real readingHeight: flReading.height

    // Pixels per unit with the nose up and on its side. Both leave room for the readings and
    // for an open front door, so the car keeps its size when a door opens. They depend on
    // nothing but the item's size and the size of the readings, so choosing between them
    // can't loop.
    readonly property real unitUp: Math.min((wholeHeight - 2 * pad) / boxHeight,
                                            (wholeWidth - 2 * pad) / (boxWidth + 2 * doorReach),
                                            (wholeWidth - 2 * (pad + readingWidth + gap))
                                            / (boxWidth - 2 * wheelInset))
    // The last term keeps room beyond the wheels for a reading that had to move away from
    // the doors: see Reading.
    readonly property real unitSide: Math.min((wholeWidth - 2 * pad) / boxHeight,
                                              (wholeHeight - 2 * pad) / (boxWidth + 2 * doorReach),
                                              (wholeHeight - 2 * (readingHeight + lineGap))
                                              / (boxWidth - 2 * wheelInset),
                                              (wholeWidth / 2 - pad - readingWidth - lineGap)
                                              / (boxHeight / 2 - frontAxle - readingReach))
    readonly property bool sideways: unitSide > unitUp
    // Rounded down to a car that is a whole number of pixels wide. It sits on whole pixels,
    // so its two sides fall on the pixel grid alike and are drawn alike.
    readonly property real unit: Math.max(0, Math.floor((sideways ? unitSide : unitUp) * boxWidth) / boxWidth)
    readonly property size pathScale: Qt.size(unit, unit)
    function u(v) { return v * unit }
    // Pixels in units, for what keeps its size on screen.
    function inUnits(px) { return unit > 0 ? px / unit : 0 }
    // v moved to a whole number of pixels from the car's corner, and to where the middle of
    // a straight line of some width has to be for the line to start on a whole pixel.
    function snap(v) { return inUnits(Math.round(u(v))) }
    function crisp(v, line) { return inUnits(Math.round(u(v) - line / 2) + line / 2) }

    // Where a point of the car is in this item, on a whole pixel. Everything that stays
    // upright while the car turns is placed with it.
    function at(x, y) {
        return sideways ? Qt.point(Math.round(drawing.x - u(y)), Math.round(drawing.y + u(x)))
                        : Qt.point(Math.round(drawing.x + u(x)), Math.round(drawing.y + u(y)))
    }

    // The signs are as large as a small icon. They grow with a car that is larger than the
    // popup's, in even sizes so that they stay centered on a pixel, up to 32 pixels, and
    // they are never larger than the windshield is long.
    readonly property real glyphSize: Math.min(Math.floor(u(78)), Math.max(20, Math.min(32, 2 * Math.floor(u(15)))))

    // ---------- tooltip text ----------

    function openText(open) {
        return open === null ? "—" : (open ? i18n("Open") : i18n("Closed"))
    }

    function summary() {
        const lines = []
        if (locked !== null) lines.push(locked ? i18n("Locked") : i18n("Unlocked"))
        lines.push(i18n("Doors: %1", texts.partsText(Logic.parts(car, "door"))))
        lines.push(i18n("Windows: %1", texts.partsText(Logic.parts(car, "window"))))
        lines.push(i18n("Frunk: %1", openText(frunkOpen)))
        lines.push(i18n("Trunk: %1", openText(trunkOpen)))
        lines.push(i18n("Charge port: %1", pluggedIn ? i18n("Plugged in") : openText(portOpen)))
        const sentryState = Logic.triState(car, "sentry_mode")
        lines.push(i18n("Sentry: %1", sentryState === null ? "—" : (sentryState ? i18n("On") : i18n("Off"))))
        const low = [["fl", fl], ["fr", fr], ["rl", rl], ["rr", rr]]
            .filter(t => t[1].warn).map(t => texts.tireName(t[0]))
        if (low.length > 0) lines.push(i18n("Low tire pressure: %1", low.join(", ")))
        return lines.join("\n")
    }

    Texts { id: texts }
    Look { id: look }

    implicitWidth: 2 * (readingWidth + gap) + Kirigami.Units.gridUnit * 3
    implicitHeight: Kirigami.Units.gridUnit * 7

    // ---------- parts ----------

    // One piece of the car: an outline in units that is filled, stroked or both.
    component Part: ShapePath {
        id: part
        property string path
        fillColor: "transparent"
        strokeColor: "transparent"
        strokeWidth: root.lineWidth
        joinStyle: ShapePath.RoundJoin
        scale: root.pathScale
        PathSvg { path: part.path }
    }

    component Tire: Part {
        property bool onLeft
        property real axle
        property bool low
        path: root.tirePath(onLeft, axle)
        fillColor: low ? root.lowColor : root.tireColor
    }

    // Filled when this window is open. When TeslaMate only reports that some window is open,
    // all four get an orange outline but no fill.
    component SideWindow: Part {
        property bool onLeft
        property real from
        property real to
        property var open
        path: root.windowPath(onLeft, from, to)
        fillColor: open === true ? root.openFill : root.glassColor
        strokeColor: root.edgeColor(open)
    }

    // Hinged at its front edge. Swings out and fills only when TeslaMate says which door is
    // open; when it only reports that some door is open, all four get an orange outline.
    // It sits on whole pixels, like the parts that don't move.
    component Door: Shape {
        id: door
        property bool onLeft
        property real from
        property real to
        property var open
        readonly property bool shown: open === true || open === "some"
        readonly property var across: root.side(onLeft, 14, 14 + root.doorWidth)
        property real swing: open === true ? root.doorSwing : 0
        Behavior on swing {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        x: root.u(across[0])
        y: root.u(root.snap(from))
        width: root.u(across[1]) - x
        height: root.u(root.snap(to)) - y
        transform: Rotation {
            origin.x: door.onLeft ? 0 : door.width
            origin.y: 0
            angle: door.onLeft ? door.swing : -door.swing
        }

        Part {
            path: root.doorPath(root.inUnits(door.width), root.inUnits(door.height))
            fillColor: door.open === true ? root.openFill : "transparent"
            // Closed doors are faint seams so the side doesn't read as three parallel lines.
            strokeColor: door.shown ? root.openColor : door.open === null ? "transparent" : root.faintColor
        }
    }

    // The mirrors sit on the front doors and swing with them.
    component FrontDoor: Door {
        id: frontDoor
        from: 152
        to: 266

        Part {
            path: root.mirrorPath(frontDoor.onLeft, root.inUnits(frontDoor.width))
            strokeColor: root.lineColor
        }
    }

    // A filled sign that stays upright whichever way the car lies, centered on a point of
    // the car.
    component Glyph: Shape {
        id: glyph
        property real centerX
        property real centerY
        property string path
        property color color
        readonly property point center: root.at(centerX, centerY)
        x: center.x - Math.floor(width / 2)
        y: center.y - Math.floor(height / 2)
        width: root.glyphSize
        height: root.glyphSize

        ShapePath {
            fillColor: glyph.color
            strokeColor: "transparent"
            scale: Qt.size(glyph.width / 20, glyph.height / 20)
            PathSvg { path: glyph.path }
        }
    }

    // What the car is drawn in: a multisampled layer over the whole item, placed so that
    // its texture reaches the screen pixel for pixel. Whatever is put in it is placed from
    // the item's corner.
    // Not Shape.CurveRenderer: on Qt 6.7 and 6.8 it can keep showing the paths at an old
    // scale when the row is resized several times in a row while the card lays out
    // (QTBUG-133267). A multisampled layer gives the same smooth edges, and the same ones
    // on every part. It is never turned; the car turns inside it.
    // It does not lie on the item's own area, because at a scale factor such as 125 % or
    // 150 % that rarely starts on a device pixel. A layer there reaches the screen blurred
    // if it is smoothed (layer.smooth), and with rows left out or repeated if it is not.
    // It starts on a multiple of 20 pixels of the window instead and is a multiple of 20
    // pixels wide and high, which is a whole number of device pixels at every scale factor
    // in steps of 5 %.
    // The software renderer draws nothing for a Shape inside a layer at scale factors
    // above 1, and doesn't need one (it anti-aliases on its own), so it skips it.
    component PixelLayer: Item {
        id: pixelLayer
        default property alias content: corner.data
        readonly property int grid: 20
        // Where the item is in the window, unless something above it is scaled or turned,
        // and how far that is past the grid.
        readonly property point origin: {
            let x = 0
            let y = 0
            for (let item = root; item; item = item.parent) {
                x += item.x
                y += item.y
            }
            return Qt.point(x, y)
        }
        readonly property point past: Qt.point(origin.x - Math.floor(origin.x / grid) * grid,
                                               origin.y - Math.floor(origin.y / grid) * grid)
        x: -past.x
        y: -past.y

        // The layer is on an item of its own at 0, 0, because Qt 6.12 makes a layer a
        // device pixel larger when its item is not on a device pixel of its parent.
        Item {
            width: Math.ceil((pixelLayer.past.x + root.wholeWidth) / pixelLayer.grid) * pixelLayer.grid
            height: Math.ceil((pixelLayer.past.y + root.wholeHeight) / pixelLayer.grid) * pixelLayer.grid
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.samples: 4

            // The item's corner in the layer. It is on a whole pixel even when the item
            // itself is not, so that the drawing is as sharp there.
            Item {
                id: corner
                x: Math.round(pixelLayer.past.x)
                y: Math.round(pixelLayer.past.y)
            }
        }
    }

    // A pressure with its unit beside it as a note. It never turns with the car: with the
    // nose up it is beside its wheel, and on the car's side it is above or below it.
    component Reading: Item {
        id: reading
        property var tire
        property bool onLeft
        property bool front
        // Without a unit there is no pressure either, only the dash that stands for it.
        readonly property bool known: tire.unit !== ""
        readonly property real axle: front ? root.frontAxle : root.rearAxle
        // The middle of the wheel's outer face.
        readonly property point wheel: root.at(onLeft ? root.wheelInset : root.boxWidth - root.wheelInset, axle)
        // Above or below its wheel, a reading is centered on it unless that brings it too
        // close to where an open rear door ends. Then it moves towards the end of the car,
        // at the front as far as at the rear so that both ends look alike.
        readonly property real centered: wheel.x - Math.round(width / 2)
        readonly property real limit: root.at(0, axle + (front ? root.readingReach : -root.readingReach)).x

        x: {
            let left
            if (!root.sideways)
                left = onLeft ? wheel.x - root.gap - width : wheel.x + root.gap
            else if (front)
                left = Math.max(centered, limit + root.lineGap)
            else
                left = Math.min(centered, limit - root.lineGap - width)
            return Math.max(0, Math.min(root.wholeWidth - width, left))
        }
        y: {
            let top
            if (!root.sideways)
                top = wheel.y - Math.round(height / 2)
            else
                top = onLeft ? wheel.y - root.lineGap - height : wheel.y + root.lineGap
            return Math.max(0, Math.min(root.wholeHeight - height, top))
        }
        // Text is as wide as its letters, which is rarely a whole number of pixels. The
        // unit starts on a whole pixel all the same, and so does what is beside the reading.
        readonly property real unitX: Math.round(valueLabel.implicitWidth + Kirigami.Units.smallSpacing / 2)
        width: known ? unitX + Math.ceil(unitLabel.implicitWidth) : Math.ceil(valueLabel.implicitWidth)
        height: Math.ceil(valueLabel.implicitHeight)

        PlasmaComponents3.Label {
            id: valueLabel
            text: reading.tire.value
            color: reading.tire.warn ? root.lowColor : root.textColor
            opacity: reading.known ? 1 : look.faint
            font.weight: reading.tire.warn && reading.known ? Font.DemiBold : Font.Normal
            font.features: { "tnum": 1 }
        }
        PlasmaComponents3.Label {
            id: unitLabel
            x: reading.unitX
            y: Math.round(valueLabel.baselineOffset - baselineOffset)
            text: reading.tire.unit
            opacity: look.secondary
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }

    // The tooltip covers the whole row: the readings and any swung-open door, not just the car.
    HoverHandler { id: hover }

    PlasmaComponents3.ToolTip {
        visible: hover.hovered
        text: root.summary()
    }

    // ---------- the car ----------

    PixelLayer {
        id: canvas

        // Drawn nose up and turned as a whole. From bottom to top: tires, body, frunk and
        // trunk, the glass over the cabin, side windows, doors with their mirrors, charge
        // port and cable.
        Item {
            id: drawing
            x: Math.round(root.sideways ? (root.wholeWidth + height) / 2 : (root.wholeWidth - width) / 2)
            y: Math.round(root.sideways ? (root.wholeHeight - width) / 2 : (root.wholeHeight - height) / 2)
            width: root.u(root.boxWidth)
            height: root.u(root.boxHeight)
            rotation: root.sideways ? 90 : 0
            transformOrigin: Item.TopLeft

            Shape {
                width: drawing.width
                height: drawing.height

                Tire { onLeft: true; axle: root.frontAxle; low: root.fl.warn }
                Tire { onLeft: false; axle: root.frontAxle; low: root.fr.warn }
                Tire { onLeft: true; axle: root.rearAxle; low: root.rl.warn }
                Tire { onLeft: false; axle: root.rearAxle; low: root.rr.warn }

                Part {
                    path: root.bodyPath
                    strokeColor: root.lineColor
                    strokeWidth: root.bodyLineWidth
                }
                Part {
                    path: root.frunkPath
                    fillColor: root.frunkOpen === true ? root.openFill : "transparent"
                    strokeColor: root.edgeColor(root.frunkOpen)
                }
                Part {
                    path: root.trunkPath
                    fillColor: root.trunkOpen === true ? root.openFill : "transparent"
                    strokeColor: root.edgeColor(root.trunkOpen)
                }
                Part {
                    path: root.glassPath
                    fillColor: root.glassColor
                    strokeColor: root.lineColor
                }

                SideWindow { onLeft: true; from: 178; to: 264; open: root.windowState(root.leftSeat, "front") }
                SideWindow { onLeft: true; from: 272; to: 330; open: root.windowState(root.leftSeat, "rear") }
                SideWindow { onLeft: false; from: 178; to: 264; open: root.windowState(root.rightSeat, "front") }
                SideWindow { onLeft: false; from: 272; to: 330; open: root.windowState(root.rightSeat, "rear") }
            }

            FrontDoor { onLeft: true; open: root.doorState(root.leftSeat, "front") }
            Door { onLeft: true; from: 270; to: 336; open: root.doorState(root.leftSeat, "rear") }
            FrontDoor { onLeft: false; open: root.doorState(root.rightSeat, "front") }
            Door { onLeft: false; from: 270; to: 336; open: root.doorState(root.rightSeat, "rear") }

            // An open port is expected while plugged in.
            Shape {
                width: drawing.width
                height: drawing.height

                Part {
                    path: root.portPath
                    fillColor: root.portFill
                    strokeColor: root.portLine
                }
                Part {
                    path: root.cablePath
                    strokeColor: root.pluggedIn ? root.pluggedColor : "transparent"
                    strokeWidth: root.cableWidth
                    capStyle: ShapePath.RoundCap
                }
            }
        }

        // Sentry watches through the windshield, and the lock is on the roof.
        Glyph {
            visible: root.sentry
            centerX: root.boxWidth / 2
            centerY: 162
            path: root.sentryPath
            color: root.sentryColor
        }
        Glyph {
            visible: root.locked !== null
            centerX: root.boxWidth / 2
            centerY: 250
            path: root.locked ? root.lockPath : root.unlockPath
            color: root.locked ? root.lockedColor : root.unlockedColor
        }
    }

    // ---------- tire readings ----------

    Reading { id: flReading; tire: root.fl; onLeft: true; front: true }
    Reading { id: frReading; tire: root.fr; onLeft: false; front: true }
    Reading { id: rlReading; tire: root.rl; onLeft: true; front: false }
    Reading { id: rrReading; tire: root.rr; onLeft: false; front: false }
}
