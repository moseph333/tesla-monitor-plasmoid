pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "logic.js" as Logic
import "models.js" as Models

// The car from above, showing everything about the car's body at once: a pressure reading at
// each wheel, doors that swing out when open, windows, frunk, trunk, charge port, lock and
// Sentry. Hovering lists the same status as text.
// The car lies on its side with its nose to the right, like the panel icon, or stands nose
// up, whichever draws it larger in the room the item has.
// Its colors are CarPalette's: the car's own paint, or tints of the theme's text color.
// Everything is in the car's real dimensions: 1 unit = 10 mm. The shapes come from
// models.js as a plan, drawn for each model after the top view in Tesla's owner's manual,
// in a box that ends at the mirror tips: a Model 3's body is 185 × 469.4 in it. The
// wheels sit further out than the real track so they stay visible from above.
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
    // Which car: a key from Models.KEYS.
    property string model: "3"
    readonly property var plan: Models.plan(model)
    // What the plan says about rear doors that lift like wings, or null for doors that
    // swing out.
    readonly property var falcon: plan.falcon

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

    // ---------- lines ----------

    // The charge port is green with a cable in it, orange when open and empty, and not
    // drawn when closed or while TeslaMate hasn't reported it.
    readonly property color portFill: pluggedIn ? colors.pluggedColor : portOpen ? colors.openColor : "transparent"
    readonly property color portLine: pluggedIn ? Qt.darker(colors.pluggedColor, 1.3) : portOpen ? colors.openEdge : "transparent"

    // The width of the line around a part, around the body, and of the cable.
    readonly property real lineWidth: 1
    readonly property real bodyLineWidth: 1.5
    readonly property real cableWidth: 2
    // The line that stands for a door when only the total says that some door is open, and
    // how far inside the door's outer edge it starts: clear of the body's own line.
    readonly property real doorEdgeWidth: 2
    readonly property real doorEdgeInset: 1
    readonly property real lightWidth: 1.5

    // ---------- the car, in units, nose up ----------

    readonly property real boxWidth: plan.boxWidth
    readonly property real boxHeight: plan.boxHeight
    readonly property real frontAxle: plan.frontAxle
    readonly property real rearAxle: plan.rearAxle
    // The box ends at the mirror tips. The wheels' outer faces are this far inside it.
    readonly property real wheelInset: plan.wheelInset
    // Across the car, a door starts just inside the body's side and ends short of its
    // window. An open one swings doorSwing degrees around its front edge: the rear corner
    // of a Model 3's front door, which is 116 long and hinged 16 inside the box, is then
    // doorReach outside the box (116 × sin 30° − 16 = 42).
    readonly property real doorOuter: plan.flank + 1.75
    readonly property real doorWidth: plan.belt - 2 - doorOuter
    // An open door shows its whole leaf, 19 wide whatever the door's own width: that much
    // wider towards the cabin, so that it is a panel and not a stick. Its outer edge, and
    // with it doorReach, stays.
    readonly property real leafExtra: 19 - doorWidth
    readonly property real doorSwing: 30
    readonly property real swingSin: Math.sin(doorSwing * Math.PI / 180)
    readonly property real swingCos: Math.cos(doorSwing * Math.PI / 180)
    readonly property real swingTan: Math.tan(doorSwing * Math.PI / 180)
    readonly property real doorReach: (plan.frontDoor[1] - plan.frontDoor[0]) * swingSin - doorOuter
    // How far a reading above or below a wheel may reach towards the middle of the car: an
    // open rear door ends this far ahead of the rear axle. On a Model 3, whose rear door is
    // 9 wide and 70 long from its hinge at 270, that is 36.4
    // (371.5 − 270 − 9 × sin 30° − 70 × cos 30°).
    // A rear door that lifts like a wing ends where its plan says.
    readonly property real readingReach: falcon ? rearAxle - falcon.back
                                                : rearAxle - plan.rearDoor[0] - doorWidth * swingSin
                                                  - (plan.rearDoor[1] - plan.rearDoor[0]) * swingCos

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

    // The body's side along the doors and the side windows' outer edge are long straight
    // lines along the car. They are moved, by less than half a pixel, to where such a line
    // fills whole pixels.
    readonly property real flank: crisp(plan.flank, bodyLineWidth)
    readonly property real belt: snap(plan.belt)
    readonly property string bodyPath: plan.bodyPath(flank)
    readonly property string frunkPath: plan.frunkPath
    readonly property string trunkPath: plan.trunkPath
    // The windshield and the glass over the cabin, and the rear window, which on a
    // hatchback is part of the trunk lid.
    readonly property string glassPath: plan.glassPath
    readonly property string rearGlassPath: plan.rearGlassPath
    // The beams across the roof, between the panes of glass.
    readonly property string beamPath: plan.beamPath
    // The body with the glass left out of it, for a body that is not opaque: all of
    // bodyPath, and inside it, as holes, the glass over the cabin with its beams, the
    // side windows and the doorways of open doors.
    readonly property string openBodyPath: [
        bodyPath, plan.canopyPath, plan.quarterPath,
        windowPath(true, plan.frontWindow, 0), windowPath(true, plan.rearWindow, 0),
        windowPath(false, plan.frontWindow, 0), windowPath(false, plan.rearWindow, 0),
        doorwaysPath
    ].join(" ")
    // The doorways of the open doors, as one path. A doorway comes and goes with the
    // door's leaf, which is drawn only while the door is open.
    readonly property string doorwaysPath: [leftFrontDoor, leftRearDoor, rightFrontDoor, rightRearDoor]
        .filter(door => door.open === true && !door.wing).map(door => doorwayPath(door.onLeft, door.from, door.to)).join(" ")

    // The body's left edge beside a wheel.
    function flankAt(y) { return Models.edgeAt(plan.bodyLeft(flank), y) }
    // A place across the car on the left side, or its reflection on the right.
    function reflect(onLeft, x) { return onLeft ? x : boxWidth - x }

    // What shows of a tire: its outer face and its two ends, from the body's edge outwards.
    function tirePath(onLeft, axle) {
        const face = snap(wheelInset)
        const front = snap(axle - plan.tire)
        const rear = snap(axle + plan.tire)
        const r = 4.5
        return ["M", reflect(onLeft, flankAt(front)), front, "H", reflect(onLeft, face + r),
                "Q", reflect(onLeft, face), front, reflect(onLeft, face), front + r, "V", rear - r,
                "Q", reflect(onLeft, face), rear, reflect(onLeft, face + r), rear,
                "H", reflect(onLeft, flankAt(rear)), "Z"].join(" ")
    }
    // A side window, from the plan, where its outer edge is on the belt. The whole window
    // is moved with that edge onto whole pixels, and half the width of its line further
    // in, so that the edge is sharp. With no line it is all that the window covers.
    function windowPath(onLeft, points, line) {
        return Models.placed(points, belt + inUnits(line / 2) - plan.belt, onLeft ? undefined : boxWidth)
    }
    // The leaf of an open door that is w wide and l long once it is on whole pixels,
    // measured, like the mirror on a front door, from the door's own front left corner.
    // It reaches further towards the cabin, which is to its right on the left side.
    // The corner of the leaf's extra width at the hinge is cut off along the flank, as the
    // swung door lies: square, it would reach the window behind a rear door's hinge, and an
    // open door and an open window would be one shape.
    function leafPath(onLeft, w, l) {
        const d = inUnits(lineWidth / 2)
        const r = 4
        const cut = leafExtra / swingTan
        const x0 = snap(onLeft ? 0 : -leafExtra) + d
        const x1 = snap(onLeft ? w + leafExtra : w) - d
        const y0 = d
        const y1 = snap(l) - d
        return onLeft
            ? ["M", x0 + r, y0, "H", x1 - leafExtra, "L", x1, y0 + cut,
               "V", y1 - r, "A", r, r, 0, 0, 1, x1 - r, y1,
               "H", x0 + r, "A", r, r, 0, 0, 1, x0, y1 - r,
               "V", y0 + r, "A", r, r, 0, 0, 1, x0 + r, y0, "Z"].join(" ")
            : ["M", x0 + leafExtra, y0, "H", x1 - r, "A", r, r, 0, 0, 1, x1, y0 + r,
               "V", y1 - r, "A", r, r, 0, 0, 1, x1 - r, y1,
               "H", x0 + r, "A", r, r, 0, 0, 1, x0, y1 - r,
               "V", y0 + cut, "Z"].join(" ")
    }
    // The outer edge of a door, as a line that lies inside the door, on whole pixels, and
    // whose round ends stop short of the door's: on a small car two doors' lines would
    // otherwise meet across the seam.
    function doorEdgePath(onLeft, w, l) {
        const half = inUnits(doorEdgeWidth / 2)
        const x = inUnits(doorEdgeInset) + half
        return ["M", onLeft ? x : w - x, 3 + half, "V", l - 3 - half].join(" ")
    }
    // The opening an open door leaves in the flank: where the closed door was, short of
    // the seams at its two ends, and of the window by doorwayGap pixels of paint, so that
    // a closed window beside it stays a shape of its own.
    // It starts behind the leaf's slanted front edge: ahead of that it would be a dark
    // nick between the hinge and the seam.
    readonly property real doorwayGap: 2
    function doorwayPath(onLeft, from, to) {
        const left = snap(doorOuter)
        const right = Math.max(left, belt - inUnits(doorwayGap))
        const front = from + 2 + (right - left) * swingTan
        return box(reflect(onLeft, onLeft ? left : right), Math.min(front, to - 2), reflect(onLeft, onLeft ? right : left), to - 2, 2, 0)
    }
    // A mirror grows out of the body. Its outline, from the plan, starts and ends on the
    // flank and is not closed, so its line leaves the body's own line whole.
    function mirrorPath(onLeft, w) {
        return Models.mirrorPath(plan.mirror, snap(doorOuter) - flank - inUnits(bodyLineWidth / 2), w, onLeft)
    }
    // Lights follow the corners of the car between its outline and the hood or the trunk:
    // a lens, and a line of light inside it.
    readonly property string headlightPath: plan.headlightPath
    readonly property string headlightLine: plan.headlightLine
    readonly property string taillightPath: plan.taillightPath
    readonly property string taillightLine: plan.taillightLine
    // Where one door ends and the next begins, across the shoulder from the flank to the
    // glass. The edges of a door that lifts like a wing run on across the roof.
    readonly property string seamPath: [plan.frontDoor[0], (plan.frontDoor[1] + plan.rearDoor[0]) / 2,
                                        plan.rearDoor[1]].map((y, i) => {
        const at = crisp(y, lineWidth)
        const to = falcon && i > 0 ? falcon.seam : belt
        return ["M", flank, at, "H", to, "M", boxWidth - flank, at, "H", boxWidth - to].join(" ")
    }).join(" ")
    // The charge port is on the left rear. It keeps a size that can be seen when the car
    // gets small, and then moves back to stay clear of the rear wheel.
    readonly property real portRadius: Math.max(5.5, inUnits(Kirigami.Units.smallSpacing * 0.75))
    readonly property real portX: plan.port[0]
    readonly property real portY: Math.max(plan.port[1], rearAxle + plan.tire + inUnits(1) + portRadius)
    readonly property string portPath: circle(portX, portY, portRadius)
    // From the port out to the side
    readonly property string cablePath: ["M", portX - 6, portY, "C", portX - 14, portY + 1,
                                         portX - 20, portY + 10, portX - 22, portY + 28].join(" ")

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
    // The least height at which the car lies on its side, in an item that is wider than
    // high. In less, the readings above and below the wheels leave the car less room than
    // it has standing nose up: this is where (h - readings) / the car's width passes
    // (h - pad) / the car's length.
    readonly property real sidewaysHeight: {
        const across = boxWidth - 2 * wheelInset
        return Math.floor((2 * (readingHeight + lineGap) * boxHeight - 2 * pad * across)
                          / (boxHeight - across)) + 1
    }
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
    readonly property real glyphSize: Math.min(Math.floor(u(plan.windshieldLength)), Math.max(20, Math.min(32, 2 * Math.floor(u(15)))))

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
    CarPalette {
        id: colors
        paint: root.paint
    }

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
        fillColor: low ? colors.lowColor : colors.tireColor
    }

    // Filled when this window is open. When TeslaMate only reports that some window is open,
    // all four get an orange outline but no fill.
    component SideWindow: Part {
        property bool onLeft
        property var points
        property var open
        path: root.windowPath(onLeft, points, root.lineWidth)
        fillColor: colors.openFill(open, open === null ? colors.faintGlassColor : colors.glassColor)
        strokeColor: colors.openLine(open, colors.glassLine, colors.faintGlassColor)
    }

    // Hinged at its front edge. Swings out and fills only when TeslaMate says which door is
    // open; when it only reports that some door is open, all four get an orange line along
    // their outer edge, just inside the body's own line. A door's whole outline there would
    // be a second capsule beside each outlined window, and the least certain state would be
    // the busiest. It sits on whole pixels, like the parts that don't move.
    component Door: Shape {
        id: door
        property bool onLeft
        property real from
        property real to
        property var open
        // Whether the door lifts like a wing. Then a Wing draws it while it is open, and
        // it has no leaf to swing and leaves no doorway.
        property bool wing: false
        readonly property var across: root.side(onLeft, root.doorOuter, root.doorOuter + root.doorWidth)
        property real swing: open === true && !wing ? root.doorSwing : 0
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
            // The line that stands for a door of which only the total is known lies on
            // the flank at once, also where a door was open before.
            angle: door.open === "some" ? 0 : door.onLeft ? door.swing : -door.swing
        }

        // A closed door is not drawn: the seams on the body show where it is.
        Part {
            readonly property real w: root.inUnits(door.width)
            readonly property real l: root.inUnits(door.height)
            path: door.open === true ? (door.wing ? "" : root.leafPath(door.onLeft, w, l))
                : door.open === "some" ? root.doorEdgePath(door.onLeft, w, l) : ""
            fillColor: colors.openFill(door.open, "transparent")
            strokeColor: colors.openLine(door.open, "transparent", "transparent")
            strokeWidth: door.open === "some" ? root.doorEdgeWidth : root.lineWidth
            capStyle: ShapePath.RoundCap
        }
    }

    // A rear door that is hinged along the middle of the roof and lifts like a wing, in
    // two leaves, as a Model X's do. Seen from above an open one hides its half of the
    // roof and its side window, and reaches out over the body's side, where it slides
    // out as it opens. On it are the line where its two leaves meet and the glass in
    // each: the roof's pane, which stands too steeply to show much, and the side window.
    component Wing: Shape {
        id: wing
        property bool onLeft
        property var open
        // How far it has opened, from 0 to 1.
        property real lift: open === true ? 1 : 0
        Behavior on lift {
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
        }
        readonly property bool shown: root.falcon !== null && open === true
        // For Models.reached(): nothing on the left side, the car's width on the right.
        readonly property var mirrorWidth: onLeft ? undefined : root.boxWidth
        width: root.u(root.boxWidth)
        height: root.u(root.boxHeight)
        visible: shown

        Part {
            path: wing.shown ? Models.reached(root.falcon.wing, root.flank, wing.lift, wing.mirrorWidth, true) : ""
            fillColor: colors.openColor
            strokeColor: colors.openEdge
        }
        Part {
            path: wing.shown ? root.falcon.glass.map(pane => Models.reached(pane, root.flank, 1, wing.mirrorWidth, true)).join(" ") : ""
            fillColor: Qt.rgba(colors.openEdge.r, colors.openEdge.g, colors.openEdge.b, 0.3)
            strokeColor: colors.openEdge
        }
        Part {
            path: wing.shown ? Models.reached(root.falcon.fold, root.flank, 1, wing.mirrorWidth, false) : ""
            strokeColor: colors.openEdge
            capStyle: ShapePath.FlatCap
        }
    }

    // The mirrors sit on the front doors and swing with them.
    component FrontDoor: Door {
        id: frontDoor
        from: root.plan.frontDoor[0]
        to: root.plan.frontDoor[1]

        Part {
            path: root.mirrorPath(frontDoor.onLeft, root.inUnits(frontDoor.width))
            fillColor: colors.mirrorColor
            strokeColor: colors.outlineColor
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
            color: reading.tire.warn ? colors.lowColor : colors.textColor
            opacity: reading.known ? 1 : look.faint
            font.weight: reading.tire.warn && reading.known ? Font.DemiBold : Font.Normal
            font.features: { "tnum": 1 }
            // A screen reader gets the pressure and its unit as one text.
            Accessible.name: reading.tire.text
        }
        PlasmaComponents3.Label {
            id: unitLabel
            x: reading.unitX
            y: Math.round(valueLabel.baselineOffset - baselineOffset)
            text: reading.tire.unit
            opacity: look.secondary
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            Accessible.ignored: true
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
        // Drawn nose up and turned as a whole. From bottom to top: tires, body, frunk and
        // trunk, door seams, the glass over the cabin with its beams, lights, side windows,
        // doors with their mirrors, charge port and cable.
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

                // What is black on the car outside its body, such as fender flares.
                Part {
                    path: root.plan.trimPath
                    fillColor: colors.trimColor
                }

                // The body, shaded across the car. A gradient is laid out in the Shape's own
                // pixels, whatever the path's scale. A path with a gradient keeps a fill
                // color that is not transparent, or it would not be filled at all.
                Part {
                    path: colors.painted ? root.bodyPath : root.openBodyPath
                    fillColor: colors.bodySide
                    fillGradient: LinearGradient {
                        x1: root.u(root.flank)
                        y1: 0
                        x2: root.u(root.boxWidth - root.flank)
                        y2: 0
                        GradientStop { position: 0; color: colors.bodyEdge }
                        GradientStop { position: 0.035; color: colors.bodyTurn }
                        GradientStop { position: 0.09; color: colors.bodyShoulder }
                        GradientStop { position: 0.22; color: colors.bodySide }
                        GradientStop { position: 0.36; color: colors.bodyHigh }
                        GradientStop { position: 0.5; color: colors.bodyCrown }
                        GradientStop { position: 0.64; color: colors.bodyHigh }
                        GradientStop { position: 0.78; color: colors.bodySide }
                        GradientStop { position: 0.91; color: colors.bodyShoulder }
                        GradientStop { position: 0.965; color: colors.bodyTurn }
                        GradientStop { position: 1; color: colors.bodyEdge }
                    }
                }
                // The same along the car, over the paint, and the line around the body.
                LinearGradient {
                    id: endShading
                    x1: 0
                    y1: 0
                    x2: 0
                    y2: root.u(root.plan.length)
                    GradientStop { position: 0; color: colors.tipShade }
                    GradientStop { position: 0.035; color: colors.endShade }
                    GradientStop { position: 0.11; color: colors.noShade }
                    GradientStop { position: 0.86; color: colors.noShade }
                    GradientStop { position: 0.955; color: colors.endShade }
                    GradientStop { position: 1; color: colors.tipShade }
                }
                Part {
                    path: root.bodyPath
                    // Always filled, with a shade of nothing in theme colors: a fill that
                    // only comes with the paint is drawn over the lights instead of under them.
                    fillColor: "black"
                    fillGradient: endShading
                    strokeColor: colors.outlineColor
                    strokeWidth: root.bodyLineWidth
                }
                // Hood and trunk lid: a soft light on the closed panel, solid when open.
                LinearGradient {
                    id: hoodSheen
                    x1: 0
                    y1: root.u(root.plan.hoodSpan[0])
                    x2: 0
                    y2: root.u(root.plan.hoodSpan[1])
                    GradientStop { position: 0; color: colors.noSheen }
                    GradientStop { position: 0.4; color: colors.sheenColor }
                    GradientStop { position: 1; color: colors.noSheen }
                }
                LinearGradient {
                    id: trunkSheen
                    x1: 0
                    y1: root.u(root.plan.trunkSpan[0])
                    x2: 0
                    y2: root.u(root.plan.trunkSpan[1])
                    GradientStop { position: 0; color: colors.noSheen }
                    GradientStop { position: 0.55; color: colors.sheenColor }
                    GradientStop { position: 1; color: colors.noSheen }
                }
                Part {
                    path: root.frunkPath
                    fillColor: colors.openFill(root.frunkOpen, colors.painted ? "white" : "transparent")
                    fillGradient: colors.painted && root.frunkOpen !== true ? hoodSheen : null
                    strokeColor: colors.openLine(root.frunkOpen, colors.seamColor, colors.faintSeamColor)
                }
                Part {
                    path: root.trunkPath
                    fillColor: colors.openFill(root.trunkOpen, colors.painted ? "white" : "transparent")
                    fillGradient: colors.painted && root.trunkOpen !== true ? trunkSheen : null
                    strokeColor: colors.openLine(root.trunkOpen, colors.seamColor, colors.faintSeamColor)
                }
                // Lines pressed into the hood, and the slats of a bed's cover.
                Part {
                    path: root.plan.creasePath
                    strokeColor: colors.faintSeamColor
                    capStyle: ShapePath.RoundCap
                }
                Part {
                    path: root.plan.slatPath
                    strokeColor: root.trunkOpen === true ? colors.openEdge : colors.faintSeamColor
                    capStyle: ShapePath.FlatCap
                }
                Part {
                    path: root.seamPath
                    strokeColor: colors.seamColor
                    capStyle: ShapePath.FlatCap
                }
                // Behind an open door the flank is open: dark like the cabin's glass.
                Part {
                    path: root.doorwaysPath
                    fillColor: colors.glassColor
                }
                Part {
                    path: root.beamPath
                    fillColor: colors.beamColor
                }
                LinearGradient {
                    id: glassShade
                    x1: 0
                    y1: root.u(root.plan.glassSpan[0])
                    x2: 0
                    y2: root.u(root.plan.glassSpan[1])
                    GradientStop { position: 0; color: colors.glassFront }
                    GradientStop { position: 0.3; color: colors.glassColor }
                    GradientStop { position: 0.66; color: colors.glassColor }
                    GradientStop { position: 1; color: colors.glassRear }
                }
                Part {
                    path: root.glassPath
                    fillColor: colors.glassColor
                    fillGradient: glassShade
                    strokeColor: colors.glassLine
                }
                // A hatchback's rear window opens with its trunk lid.
                Part {
                    readonly property var open: root.plan.hatch ? root.trunkOpen : false
                    path: root.rearGlassPath
                    fillColor: colors.openFill(open, colors.glassColor)
                    fillGradient: open === true ? null : glassShade
                    strokeColor: colors.openLine(open, colors.glassLine, colors.glassLine)
                }
                Part {
                    path: root.headlightPath
                    fillColor: colors.lensColor
                    strokeColor: colors.lensLine
                }
                Part {
                    path: root.headlightLine
                    strokeColor: colors.headlightColor
                    strokeWidth: root.lightWidth
                    capStyle: ShapePath.RoundCap
                }
                Part {
                    path: root.taillightPath
                    fillColor: colors.tailLensColor
                }
                Part {
                    path: root.taillightLine
                    strokeColor: colors.taillightColor
                    capStyle: ShapePath.RoundCap
                }

                // The side glass that doesn't open.
                Part {
                    path: root.plan.quarterPath
                    fillColor: colors.glassColor
                    strokeColor: colors.glassLine
                }
                SideWindow { onLeft: true; points: root.plan.frontWindow; open: root.windowState(root.leftSeat, "front") }
                SideWindow { onLeft: true; points: root.plan.rearWindow; open: root.windowState(root.leftSeat, "rear") }
                SideWindow { onLeft: false; points: root.plan.frontWindow; open: root.windowState(root.rightSeat, "front") }
                SideWindow { onLeft: false; points: root.plan.rearWindow; open: root.windowState(root.rightSeat, "rear") }
            }

            FrontDoor { id: leftFrontDoor; onLeft: true; open: root.doorState(root.leftSeat, "front") }
            Door { id: leftRearDoor; onLeft: true; from: root.plan.rearDoor[0]; to: root.plan.rearDoor[1]; open: root.doorState(root.leftSeat, "rear"); wing: root.falcon !== null }
            FrontDoor { id: rightFrontDoor; onLeft: false; open: root.doorState(root.rightSeat, "front") }
            Door { id: rightRearDoor; onLeft: false; from: root.plan.rearDoor[0]; to: root.plan.rearDoor[1]; open: root.doorState(root.rightSeat, "rear"); wing: root.falcon !== null }
            Wing { onLeft: true; open: leftRearDoor.open }
            Wing { onLeft: false; open: rightRearDoor.open }

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
                    strokeColor: root.pluggedIn ? colors.pluggedColor : "transparent"
                    strokeWidth: root.cableWidth
                    capStyle: ShapePath.RoundCap
                }
            }
        }

        // Sentry watches through the windshield, and the lock is on the roof.
        Glyph {
            visible: root.sentry
            centerX: root.boxWidth / 2
            centerY: root.plan.sentryY
            path: root.sentryPath
            color: colors.sentryColor
        }
        Glyph {
            visible: root.locked !== null
            centerX: root.boxWidth / 2
            centerY: root.plan.lockY
            path: root.locked ? root.lockPath : root.unlockPath
            color: root.locked ? colors.lockedColor : colors.unlockedColor
        }
    }

    // ---------- tire readings ----------

    Reading { id: flReading; tire: root.fl; onLeft: true; front: true }
    Reading { id: frReading; tire: root.fr; onLeft: false; front: true }
    Reading { id: rlReading; tire: root.rl; onLeft: true; front: false }
    Reading { id: rrReading; tire: root.rr; onLeft: false; front: false }
}
